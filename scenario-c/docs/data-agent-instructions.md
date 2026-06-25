# Fabric データエージェント設定：lh_quality_analytics（単一ソース / クロスドメイン T-SQL）

工場ラインの **Telemetry**（リアルタイム品質テレメトリ）と **ERP 3 テーブル**（フルフィルメント受注／受注明細／返品明細）を、
**1 つの Lakehouse `lh_quality_analytics`** にまとめ、**単一データソース**として 1 つの **Fabric データエージェント（Data Agent）**
から自然言語で照会できるようにする設定ドキュメント。

| ソース | 種別 | 公開対象 | 生成言語 | 利用ペルソナ |
|---|---|---|---|---|
| `lh_quality_analytics` | Lakehouse（tables / SQL analytics endpoint） | `Telemetry` / `ERP_FulfillmentOrder` / `ERP_FulfillmentOrderDetail` / `ERP_ReturnOrderDetail` | T-SQL (NL2SQL) | 🏭 工場（品質）＋ 🧑‍💼 営業 |

想定ユーザーは 2 ペルソナ + 横断:

| ペルソナ | 主な用途 |
|---|---|
| 🏭 **工場（品質）担当** | 品質異常の発生有無と原因（製品／ロット／ステーション／トルク）を調査 |
| 🧑‍💼 **営業担当** | 顧客名を基に進行中オーダーの状況・出荷予定・数量・返品を確認 |
| 🔁 **横断（品質→受注）** | 異常製品を起点に、出荷保留の判断材料として進行中オーダー・過去返品を 1 クエリで突合 |

> ✅ **作成済み（自動化）**: ポータルで `lh_quality_analytics` を単一ソースとして追加した Data Agent
> **`da_manufacturing_erp`** に対し、[../12_create_data_agent.ps1](../12_create_data_agent.ps1) が
> AI 指示／データソース指示／few-shot を投入して公開する。
> ポータル生成の `datasource.json`（artifactId / type / 選択テーブル）はそのまま保持し、指示と few-shot のみを上書きする。
> コンテンツは [../data_agent/](../data_agent/) 配下の UTF-8 ファイルで管理する。再実行で定義を上書き更新できる。

> ✅ **なぜ単一ソースにしたか（重要）**
> Telemetry と ERP を **同一 Lakehouse** に置くことで、データエージェントが **1 クエリ内で Telemetry×ERP を JOIN** できる。
> これにより「異常→影響オーダー」の橋渡しを **2 ステップに分けず 1 つの質問**で回答できる（クロスドメイン）。
> NL2SQL（T-SQL）に統一されるため、ソースをまたぐルーティングや「クロスソース禁止」制約も不要。

---

## 1. データソースの追加（ポータル）

| 項目 | 値 |
|---|---|
| データソース種別 | Lakehouse（tables / SQL analytics endpoint） |
| Lakehouse | `lh_quality_analytics` |
| artifactId | **Lakehouse アイテム ID**（SQL エンドポイント ID ではない） |
| スキーマ | `dbo` |
| 公開テーブル | `Telemetry`, `ERP_FulfillmentOrder`, `ERP_FulfillmentOrderDetail`, `ERP_ReturnOrderDetail` |

**手順**
1. データエージェント `da_manufacturing_erp` を開く → **データソースの追加** → Lakehouse → `lh_quality_analytics`。
2. `dbo` の 4 テーブルすべてを選択（⚠ が出ないことを確認）。
3. [../12_create_data_agent.ps1](../12_create_data_agent.ps1) を実行して AI 指示・データソース指示・few-shot を投入・公開。

> ℹ️ Lakehouse データソースの **artifactId は Lakehouse アイテム ID**。SQL エンドポイント ID を指定すると
> ポータルにソースが表示されない（過去にこれが原因で表示されなかった）。

---

## 2. スキーマ（すべて `lh_quality_analytics` / `dbo`）

### 2.1 Telemetry（リアルタイム品質テレメトリ / Eventhouse→OneLake ミラー）

| 列 | 型 | 説明 |
|---|---|---|
| `event_time` | datetime | 計測時刻（UTC） |
| `plant_id` | string | 工場 |
| `line_id` | string | ライン（`LINE-A` / `LINE-B`） |
| `station_id` | string | ステーション（異常は `ST-07-PRESS` 圧入工程） |
| `product_number` | string | 製品コード（例 `CRCA`, `BRFI-SP`, `AIDU`, `AILI`, `AUDR`, `PRBRLI`） |
| `lot_id` | string | ロット |
| `vibration_mm_s` | real | 振動 |
| `temperature_c` | real | 温度 |
| `torque_nm` | real | 圧入トルク（**warn > 48 / fail > 50**、規格上限 50.0 Nm） |
| `dimension_dev_um` | real | 寸法偏差 |
| `status` | string | `ok` / `warn` / `fail` |
| `defect_flag` | int | 0 / 1 |

> ⏱ Telemetry は Eventhouse から OneLake へミラーされる（遅延あり）。T-SQL の時間窓は広め
> （既定 `DATEADD(hour,-6,SYSUTCDATETIME())` ＝直近6時間）を用いる。

### 2.2 ERP_FulfillmentOrder（受注ヘッダ／スナップショット）

| 列 | 説明 |
|---|---|
| `msdyn_fulfillmentorderid` | 受注 ID（PK） |
| `msdyn_name` | 受注番号 |
| `msdyn_customername` | **顧客名**（営業ペルソナの起点） |
| `msdyn_iomstatename` | 状態（`Shipped`/`Cancelled`/`Closed` は完了、それ以外は進行中） |
| `msdyn_plannedshipmentdate` | 出荷予定日 |
| `msdyn_shiptocountry` / `msdyn_shiptocity` | 出荷先国 / 都市 |

### 2.3 ERP_FulfillmentOrderDetail（受注明細／スナップショット）

| 列 | 説明 |
|---|---|
| `msdyn_fulfillmentorderdetailid` | 明細 ID（PK） |
| `msdyn_fulfillmentid` | 親受注への FK → `ERP_FulfillmentOrder.msdyn_fulfillmentorderid` |
| `msdyn_product` | 製品 GUID |
| `msdyn_productname` | 製品名 |
| `msdyn_invoiceqty` | 出荷数量 |
| `msdyn_shipdate` | 出荷日 |

### 2.4 ERP_ReturnOrderDetail（返品明細／スナップショット）

| 列 | 説明 |
|---|---|
| `msdyn_productnumber` | 製品コード（`Telemetry.product_number` と一致する値） |
| `msdyn_productid` | 製品 GUID（製品コード→GUID のブリッジ） |
| `msdyn_productidname` | 製品名 |
| `msdyn_returninginventorylotid` | 返品ロット |
| `msdyn_returnreasonv2` | 返品理由 |
| `msdyn_dispositioncode` | 処置コード |

### 2.5 結合キー（すべて 1 クエリ内で完結）

```
ERP_FulfillmentOrder.msdyn_fulfillmentorderid
   = ERP_FulfillmentOrderDetail.msdyn_fulfillmentid                       // ヘッダ↔明細

-- クロスドメイン（品質→受注）
Telemetry.product_number
   = ERP_ReturnOrderDetail.msdyn_productnumber                            // 製品コード→GUID ブリッジ
ERP_ReturnOrderDetail.msdyn_productid
   = ERP_FulfillmentOrderDetail.msdyn_product                             // GUID で明細へ
ERP_FulfillmentOrderDetail.msdyn_fulfillmentid
   = ERP_FulfillmentOrder.msdyn_fulfillmentorderid                        // 明細→ヘッダ
```

---

## 3. エージェント指示（agent instructions）

エージェント全体の指示は [../data_agent/ai_instructions.txt](../data_agent/ai_instructions.txt) を投入済み。要点:

- **単一ソース・T-SQL のみ**: すべて `lh_quality_analytics`（`dbo`）に対する T-SQL を生成する（KQL は使わない）。
- **クロスドメイン結合 OK**: 品質と受注をまたぐ質問は 1 クエリの JOIN で回答する。
- **しきい値**: torque_nm warn>48 / fail>50。異常 = 時間窓内で `defect_rate>0.2` かつ件数>5。
  完了受注 = `msdyn_iomstatename in ('Shipped','Cancelled','Closed')`。
- **時間窓**: Telemetry はミラー遅延があるため既定で直近6時間。使った時間窓を明記する。

## 4. データソース別の指示

- Lakehouse（`lh_quality_analytics`）: [../data_agent/datasource_instructions.txt](../data_agent/datasource_instructions.txt)

---

## 5. 例題（few-shot）

few-shot は単一ファイル [../data_agent/fewshots.json](../data_agent/fewshots.json)（全 7 件：品質3 / 営業2 / 横断2）。

### 5.1 工場（品質）担当：異常の原因調査

**Q.「今、品質異常は出ている？どの製品・ロット・ステーション？」**
```sql
SELECT TOP 25 product_number AS [product], lot_id AS [lot], station_id AS [station],
       SUM(CASE WHEN status='fail' THEN 1 ELSE 0 END) AS [fails], COUNT(*) AS [total],
       ROUND(MAX(torque_nm),2) AS [max_torque],
       ROUND(CAST(SUM(CASE WHEN status='fail' THEN 1 ELSE 0 END) AS float)/COUNT(*),3) AS [defect_rate]
FROM dbo.Telemetry
WHERE event_time > DATEADD(hour,-6,SYSUTCDATETIME())
GROUP BY product_number, lot_id, station_id
HAVING COUNT(*) > 5 AND CAST(SUM(CASE WHEN status='fail' THEN 1 ELSE 0 END) AS float)/COUNT(*) > 0.2
ORDER BY [defect_rate] DESC
```

### 5.2 営業担当：顧客を基にオーダーを確認

**Q.「Contoso の進行中の受注を一覧で。出荷予定日と状態も。」**
```sql
SELECT TOP 25 fo.msdyn_name AS [order_no], fo.msdyn_customername AS [customer],
       fo.msdyn_iomstatename AS [state], fod.msdyn_productname AS [product],
       fod.msdyn_invoiceqty AS [qty], fo.msdyn_plannedshipmentdate AS [planned_ship],
       fo.msdyn_shiptocountry AS [ship_to_country]
FROM dbo.ERP_FulfillmentOrder AS fo
JOIN dbo.ERP_FulfillmentOrderDetail AS fod
     ON fo.msdyn_fulfillmentorderid = fod.msdyn_fulfillmentid
WHERE fo.msdyn_customername LIKE '%Contoso%'
  AND fo.msdyn_iomstatename NOT IN ('Shipped','Cancelled','Closed')
ORDER BY fo.msdyn_plannedshipmentdate ASC
```

### 5.3 横断（品質→受注）：1 クエリのクロスドメイン結合

**Q.「今 品質異常が出ている製品の進行中オーダー（顧客・出荷予定）を出して。」**
```sql
WITH anomaly_products AS (
  SELECT product_number
  FROM dbo.Telemetry
  WHERE event_time > DATEADD(hour,-6,SYSUTCDATETIME())
  GROUP BY product_number
  HAVING COUNT(*) > 5 AND CAST(SUM(CASE WHEN status='fail' THEN 1 ELSE 0 END) AS float)/COUNT(*) > 0.2
),
product_bridge AS (
  SELECT DISTINCT msdyn_productnumber, msdyn_productid, msdyn_productidname
  FROM dbo.ERP_ReturnOrderDetail
)
SELECT TOP 25 ap.product_number AS [product_code], pb.msdyn_productidname AS [product],
       fo.msdyn_name AS [order_no], fo.msdyn_iomstatename AS [state],
       fo.msdyn_customername AS [customer], fo.msdyn_plannedshipmentdate AS [planned_ship],
       fo.msdyn_shiptocountry AS [ship_to_country]
FROM anomaly_products ap
JOIN product_bridge pb ON ap.product_number = pb.msdyn_productnumber
JOIN dbo.ERP_FulfillmentOrderDetail fod ON pb.msdyn_productid = fod.msdyn_product
JOIN dbo.ERP_FulfillmentOrder fo ON fod.msdyn_fulfillmentid = fo.msdyn_fulfillmentorderid
WHERE fo.msdyn_iomstatename NOT IN ('Shipped','Cancelled','Closed')
ORDER BY fo.msdyn_plannedshipmentdate ASC
```

---

## 6. 運用上の注意

- **実行 ID（権限）**: データエージェントは **質問したユーザーの委任 ID（delegated Entra ID）** でクエリする。
  各利用者に **`lh_quality_analytics` の読み取り権限**が必要。
- **データ鮮度**: Telemetry は Eventhouse→OneLake ミラーのため遅延あり（時間窓は広めに）。
  ERP は Dataverse Link のスナップショット（参照データ）。
- **容量停止の影響**: Fabric 容量を pause すると Eventstream／ミラーが止まり Telemetry が更新されない。
  デモ前に容量を resume し、Telemetry の送信を済ませておく（[../README.md](../README.md) 参照）。
- **0 件の解釈**: 異常クエリが 0 件 = 現時点で異常なし（正常運転）。営業クエリが 0 件 = 該当条件の進行中受注なし。
- **ダッシュボードとの関係**: RTI ダッシュボード（[../queries/analysis.kql](../queries/analysis.kql)）は引き続き
  Eventhouse(KQL) と OneLake ショートカットを使用するため**残す**。データエージェントはこの単一 Lakehouse のみを参照する。
