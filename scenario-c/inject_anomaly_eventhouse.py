# シナリオC: Eventhouse 直接「異常注入」スクリプト（デモの起点）
#
# Eventhouse(KQL DB) の Telemetry テーブルへ Kusto ストリーミング取り込みで
# 「正常 → （任意の待機）→ 異常」を流し、Activator(factory_activator / torque_alert,
# トルク平均 >= 50Nm) を発火させる。デモの「異常発生」をワンコマンドで再現する。
#
# 公式の telemetry_sender.py（正常→異常→回復の連続送信）は壊さない。本スクリプトは
# 「固定ロットで短時間に異常バーストを入れて Activator を確実に発火させる」用途に特化する。
# 異常文脈は station_id + product_number + lot_id + detected_at(event_time) で識別する
# （fabric.instructions.md 準拠）。--lot で Activator/incident と同じロットに揃えられる。
#
# 接続情報（クラスタ URI / DB 名）はリポジトリにハードコードしない。次の優先順で解決する:
#   1) コマンドライン引数 --query-uri / --ingest-uri / --database
#   2) 環境変数 KUSTO_QUERY_URI / KUSTO_INGEST_URI / KUSTO_DATABASE
#   3) scenario-c/rti_info.json（01_create_eventhouse.ps1 が生成。.gitignore 済）
#
# 使い方:
#   uv run --no-project --with azure-kusto-data --with azure-kusto-ingest \
#     python scenario-c/inject_anomaly_eventhouse.py --lot LOT-CRCA-20260629-007
#
#   （rti_info.json が無い場合は URI/DB を引数か環境変数で渡す）

import argparse
import io
import json
import os
import random
import time
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).parent

PLANT_ID = "JP-NAGOYA-01"
# 圧入トルク上限（規格）。Activator は station 別の平均トルク >= 50 で発火する。
TORQUE_UPPER = 50.0


def iso(dt: datetime) -> str:
    return dt.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _row(ts, plant, line, station, product, lot, anomaly):
    if anomaly:
        torque = round(random.uniform(54.5, 57.5), 2)
        vib = round(random.uniform(3.9, 4.4), 2)
        temp = round(random.uniform(61.0, 63.5), 2)
        dim = round(random.uniform(9.5, 11.8), 2)
    else:
        torque = round(random.gauss(45.0, 1.5), 2)
        vib = round(random.gauss(3.5, 0.4), 2)
        temp = round(random.gauss(60.0, 2.5), 2)
        dim = round(random.gauss(8.0, 2.0), 2)
    if torque > TORQUE_UPPER or dim > 15.0:
        status, defect = "fail", 1
    elif torque > TORQUE_UPPER - 2 or vib > 4.6:
        status, defect = "warn", 0
    else:
        status, defect = "ok", 0
    return {
        "event_time": iso(ts),
        "plant_id": plant,
        "line_id": line,
        "station_id": station,
        "product_number": product,
        "lot_id": lot,
        "vibration_mm_s": vib,
        "temperature_c": temp,
        "torque_nm": torque,
        "dimension_dev_um": dim,
        "status": status,
        "defect_flag": defect,
    }


def resolve_connection(args):
    """query_uri / ingest_uri / database を 引数 > 環境変数 > rti_info.json の順で解決。"""
    query_uri = args.query_uri or os.environ.get("KUSTO_QUERY_URI")
    ingest_uri = args.ingest_uri or os.environ.get("KUSTO_INGEST_URI")
    database = args.database or os.environ.get("KUSTO_DATABASE")
    if not (query_uri and ingest_uri and database):
        info_path = HERE / "rti_info.json"
        if info_path.exists():
            db = json.loads(info_path.read_text(encoding="utf-8-sig"))["databases"][0]
            query_uri = query_uri or db["queryUri"]
            ingest_uri = ingest_uri or db["ingestUri"]
            database = database or db["name"]
    if not (query_uri and ingest_uri and database):
        raise SystemExit(
            "接続情報が不足しています。--query-uri/--ingest-uri/--database か "
            "環境変数 KUSTO_QUERY_URI/KUSTO_INGEST_URI/KUSTO_DATABASE、"
            "または scenario-c/rti_info.json を用意してください。"
        )
    return query_uri, ingest_uri, database


def make_client(query_uri, ingest_uri, database, table, mapping):
    from azure.kusto.data import KustoConnectionStringBuilder
    from azure.kusto.data.data_format import DataFormat
    from azure.kusto.ingest import IngestionProperties, ManagedStreamingIngestClient

    client = ManagedStreamingIngestClient(
        KustoConnectionStringBuilder.with_az_cli_authentication(query_uri),
        KustoConnectionStringBuilder.with_az_cli_authentication(ingest_uri),
    )
    props = IngestionProperties(
        database=database,
        table=table,
        data_format=DataFormat.JSON,
        ingestion_mapping_reference=mapping,
    )
    return client, props


def ingest(client, props, rows):
    from azure.kusto.ingest import StreamDescriptor

    payload = "\n".join(json.dumps(r) for r in rows).encode("utf-8")
    client.ingest_from_stream(StreamDescriptor(io.BytesIO(payload)), props)


def main():
    ap = argparse.ArgumentParser(
        description="Eventhouse へ固定ロットの異常テレメトリを注入し Activator を発火させる"
    )
    ap.add_argument("--product", default="CRCA", help="製品コード（既定 CRCA）")
    ap.add_argument("--station", default="ST-07-PRESS", help="ステーション（既定 圧入工程）")
    ap.add_argument("--line", default="LINE-A")
    ap.add_argument("--plant", default=PLANT_ID)
    ap.add_argument(
        "--lot",
        default=os.environ.get("DEMO_ANOMALY_LOT"),
        help="異常ロット。Activator/incident と揃える（既定: LOT-<product>-<today>-007）",
    )
    ap.add_argument("--normal", type=int, default=80, help="先に流す正常行数")
    ap.add_argument("--anomaly", type=int, default=100, help="異常行数")
    ap.add_argument(
        "--reset-wait",
        type=int,
        default=130,
        help="正常→異常の待機秒。Activator の状態をリセットして再発火させるため（既定130）",
    )
    ap.add_argument("--no-normal", action="store_true", help="正常フェーズを省略して異常のみ注入")
    ap.add_argument("--table", default="Telemetry")
    ap.add_argument("--mapping", default="telemetry_json_mapping")
    ap.add_argument("--query-uri", default=None)
    ap.add_argument("--ingest-uri", default=None)
    ap.add_argument("--database", default=None)
    args = ap.parse_args()

    lot = args.lot or f"LOT-{args.product}-{datetime.now(timezone.utc):%Y%m%d}-007"
    query_uri, ingest_uri, database = resolve_connection(args)
    client, props = make_client(query_uri, ingest_uri, database, args.table, args.mapping)

    if not args.no_normal:
        now = datetime.now(timezone.utc)
        rows = [
            _row(now, args.plant, args.line, args.station, args.product, lot, anomaly=False)
            for _ in range(args.normal)
        ]
        ingest(client, props, rows)
        print(f"[normal] {len(rows)} 行を注入。{args.reset_wait}s 待機（Activator リセット）", flush=True)
        time.sleep(args.reset_wait)

    now = datetime.now(timezone.utc)
    rows = [
        _row(now, args.plant, args.line, args.station, args.product, lot, anomaly=True)
        for _ in range(args.anomaly)
    ]
    ingest(client, props, rows)
    print(
        json.dumps(
            {
                "anomaly_sent": len(rows),
                "station_id": args.station,
                "product_number": args.product,
                "lot_id": lot,
                "event_time": iso(now),
            },
            ensure_ascii=False,
        ),
        flush=True,
    )
    print(
        "    Activator(torque_alert, 平均>=50Nm) が次回ポーリングで発火 → UDF → Logic Apps。",
        flush=True,
    )


if __name__ == "__main__":
    main()
