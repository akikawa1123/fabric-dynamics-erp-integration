# デモ手順（シナリオC + RTI：リアルタイム品質異常 × ERP 複合分析）

当日の実演手順をまとめたランブック。構築・スクリプト詳細は [../README.md](../README.md) を参照。

> インフラ（01〜04, 06, 07, 09）は**構築済み**。当日は基本「送信を流す → 見せる」だけ。
> ターミナルを2枚開いておく（`cd C:\work\seall_demo\scenario-c`）。

## 役割分担
| 見せたいもの | 使うもの | 鮮度 |
|---|---|---|
| リアルタイム品質監視（異常の発生をその場で） | Real-Time Dashboard ＋ `05`（KQL） | **数秒〜1分**（即時） |
| ERP 複合分析（出荷影響・返品突合） | `08`（レイクハウス SQL エンドポイント） | **約1分**（Eventstream → Lakehouse 直送宛先） |

> Eventstream に Lakehouse 宛先（`09`）を追加済み。`--mode eventstream` で送ると **Eventhouse（ダッシュボード）と Lakehouse（T-SQL）の両方に約1分で到達**するため、事前送信は不要。

## パターン1：リアルタイム重視（推奨・短時間）
1. **ダッシュボードを開く**：ワークスペース → Real-Time Dashboard「RTI 製造品質モニタリング」。自動更新を 10〜30秒に設定。
2. **送信開始（ターミナル1）**
   ```powershell
   .\.venv\Scripts\python telemetry_sender.py --mode kusto --loop --anomaly-product CRCA
   ```
   ※ `--mode kusto` は取込遅延がほぼ無く、ダッシュボードが即反応する。
3. **異常が出たら複合分析（ターミナル2）**
   ```powershell
   .\05_run_analysis.ps1
   ```
   異常製品 CRCA → 進行中出荷オーダー・返品履歴を KQL で即突合。
4. **終了**：ターミナル1で `Ctrl+C`。

## パターン2：レイクハウス側の複合分析も見せる（事前準備不要）
Eventstream の Lakehouse 宛先（`09`）により約1分で反映されるため、その場で見せられる。
1. **送信開始（ターミナル1）** — 今回は `--mode eventstream`（ダッシュボードと Lakehouse の両方に到達）
   ```powershell
   .\.venv\Scripts\python telemetry_sender.py --mode eventstream --loop --anomaly-product CRCA
   ```
2. ダッシュボードでリアルタイムの異常を見せる（約1分遅延）。
3. 締めに**レイクハウス側の複合分析**を実行（ターミナル2）
   ```powershell
   .\08_run_lakehouse_analysis.ps1
   ```
   「Eventstream から Lakehouse に直接取り込まれた Telemetry（Delta）を、T-SQL で ERP と結合できる」を提示。

## ストーリー（話す順）
1. **平常運転** … ライン正常、ダッシュボードは緑。
2. **異常発生** … プレス工程でトルク50Nm超過 → 不良率がリアルタイムに急上昇。
3. **影響分析** … 異常製品 CRCA（Crema Café）に紐づく **未出荷オーダー** と **過去の返品** を ERP と即突合 → 出荷停止・顧客への先回り対応。

## デモ開始前の必須操作（容量再開時）
> ⚠️ **Fabric 容量を停止（pause）すると Eventstream と Activator も停止する。** デモ前に容量を再開（resume）したら、以下を必ず確認・再開すること。

1. **Activator を ON に戻す**
   - コスト節約のため、通常時は Activator（`act_quality_alerts`）の各ルールを**停止（OFF）**にしている。
   - デモ前に Activator を開き、ルール「トルク異常値」を **ON（実行中）** に戻す。
   - ※ ルールが OFF のままだと、トルク 50 超過でも **Teams 通知が飛ばない**。
2. **Eventstream の稼働を確認**
   - 容量停止で Eventstream（`es_client_telemetry`）も止まるため、再開後に**ソース／宛先が実行中（Running）か**を確認する。
   - 停止していたら Eventstream を開いて再開（Activate）する。これが止まっていると `--mode eventstream` 送信が Eventhouse / Lakehouse に届かない。

## 直前チェック
```powershell
# 必要ファイルの存在確認
Test-Path .\.eventstream_connection.json, .\.venv\Scripts\python.exe, .\rti_info.json, .\dashboard_info.json, .\lakehouse_info.json
```

## トラブルシュート
- **Teams 通知が飛ばない** … Activator のルールが **OFF のまま**になっていないか確認（デモ前に ON に戻す）。容量を再開した直後は特に要注意。
- **送信しても何も届かない（eventstream モード）** … Fabric 容量停止で **Eventstream が止まっている**可能性。Eventstream を開いて稼働状態を確認し、停止していれば再開する。
- **ダッシュボードに出ない** … `--mode kusto` か確認（eventstream は約1分遅延）。自動更新が有効か確認。
- **08 が「該当データなし」** … `--mode eventstream` で送信したか確認（`--mode kusto` は Eventhouse 直送で Lakehouse には届かない）。Lakehouse 宛先の反映は約1分。即時確認は `05`（KQL）。
- Telemetry の行数確認（SQL エンドポイント）は [../README.md](../README.md) の手順を参照。
