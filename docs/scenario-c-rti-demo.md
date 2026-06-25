# シナリオC + RTI デモ詳細案：リアルタイム品質異常 × ERP返品連携

調査・作成日: 2026-06-24
関連メモ: [manufacturing-demo-notes.md](manufacturing-demo-notes.md)

> 本書は採用シナリオ「シナリオC（返品・品質トレンド）+ RTI」の具体的なデモ設計案。
> 環境・テーブル詳細・接続手順は関連メモを参照。


---

## コンセプト（想定業種：自動車部品メーカー）
- 工場の製造ラインに取り付けた IoT センサー（振動・温度・圧入トルク・寸法検査）の**リアルタイムテレメトリを Fabric RTI に取り込み**、
  ERP 側の**受注フルフィルメント・返品データ**と突合する。
- 訴求する価値の転換:
  - **Before（ERP単体）**: 返品が積み上がってから「事後」に不良集計 → 後追い対応。
  - **After（RTI × ERP）**: 出荷前に製造ラインの異常をリアルタイム検知 →
    「その不良ロットを含む進行中の受注・影響顧客」を即特定 → **先回りでの出荷停止・顧客通知**。

---

## 結合キー（調査で確認済み）
| 役割 | ERP 側カラム | テレメトリ側 |
|---|---|---|
| 製品 | `msdyn_returnorderdetail.msdyn_productnumber`（例: `CRCA`, `BRFI-SP`, `AIDU`, `AILI`, `AUDR`, `PRBRLI`） | `product_number` |
| ロット | `msdyn_returnorderdetail.msdyn_returninginventorylotid` | `lot_id` |
| 返品理由 | `msdyn_returnorderdetail.msdyn_returnreasonv2` / `msdyn_dispositioncode` | （相関分析対象） |
| 進行中受注 | `msdyn_fulfillmentorderdetail.msdyn_product`(製品GUID)、`msdyn_fulfillmentorder.msdyn_iomstatename`, `msdyn_customername`, `msdyn_plannedshipmentdate` | `product_number` → 製品GUID 経由で突合 |

> ※実データ上、返品明細には実在の製品コード（`CRCA` ほか）が入っているため、合成テレメトリはこれらの製品コードを参照させることで「リアルタイム異常 → 既存返品実績」の物語が成立する。

### 実装で確定した結合チェーン（検証済み）
フルフィルメント受注側には製品コード（`CRCA` 等）が無く製品GUIDのみのため、返品明細をブリッジに使う:
```
Telemetry.product_number
   == external_table('ERP_ReturnOrderDetail').msdyn_productnumber      // 例: CRCA
   -- ブリッジ: ROD.msdyn_productid (製品GUID 22b274a2-…) / msdyn_productidname (Crema Café)
   == external_table('ERP_FulfillmentOrderDetail').msdyn_product       // 製品GUID で突合
   -- FOD.msdyn_fulfillmentid（親オーダーへのFK）
   == external_table('ERP_FulfillmentOrder').msdyn_fulfillmentorderid
   -- 表示: msdyn_iomstatename / msdyn_customername / msdyn_plannedshipmentdate / msdyn_shiptocountry / msdyn_name
```
検証結果（`CRCA` 異常注入時）: 進行中フルフィルメント受注 **8件**（status=`New fulfillment order line`）＋ 過去返品 **3件**。

---

## デモのストーリーボード（提示フロー）
1. **平常運転**: Real-Time Dashboard に製造ライン各ステーションのセンサー値がリアルタイムで流れる（正常）。
2. **異常発生**: 特定製品（例 `CRCA`）の圧入トルクが連続して上限超過 → テレメトリに `status=fail` が急増。
3. **RTI 異常検知**: Eventhouse(KQL) の異常検知クエリ／**Activator** がしきい値超過を検知。
4. **ERP 影響分析（ここが価値の山場）**:
   - 異常ロットの `product_number` で **進行中フルフィルメント受注**（ERP）を即抽出 →「影響を受ける顧客 Contoso/Fabrikam 等と出荷予定日」を表示。
   - 同 `product_number` の **過去返品実績**（`msdyn_returnorderdetail`）を重ね、「この製品は過去にも品質起因の返品が多い」と裏付け。
5. **自動アクション**: Activator が「該当ロットの出荷保留 + 品質・営業担当へ Teams/メール通知」を自動トリガー。
6. **経営ダッシュボード**: Power BI で「リアルタイム不良率」「影響受注金額」「製品別返品トレンド」を統合表示。

---

## Fabric アーキテクチャ構成
```
[合成テレメトリ生成器] --(JSON events)--> [Eventstream]
        |                                      |
        |                              [Eventhouse / KQL DB]  <-- 異常検知KQL
        |                                      |
        |                          [Real-Time Dashboard] / [Activator(アラート)]
        |
[ERP Lakehouse (Dataverse Link to Fabric / 既存)]
        |   OneLake ショートカット or クロスDBクエリ
        +----> [KQL で telemetry × ERP 結合] ----> [Power BI レポート]
```
- **Eventstream**: テレメトリのリアルタイム取り込み口（カスタムエンドポイント / Event Hub）。
- **Eventhouse(KQL DB)**: テレメトリ蓄積＋異常検知＋時系列分析。
- **ERP 連携**: 既存の Dataverse Lakehouse を同一ワークスペースに保持済み。KQL から OneLake ショートカット or `external_table`／クロスクエリで結合。
- **Activator**: しきい値/パターン検知で自動通知・出荷保留トリガー。
- **Power BI / Real-Time Dashboard**: 可視化。

---

## 合成テレメトリ データスキーマ（案）
```json
{
  "event_time": "2026-06-24T09:15:03.123Z",
  "plant_id": "JP-NAGOYA-01",
  "line_id": "LINE-A",
  "station_id": "ST-07-PRESS",
  "product_number": "CRCA",
  "lot_id": "LOT-CRCA-20260624-014",
  "vibration_mm_s": 3.8,
  "temperature_c": 62.4,
  "torque_nm": 48.7,
  "dimension_dev_um": 12.5,
  "status": "fail",        // ok | warn | fail
  "defect_flag": 1          // 0 | 1
}
```
- 正常時は各指標を正規分布で生成、デモの山場で特定製品（`CRCA`）に異常スパイクを注入。
- 製品コードは ERP 返品データに実在する値（`CRCA`, `BRFI-SP`, `AIDU`, `AILI`, `AUDR`, `PRBRLI`）から抽選。

---

## サンプル KQL（異常検知 → ERP 突合のイメージ）
```kql
// 1) 直近5分で fail が多発した製品ロットを検知
Telemetry
| where event_time > ago(5m)
| summarize fails = countif(status == "fail"), total = count() by product_number, lot_id
| extend defect_rate = todouble(fails) / total
| where defect_rate > 0.2 and total > 10

// 2) 影響を受ける「進行中フルフィルメント受注」をERPから突合（ショートカット/外部テーブル）
//    → product_number 一致 かつ 出荷前の受注を抽出し、顧客と出荷予定日を提示
```

---

## 合成データ生成器（実装方針）
- Python（推奨）または PowerShell で、上記スキーマの JSON を一定間隔で Eventstream のカスタムエンドポイント（Event Hub 互換）へ送信。
- パラメータ: 送信レート、製品コードの分布、異常注入の対象製品・開始時刻・継続時間。
- 「平常 → 異常 → 回復」のシナリオをタイマーで再現できるようにする。

---

## 実装結果（2026-06-24 実装・検証済み）

クライアント（ローカル Python）からリアルタイムにテレメトリを Fabric RTI へ送信し、
KQL で蓄積 → 異常検知 → ERP（OneLake ショートカット）と複合分析するパイプラインを構築・検証した。
成果物はすべて `scenario-c/` 配下。

### 作成した Fabric リソース
| リソース | 名前 | itemId | 備考 |
|---|---|---|---|
| Eventhouse | `eh_manufacturing_rti` | `<eventhouse-item-id>` | RTI 基盤 |
| KQL Database | `eh_manufacturing_rti` | `<kql-database-id>` | `Telemetry` テーブル + ERP external table |
| Eventstream | `es_client_telemetry` | `<eventstream-id>` | カスタムEP(Event Hub互換)→Eventhouse |
| Real-Time Dashboard | `RTI 製造品質モニタリング` | `<dashboard-id>` | 5タイル / 自動更新30秒 |
| ERP Lakehouse(既存) | Dataverse Link to Fabric | `<erp-lakehouse-id>` | ショートカット元 |

KQL DB クラスタ: クエリ `https://<cluster>.kusto.fabric.microsoft.com` /
取込 `https://ingest-<cluster>.kusto.fabric.microsoft.com`

### 実行手順（再現方法）
```powershell
cd scenario-c
.\01_create_eventhouse.ps1        # Eventhouse + KQL DB 作成 → rti_info.json
.\02_create_telemetry_table.ps1   # Telemetry テーブル + ストリーミング取込 + JSON マッピング
.\03_create_eventstream.ps1       # Eventstream + カスタムEP → 接続文字列を .eventstream_connection.json に保存(秘匿)
.\04_create_erp_shortcuts.ps1     # ERP 3テーブルへ OneLake ショートカット + external table 登録
.\05_run_analysis.ps1             # 異常検知 + ERP 複合分析クエリを実行
.\06_create_dashboard.ps1         # Real-Time Dashboard 作成
```
リアルタイム送信（クライアント側）:
```powershell
python -m venv .venv ; .\.venv\Scripts\pip install -r requirements.txt
# 平常15秒 → CRCA 異常30秒（10件/秒）
.\.venv\Scripts\python telemetry_sender.py --mode eventstream --rate 10 `
    --normal-seconds 15 --anomaly-seconds 30 --recovery-seconds 0 --anomaly-product CRCA
# 連続デモ（平常→異常→回復をループ）
.\.venv\Scripts\python telemetry_sender.py --mode eventstream --loop --anomaly-product CRCA
```

### 検証ログ
- Eventstream 経由で **360件**送信 → `Telemetry` テーブルに全件着地（CRCA 267件 / fail 249件）。取込遅延 約1分。
- 複合分析4クエリすべて成功（`05_run_analysis.ps1`）:
  1. lot 単位の不良率検知（CRCA 多数ロットが defect_rate=1.0 で検出）
  2. トルク上限(50Nm)超過イベント抽出
  3. 異常製品 × 進行中出荷オーダー（顧客・出荷予定日付き 8件）
  4. 異常製品 × 返品履歴（CRCA 3件）

### 重要な技術メモ（ハマりどころ）
- **OneLake ショートカット → external_table**: REST `POST /items/{kqlDbId}/shortcuts` はショートカットを
  OneLake 上に作るのみで、KQL の external table は自動登録されない（ポータル経由だと自動登録）。
  `04` で `.create external table <name> kind=delta (h@'https://onelake.dfs.fabric.microsoft.com/{ws}/{kqlDbId}/Tables/{name};impersonate')` を明示実行して解決。
- **ERP 物理パス**: `Tables/<table>`（`dbo` フォルダ無し）。SQL エンドポイントでは `dbo.<table>` として見える。
- **Eventstream 宛先**: Eventhouse 宛先の `itemId` は **KQL DB の id**（Eventhouse の id ではない）。
- **Kusto トークン**: `--resource` はクラスタの queryUri 自体（`https://kusto.fabric.microsoft.com` は失敗）。

### 成果物ファイル一覧（`scenario-c/`）
- `fabric_common.ps1` / `kql_common.ps1` … 共通ヘルパー（認証・REST・KQL 実行）
- `01`〜`06` の番号付きスクリプト … 各構築ステップ
- `telemetry_sender.py` / `requirements.txt` … リアルタイム送信器（平常→異常→回復）
- `queries/analysis.kql` … 異常検知 + ERP 複合分析クエリ集
- `rti_info.json` / `dashboard_info.json` … 作成リソースID（自動生成）
- `.eventstream_connection.json` … 接続文字列（**秘匿** / `.gitignore` 済）

---

## 次のステップ（フェーズ4 残り：ポータル設定推奨）
RTI の自動アクション層と経営レポートは、ポータルからの数クリック設定が確実なため手順のみ記載。

### Activator（自動通知・出荷保留トリガー）
1. Real-Time Dashboard `RTI 製造品質モニタリング` を開き、`品質異常検知` タイルの **… → アラートの設定**。
2. 条件: `defect_rate > 0.2`（または `トルク上限超過イベント` タイルで `torque_nm > 50`）。
3. アクション: Teams / メール通知（品質・営業担当）。Power Automate 連携で「出荷保留フラグ更新」も可能。
4. 代替: Real-Time Hub → Eventstream `es_client_telemetry` から直接 Activator ルールを作成。

### Power BI（経営ダッシュボード）
1. KQL DB `eh_manufacturing_rti` を DirectQuery でセマンティックモデルに接続
   （`Telemetry` 集計 + `external_table('ERP_*')` 結合の KQL 関数を公開）。
2. ビジュアル: 「リアルタイム不良率」「影響受注金額」「製品別返品トレンド」。
3. シナリオA の `wh_fulfillment_demo` セマンティックモデルと組み合わせ、製造×受注×返品を統合表示。
