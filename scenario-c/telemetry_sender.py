# シナリオC RTI: クライアント側リアルタイムテレメトリ送信器
# 製造ライン IoT センサーの合成テレメトリを「平常 → 異常 → 回復」のシナリオで
# Fabric RTI へリアルタイム送信する。
#
# 送信モード:
#   eventstream … Eventstream のカスタムエンドポイント(Event Hub互換)へ送信(既定/推奨)
#   kusto       … Eventhouse へ直接ストリーミング取り込み(フォールバック)
#
# 使い方は README.md / requirements.txt を参照。

import argparse
import json
import os
import random
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).parent

# ERP 返品データに実在する製品コード
PRODUCTS = ["CRCA", "BRFI-SP", "AIDU", "AILI", "AUDR", "PRBRLI"]
PLANT_ID = "JP-NAGOYA-01"
LINES = ["LINE-A", "LINE-B"]
STATIONS = ["ST-03-WELD", "ST-05-FIT", "ST-07-PRESS", "ST-09-INSPECT"]

# 平常時の各指標の基準(平均, 標準偏差)
NOMINAL = {
    "vibration_mm_s": (3.5, 0.4),
    "temperature_c": (60.0, 2.5),
    "torque_nm": (45.0, 1.5),
    "dimension_dev_um": (8.0, 2.0),
}
# 圧入トルクの上限しきい値(これを超えると不良)
TORQUE_UPPER = 50.0

_running = True


def _stop(signum, frame):
    global _running
    _running = False
    print("\n[停止要求] 送信を終了します...", flush=True)


signal.signal(signal.SIGINT, _stop)
signal.signal(signal.SIGTERM, _stop)


def lot_id(product: str) -> str:
    day = datetime.now(timezone.utc).strftime("%Y%m%d")
    seq = random.randint(1, 30)
    return f"LOT-{product}-{day}-{seq:03d}"


def gen_event(anomaly: bool, anomaly_product: str) -> dict:
    """1件のテレメトリイベントを生成。anomaly=True かつ対象製品なら異常値を注入。"""
    # 異常フェーズでも ST-07-PRESS 以外のステーションは平常値を継続送信する。
    # 異常イベントは一定割合(60%)だけ ST-07-PRESS / 対象製品 に注入し、
    # 残りは通常どおり全ステーションからランダム生成する。
    inject_anomaly = anomaly and random.random() < 0.6
    if inject_anomaly:
        product = anomaly_product
        station = "ST-07-PRESS"
        line = "LINE-A"
    else:
        product = random.choice(PRODUCTS)
        station = random.choice(STATIONS)
        line = random.choice(LINES)

    vib = random.gauss(*NOMINAL["vibration_mm_s"])
    temp = random.gauss(*NOMINAL["temperature_c"])
    torque = random.gauss(*NOMINAL["torque_nm"])
    dim = random.gauss(*NOMINAL["dimension_dev_um"])

    if inject_anomaly:
        # 圧入トルクが上限を連続超過（主指標）。
        # 振動・温度・寸法は平常よりわずかに上振れする程度に抑え、トルクほど目立たせない。
        torque = random.gauss(54.0, 1.8)
        vib = random.gauss(4.1, 0.4)
        temp = random.gauss(62.5, 2.0)
        dim = random.gauss(10.5, 1.8)

    # ステータス判定
    if torque > TORQUE_UPPER or dim > 15.0:
        status = "fail"
        defect = 1
    elif torque > TORQUE_UPPER - 2 or vib > 4.6:
        status = "warn"
        defect = 0
    else:
        status = "ok"
        defect = 0

    return {
        "event_time": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "plant_id": PLANT_ID,
        "line_id": line,
        "station_id": station,
        "product_number": product,
        "lot_id": lot_id(product),
        "vibration_mm_s": round(vib, 2),
        "temperature_c": round(temp, 2),
        "torque_nm": round(torque, 2),
        "dimension_dev_um": round(dim, 2),
        "status": status,
        "defect_flag": defect,
    }


# ---------------- 送信バックエンド ----------------
class EventstreamSender:
    """Eventstream カスタムエンドポイント(Event Hub互換)へ送信"""

    def __init__(self):
        from azure.eventhub import EventHubProducerClient

        conn_path = HERE / ".eventstream_connection.json"
        conn_str = os.environ.get("EVENTSTREAM_CONNECTION_STRING")
        eh_name = os.environ.get("EVENTSTREAM_EVENTHUB_NAME")
        if not conn_str and conn_path.exists():
            cfg = json.loads(conn_path.read_text(encoding="utf-8-sig"))
            conn_str = cfg["primaryConnectionString"]
            eh_name = cfg.get("eventHubName")
        if not conn_str:
            raise SystemExit(
                "接続文字列がありません。03_create_eventstream.ps1 を実行するか "
                "EVENTSTREAM_CONNECTION_STRING を設定してください。"
            )
        # カスタムエンドポイントの接続文字列に EntityPath が含まれない場合は eventhub_name を渡す
        kwargs = {"conn_str": conn_str}
        if eh_name and "EntityPath=" not in conn_str:
            kwargs["eventhub_name"] = eh_name
        self.producer = EventHubProducerClient.from_connection_string(**kwargs)
        print(f"[eventstream] 接続準備完了 (eventhub={eh_name})", flush=True)

    def send(self, events):
        from azure.eventhub import EventData

        batch = self.producer.create_batch()
        for e in events:
            batch.add(EventData(json.dumps(e)))
        self.producer.send_batch(batch)

    def close(self):
        try:
            self.producer.close()
        except Exception:
            pass


class KustoSender:
    """Eventhouse へ直接ストリーミング取り込み(フォールバック)"""

    def __init__(self):
        from azure.kusto.data import KustoConnectionStringBuilder
        from azure.kusto.data.data_format import DataFormat
        from azure.kusto.ingest import (
            ManagedStreamingIngestClient,
            IngestionProperties,
        )

        info = json.loads((HERE / "rti_info.json").read_text(encoding="utf-8-sig"))
        db = info["databases"][0]
        ingest_uri = db["ingestUri"]
        query_uri = db["queryUri"]
        self.db_name = db["name"]

        kcsb = KustoConnectionStringBuilder.with_az_cli_authentication(query_uri)
        self.client = ManagedStreamingIngestClient(
            KustoConnectionStringBuilder.with_az_cli_authentication(query_uri),
            KustoConnectionStringBuilder.with_az_cli_authentication(ingest_uri),
        )
        self.props = IngestionProperties(
            database=self.db_name,
            table="Telemetry",
            data_format=DataFormat.JSON,
            ingestion_mapping_reference="telemetry_json_mapping",
        )
        print(f"[kusto] 直接取り込み準備完了 (db={self.db_name})", flush=True)

    def send(self, events):
        import io
        from azure.kusto.ingest import StreamDescriptor

        payload = "\n".join(json.dumps(e) for e in events).encode("utf-8")
        stream = io.BytesIO(payload)
        self.client.ingest_from_stream(StreamDescriptor(stream), self.props)

    def close(self):
        pass


def make_sender(mode: str):
    if mode == "eventstream":
        return EventstreamSender()
    if mode == "kusto":
        return KustoSender()
    raise SystemExit(f"未知のモード: {mode}")


# ---------------- クリーンアップ(古い時系列データの全削除) ----------------
def _az_token(resource: str) -> str:
    """az CLI からアクセストークンを取得"""
    out = subprocess.run(
        ["az", "account", "get-access-token", "--resource", resource, "--query", "accessToken", "-o", "tsv"],
        capture_output=True, text=True, shell=(os.name == "nt"),
    )
    if out.returncode != 0:
        raise SystemExit(f"az トークン取得に失敗 ({resource}): {out.stderr.strip()}")
    return out.stdout.strip()


def reset_kql():
    """Eventhouse(KQL) の Telemetry を全クリア(スキーマは保持)"""
    info_path = HERE / "rti_info.json"
    if not info_path.exists():
        print("[reset:kql] rti_info.json が無いためスキップ", flush=True)
        return
    from azure.kusto.data import KustoClient, KustoConnectionStringBuilder

    info = json.loads(info_path.read_text(encoding="utf-8-sig"))
    db = info["databases"][0]
    db_name = db["name"]
    client = KustoClient(KustoConnectionStringBuilder.with_az_cli_authentication(db["queryUri"]))
    client.execute_mgmt(db_name, ".clear table Telemetry data")
    print(f"[reset:kql] Telemetry をクリアしました (db={db_name})", flush=True)


def _onelake_list(ws: str, directory: str, token: str):
    """OneLake DFS でディレクトリ直下を一覧 -> [(name, isDirectory), ...]"""
    url = (
        f"https://onelake.dfs.fabric.microsoft.com/{ws}"
        f"?resource=filesystem&recursive=false&directory={urllib.parse.quote(directory)}"
    )
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    out = []
    for p in data.get("paths", []):
        name = (p.get("name") or "").rstrip("/")
        is_dir = str(p.get("isDirectory", "false")).lower() == "true"
        out.append((name, is_dir))
    return out


def reset_lakehouse():
    """Lakehouse の Telemetry Delta テーブルを削除(=ドロップ)。Eventstream 送信で再作成される。"""
    lh_path = HERE / "lakehouse_info.json"
    cfg_path = HERE / "config.local.json"
    if not lh_path.exists():
        print("[reset:lakehouse] lakehouse_info.json が無いためスキップ", flush=True)
        return
    lh = json.loads(lh_path.read_text(encoding="utf-8-sig"))
    ws = os.environ.get("FABRIC_WORKSPACE_ID")
    if not ws and cfg_path.exists():
        ws = json.loads(cfg_path.read_text(encoding="utf-8-sig")).get("workspaceId")
    if not ws:
        print("[reset:lakehouse] workspaceId 不明のためスキップ", flush=True)
        return
    lh_id = lh["lakehouseId"]
    token = _az_token("https://storage.azure.com")
    base = f"{lh_id}/Tables"

    # スキーマ無効(Tables/Telemetry) / 有効(Tables/<schema>/Telemetry) の両対応で実体を探す
    target = None
    top = _onelake_list(ws, base, token)
    for name, is_dir in top:
        if is_dir and name.split("/")[-1] == "Telemetry":
            target = name
            break
    if target is None:
        for name, is_dir in top:
            if not is_dir:
                continue
            for sub, sdir in _onelake_list(ws, name, token):
                if sdir and sub.split("/")[-1] == "Telemetry":
                    target = sub
                    break
            if target:
                break
    if target is None:
        print("[reset:lakehouse] Telemetry テーブルが見つかりません(未作成?)。スキップ", flush=True)
        return

    del_url = f"https://onelake.dfs.fabric.microsoft.com/{ws}/{urllib.parse.quote(target)}?recursive=true"
    req = urllib.request.Request(del_url, method="DELETE", headers={"Authorization": f"Bearer {token}"})
    try:
        urllib.request.urlopen(req)
        print(f"[reset:lakehouse] Telemetry を削除しました ({target})。Eventstream 送信で再作成されます。", flush=True)
    except urllib.error.HTTPError as e:
        print(f"[reset:lakehouse] 削除失敗 HTTP {e.code}: {e.read().decode('utf-8', 'ignore')[:200]}", flush=True)


def reset_all():
    """Lakehouse と KQL の Telemetry を両方クリーンアップ"""
    print("=== クリーンアップ開始(Lakehouse / KQL の Telemetry を全削除) ===", flush=True)
    try:
        reset_lakehouse()
    except Exception as ex:
        print(f"[reset:lakehouse] エラー: {ex}", flush=True)
    try:
        reset_kql()
    except Exception as ex:
        print(f"[reset:kql] エラー: {ex}", flush=True)
    print("=== クリーンアップ完了 ===", flush=True)


def run_phase(sender, label, seconds, rate, anomaly, anomaly_product, batch_secs=1.0):
    """指定秒数だけ rate(件/秒) でイベントを送信"""
    print(f"=== フェーズ: {label} ({seconds}s, {rate}件/秒, anomaly={anomaly}) ===", flush=True)
    end = time.time() + seconds
    sent = 0
    while _running and time.time() < end:
        n = max(1, int(rate * batch_secs))
        events = [gen_event(anomaly, anomaly_product) for _ in range(n)]
        try:
            sender.send(events)
            sent += len(events)
        except Exception as ex:
            print(f"[送信エラー] {ex}", flush=True)
            time.sleep(2)
            continue
        fails = sum(1 for e in events if e["status"] == "fail")
        print(f"  +{len(events)}件 送信 (fail={fails}) 累計={sent}", flush=True)
        time.sleep(batch_secs)
    return sent


def main():
    p = argparse.ArgumentParser(description="シナリオC RTI リアルタイムテレメトリ送信器")
    p.add_argument("--mode", choices=["eventstream", "kusto"], default="eventstream")
    p.add_argument("--rate", type=float, default=5, help="送信レート(件/秒)")
    p.add_argument("--normal-seconds", type=int, default=60, help="平常運転の秒数")
    p.add_argument("--anomaly-seconds", type=int, default=60, help="異常注入の秒数")
    p.add_argument("--recovery-seconds", type=int, default=30, help="回復運転の秒数")
    p.add_argument("--anomaly-product", default="CRCA", help="異常を注入する製品コード")
    p.add_argument("--loop", action="store_true", help="シナリオを繰り返す")
    p.add_argument("--normal-only", action="store_true", help="平常運転のみ(異常注入なし)")
    p.add_argument("--reset", action="store_true", help="送信前に Lakehouse/KQL の Telemetry を全削除する")
    p.add_argument("--reset-only", action="store_true", help="Lakehouse/KQL の Telemetry を全削除して終了(送信しない)")
    args = p.parse_args()

    if args.reset or args.reset_only:
        reset_all()
    if args.reset_only:
        return

    sender = make_sender(args.mode)
    total = 0
    try:
        while _running:
            total += run_phase(sender, "平常運転", args.normal_seconds, args.rate, False, args.anomaly_product)
            if not args.normal_only and _running:
                total += run_phase(sender, f"異常発生({args.anomaly_product})", args.anomaly_seconds, args.rate, True, args.anomaly_product)
                total += run_phase(sender, "回復運転", args.recovery_seconds, args.rate, False, args.anomaly_product)
            if not args.loop:
                break
    finally:
        sender.close()
        print(f"[完了] 合計 {total} 件を送信しました。", flush=True)


if __name__ == "__main__":
    main()
