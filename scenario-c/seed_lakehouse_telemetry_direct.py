# シナリオC: Lakehouse Telemetry 直接シード（Eventstream バイパスのフォールバック）
#
# 通常の取り込み経路（telemetry_sender.py → Eventstream es_client_telemetry
# → Lakehouse lh_quality_analytics の Delta テーブル Telemetry）が使えない場合に、
# OneLake へ直接 Delta 書き込みして「工場 live」デモ用データを復旧する。
# 例: 容量の一時停止で Eventstream ノードが Inactive 化し、公開 REST で再開できないとき。
#
# 重要:
#   - Eventstream 着地時のスキーマ（基本12列 + EventEnqueuedUtcTime:datetime2）を再現する。
#     Data Agent の例示クエリ（scenario-c/data_agent/fewshots.json）は時間フィルタに
#     EventEnqueuedUtcTime を使うため、この列が無いと NL2SQL が失敗する。
#   - 異常は station_id + product_number + lot_id で識別できるよう固定ロットに集約する。
#   - 製品単位の受注突合は candidate 前提。本シードは「確定ロット影響」を主張しない。
#   - 認証は DefaultAzureCredential（キーレス。サインインユーザー / マネージドID）。
#   - 母数・定数は telemetry_sender.py をミラーする（平常→異常→回復シナリオ）。
#
# 使い方:
#   uv run --no-project --with deltalake --with pyarrow --with azure-identity \
#     python scenario-c/seed_lakehouse_telemetry_direct.py \
#     --workspace-id <WS_GUID> --lakehouse-id <LH_GUID>
#
#   WS/LH は環境変数 FABRIC_WORKSPACE_ID / LH_QUALITY_ANALYTICS_ID でも指定可。

import argparse
import os
import random
from datetime import datetime, timedelta, timezone

import pyarrow as pa
from azure.identity import DefaultAzureCredential
from deltalake import write_deltalake

# --- telemetry_sender.py と同じ母数・定数 ---
PRODUCTS = ["CRCA", "BRFI-SP", "AIDU", "AILI", "AUDR", "PRBRLI"]
PLANT_ID = "JP-NAGOYA-01"
LINES = ["LINE-A", "LINE-B"]
STATIONS = ["ST-03-WELD", "ST-05-FIT", "ST-07-PRESS", "ST-09-INSPECT"]
NOMINAL = {
    "vibration_mm_s": (3.5, 0.4),
    "temperature_c": (60.0, 2.5),
    "torque_nm": (45.0, 1.5),
    "dimension_dev_um": (8.0, 2.0),
}
ANOMALY = {
    "vibration_mm_s": (4.1, 0.4),
    "temperature_c": (62.5, 2.0),
    "torque_nm": (54.0, 1.8),
    "dimension_dev_um": (10.5, 1.8),
}
TORQUE_UPPER = 50.0

# Eventstream 着地スキーマ（EventEnqueuedUtcTime はシステム注入列）
SCHEMA = pa.schema(
    [
        ("EventEnqueuedUtcTime", pa.timestamp("us", tz="UTC")),
        ("event_time", pa.string()),
        ("plant_id", pa.string()),
        ("line_id", pa.string()),
        ("station_id", pa.string()),
        ("product_number", pa.string()),
        ("lot_id", pa.string()),
        ("vibration_mm_s", pa.float64()),
        ("temperature_c", pa.float64()),
        ("torque_nm", pa.float64()),
        ("dimension_dev_um", pa.float64()),
        ("status", pa.string()),
        ("defect_flag", pa.int64()),
    ]
)


def _status(torque: float, dim: float, vib: float) -> tuple[str, int]:
    if torque > TORQUE_UPPER or dim > 15.0:
        return "fail", 1
    if torque > TORQUE_UPPER - 2 or vib > 4.6:
        return "warn", 0
    return "ok", 0


def _row(ts, product, line, station, lot, torque, vib, temp, dim) -> dict:
    status, defect = _status(torque, dim, vib)
    return {
        "EventEnqueuedUtcTime": ts,
        "event_time": ts.isoformat().replace("+00:00", "Z"),
        "plant_id": PLANT_ID,
        "line_id": line,
        "station_id": station,
        "product_number": product,
        "lot_id": lot,
        "vibration_mm_s": round(vib, 2),
        "temperature_c": round(temp, 2),
        "torque_nm": round(torque, 2),
        "dimension_dev_um": round(dim, 2),
        "status": status,
        "defect_flag": defect,
    }


def generate(now, anomaly_product, normal, anomaly, recovery, seed, keep_open=False, lot=None):
    """平常→異常→回復のシナリオで合成テレメトリ行を生成する。

    時間フィルタは MAX(EventEnqueuedUtcTime) 基準の相対窓のため、絶対時刻ではなく
    「最新からの相対分布」が重要。異常は直近30分窓に収まる 6-25 分前に集約する。
    keep_open=True のときは異常を直近0-20分に置き回復を抑制し、最新時刻＝異常に揃える
    （デモで「異常継続中(open)」を確実に見せ、回復で解消済みに見えるのを防ぐ）。
    lot を指定すると異常ロットを固定する（Activator/incident と同一ロットに揃えるため）。
    """
    rng = random.Random(seed)
    today = now.strftime("%Y%m%d")
    rows = []
    if keep_open:
        recovery = 0

    # 平常運転（全製品・全ステーション、過去60分に分布）
    for _ in range(normal):
        ts = now - timedelta(minutes=rng.uniform(0, 60))
        product = rng.choice(PRODUCTS)
        rows.append(
            _row(
                ts,
                product,
                rng.choice(LINES),
                rng.choice(STATIONS),
                f"LOT-{product}-{today}-{rng.randint(1, 30):03d}",
                rng.gauss(*NOMINAL["torque_nm"]),
                rng.gauss(*NOMINAL["vibration_mm_s"]),
                rng.gauss(*NOMINAL["temperature_c"]),
                rng.gauss(*NOMINAL["dimension_dev_um"]),
            )
        )

    # 異常（固定ロット・ST-07-PRESS・圧入トルクが上限を連続超過）
    # keep_open=True は直近0-20分（最新＝異常）、それ以外は直近6-25分。
    anomaly_window = (0, 20) if keep_open else (6, 25)
    anomaly_lot = lot or f"LOT-{anomaly_product}-{today}-007"
    for _ in range(anomaly):
        ts = now - timedelta(minutes=rng.uniform(*anomaly_window))
        rows.append(
            _row(
                ts,
                anomaly_product,
                "LINE-A",
                "ST-07-PRESS",
                anomaly_lot,
                rng.gauss(*ANOMALY["torque_nm"]),
                rng.gauss(*ANOMALY["vibration_mm_s"]),
                rng.gauss(*ANOMALY["temperature_c"]),
                rng.gauss(*ANOMALY["dimension_dev_um"]),
            )
        )

    # 回復運転（別ロット・直近6分、平常値）。MAX をほぼ現在時刻に揃える。
    recovery_lot = f"LOT-{anomaly_product}-{today}-008"
    for _ in range(recovery):
        ts = now - timedelta(minutes=rng.uniform(0, 6))
        rows.append(
            _row(
                ts,
                anomaly_product,
                "LINE-A",
                "ST-07-PRESS",
                recovery_lot,
                rng.gauss(*NOMINAL["torque_nm"]),
                rng.gauss(*NOMINAL["vibration_mm_s"]),
                rng.gauss(*NOMINAL["temperature_c"]),
                rng.gauss(*NOMINAL["dimension_dev_um"]),
            )
        )

    return rows, anomaly_lot


def main():
    ap = argparse.ArgumentParser(
        description="Lakehouse Telemetry 直接シード（Eventstream バイパスのフォールバック）"
    )
    ap.add_argument("--workspace-id", default=os.environ.get("FABRIC_WORKSPACE_ID"))
    ap.add_argument("--lakehouse-id", default=os.environ.get("LH_QUALITY_ANALYTICS_ID"))
    ap.add_argument("--table", default="Telemetry")
    ap.add_argument("--anomaly-product", default="CRCA")
    ap.add_argument("--normal", type=int, default=380, help="平常運転の行数")
    ap.add_argument("--anomaly", type=int, default=80, help="異常注入の行数")
    ap.add_argument("--recovery", type=int, default=40, help="回復運転の行数")
    ap.add_argument("--seed", type=int, default=None, help="乱数シード（再現用、任意）")
    ap.add_argument(
        "--keep-open",
        action="store_true",
        help="異常を最新時刻まで継続させ回復を抑制（デモで open incident を確実に見せる）",
    )
    ap.add_argument(
        "--lot",
        default=os.environ.get("DEMO_ANOMALY_LOT"),
        help="異常ロットを固定（例: LOT-CRCA-20260629-007）。Activator/incident と同一ロットに揃える用。",
    )
    ap.add_argument(
        "--mode",
        choices=["overwrite", "append"],
        default="overwrite",
        help="overwrite=スキーマごと置換 / append=既存スキーマへ追記",
    )
    args = ap.parse_args()
    if not args.workspace_id or not args.lakehouse_id:
        raise SystemExit(
            "--workspace-id と --lakehouse-id（または環境変数 FABRIC_WORKSPACE_ID / "
            "LH_QUALITY_ANALYTICS_ID）が必要です。"
        )

    now = datetime.now(timezone.utc).replace(microsecond=0)
    rows, anomaly_lot = generate(
        now, args.anomaly_product, args.normal, args.anomaly, args.recovery, args.seed, args.keep_open,
        args.lot,
    )

    token = DefaultAzureCredential().get_token("https://storage.azure.com/.default").token
    path = (
        f"abfss://{args.workspace_id}@onelake.dfs.fabric.microsoft.com/"
        f"{args.lakehouse_id}/Tables/{args.table}"
    )
    table = pa.table({name: [r[name] for r in rows] for name in SCHEMA.names}, schema=SCHEMA)
    storage_options = {"bearer_token": token, "use_fabric_endpoint": "true"}

    if args.mode == "overwrite":
        try:
            write_deltalake(
                path, table, mode="overwrite", schema_mode="overwrite",
                storage_options=storage_options,
            )
        except TypeError:  # 古い deltalake は overwrite_schema を使う
            write_deltalake(
                path, table, mode="overwrite", overwrite_schema=True,
                storage_options=storage_options,
            )
    else:
        write_deltalake(path, table, mode="append", storage_options=storage_options)

    fails = sum(1 for r in rows if r["status"] == "fail")
    anomaly_fails = sum(1 for r in rows if r["lot_id"] == anomaly_lot and r["status"] == "fail")
    anomaly_total = sum(1 for r in rows if r["lot_id"] == anomaly_lot)
    latest = max(r["EventEnqueuedUtcTime"] for r in rows).isoformat()
    print(f"[OK] {table.num_rows} 行を書き込みました（mode={args.mode}）→ {args.table}")
    print(f"     fails={fails} / 異常ロット {anomaly_lot}: {anomaly_fails}/{anomaly_total} fail")
    print(f"     MAX EventEnqueuedUtcTime ~= {latest}")
    print("     確認: Data Agent プレイグラウンドで「今、品質異常は出ている？」「トルクが規格上限を超えたイベントを直近で」")


if __name__ == "__main__":
    main()
