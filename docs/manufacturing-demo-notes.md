# 製造業デモ — 使えそうな ERP テーブルとシナリオ（調査メモ）

調査日: 2026-06-24
対象テナント: `ABSx68635792.onmicrosoft.com`
Fabric ワークスペース: `ai-seall-hackthon2026`（westus3）
Lakehouse: `dataverse_v4_cds2_workspace_unqb0962e2eca4df111b31f6045bd003`
SQL 分析エンドポイント: `dektha4djnqevaycdxm6baojri-g2w2k4lyqyxe7ejxgbyktidj4y.datawarehouse.fabric.microsoft.com`
DB 名 = Lakehouse 名（同一）

---

## デモ作成の目的

- **対象**: 製造業のお客様。
- **狙い**: Dynamics 365 ERP と Microsoft Fabric を連携させ、**Fabric 上に存在する「ERP だけではないデータ」を組み合わせることで生まれる価値**を提示する。
  - ERP 単体では見えない、外部データ（IoT テレメトリ、生産実績、在庫、需要予測、物流・天候・市況など）と ERP の受注・顧客・フルフィルメント情報を統合し、意思決定に直結する洞察を提供する。
- **特に訴求したいポイント — RTI（Real-Time Intelligence）の組み合わせ**:
  - Fabric の **Real-Time Intelligence（Eventstream / Eventhouse(KQL) / Real-Time Dashboard / Activator）** を活用し、製造設備・出荷・在庫のリアルタイムイベントを取り込む。
  - ERP の受注・フルフィルメントデータ（バッチ的なビジネスコンテキスト）と、RTI のストリーミングデータ（リアルタイムの現場状況）を掛け合わせる。
  - 例: 「設備の異常検知（RTI）」→「該当製品を含む進行中フルフィルメント受注（ERP）への影響を即座に可視化」→「Activator で納期遅延アラートを自動通知」。
- **提供価値の要旨**: 「ERP の業務データ × Fabric の外部・リアルタイムデータ」によって、**事後分析ではなくリアルタイムな状況把握とプロアクティブな対応**を実現できることを示す。

---

## サマリー

- この環境は実質 **Dynamics 365 Intelligent Order Management（IOM／受注フルフィルメント・サプライチェーン）** のデモデータが入っている。
- 従来型セールス系（`account` / `contact` / `opportunity` / `lead` / `salesorder`ヘッダー / `invoice` / `product`マスター / `incident`）は **空 or 未同期**。純粋な営業パイプラインデモは現状不可。
- 受注フルフィルメント・倉庫・返品・配送まわりに実データあり（Contoso, Fabrikam, Northwind 等のデモ企業名を確認済み）。製造業ロジスティクスデモに好適。

---

## 使えるテーブル（データが入っているもの）

### 中核：受注・フルフィルメント（最もデモ向き）

| テーブル | 行数 | 内容 |
|---|---|---|
| `msdyn_fulfillmentorder` | 308 | フルフィルメント受注ヘッダー（顧客名、出荷先住所、計画出荷/納品日、金額、IOM状態） |
| `msdyn_fulfillmentorderdetail` | 551 | 受注明細（品目・数量） |
| `salesorderdetail` | 591 | 受注明細 |
| `msdyn_iomstatedefinition` | 38 | 注文オーケストレーション状態定義 |
| `msdyn_iomstepexecutionresult` | 37 | 注文ステップ実行結果 |

### 在庫・倉庫・拠点（製造ロジスティクス）

| テーブル | 行数 | 内容 |
|---|---|---|
| `msdyn_warehouse` | 33 | 倉庫マスター（住所・緯度経度・WMS設定） |
| `msdyn_region` | 265 | 地域マスター |
| `msdyn_fulfillmentsource` | 35 | 供給元（倉庫・サプライヤー） |
| `msdyn_fulfillmentsource_sourcelist` | 56 | 供給元リスト関連 |
| `msdyn_fulfillmentsourcelist` | 3 | 供給元リスト |
| `is_inventorysystemconfig` | 5 | 在庫システム構成 |
| `is_onhandindexconfig` | 5 | 在庫インデックス構成 |

### 返品・配送（アフターサービス）

| テーブル | 行数 | 内容 |
|---|---|---|
| `msdyn_returnorder` | 10 | 返品注文 |
| `msdyn_returnorderdetail` | 10 | 返品注文明細 |
| `msdyn_fulfillmentreturnorder` | 10 | フルフィルメント返品 |
| `msdyn_fulfillmentreturnorderdetail` | 31 | フルフィルメント返品明細 |
| `msdyn_shippingcarrier` | 2 | 配送業者 |
| `msdyn_carrierservice` | 18 | 配送サービス |

### 製品・単位・価格

| テーブル | 行数 | 内容 |
|---|---|---|
| `productpricelevel` | 110 | 価格表（製品×価格） |
| `uom` | 28 | 単位 |
| `uomschedule` | 5 | 単位グループ |
| `msdyn_customergroup` | 34 | 顧客グループ |

### 組織・リソース

| テーブル | 行数 | 内容 |
|---|---|---|
| `cdm_company` | 41 | 会社（法人）マスター |
| `bookableresource` | 81 | 予約可能リソース（設備・人員） |

---

## 推奨デモシナリオ（ERP × Fabric 連携）

### シナリオA：受注フルフィルメント分析ダッシュボード（最有力）
- `msdyn_fulfillmentorder` × `msdyn_fulfillmentorderdetail` × `msdyn_warehouse` を結合。
- Power BI で「倉庫別出荷量」「地域別納期遵守率」「注文状態（IOM state）別の滞留分析」を可視化。
- 倉庫の緯度経度（`msdyn_primaryaddresslatitude` / `msdyn_primaryaddresslongitude`）でマップ可視化が可能。

### シナリオB：サプライチェーン最適化
- `msdyn_fulfillmentsource` × `msdyn_warehouse` × `msdyn_region` で供給元配置を分析。
- Fabric の外部データ（需要予測・在庫・生産計画）とレイクハウスで結合し、最適供給元をスコアリング。

### シナリオC：返品・品質トレンド
- `msdyn_returnorder` を Fabric 上で IoT/製造実績データと突合し、不良率と返品の相関を分析。

---

## ★採用シナリオ：シナリオC + RTI（リアルタイム品質異常 × ERP返品連携）

具体的なデモ設計案は別ファイルに切り出し: **[scenario-c-rti-demo.md](scenario-c-rti-demo.md)**

- 想定業種：自動車部品メーカー
- 製造ラインの IoT テレメトリ（RTI）× ERP の受注フルフィルメント・返品データを突合
- 結合キー：製品コード（実在値 `CRCA` 等）・ロットID
- アーキテクチャ／テレメトリスキーマ／異常検知 KQL／合成データ生成方針を記載

---

## 注意点・制約

- `account` `contact` `opportunity` `lead` `salesorder`(ヘッダー) `invoice` `product`(製品マスター) `incident` は **空 or 未同期**。
- 顧客は `msdyn_fulfillmentorder.msdyn_customername`（テキスト）に格納されており、`account` テーブルが無くても顧客軸の分析は可能。
- IoT 系（`msdyn_iotdevice` 等）はテーブルは存在するが **0行**。製造設備テレメトリは Fabric 側の外部データで補完する必要あり。
- SQL エンドポイントは初回 `refreshMetadata` API を叩くことでテーブルが可視化された（Dataverse Link to Fabric の同期挙動）。

---

## 接続・調査メモ（再現手順）

- 認証: `az account get-access-token --resource https://database.windows.net/`（Entra ID トークン）→ .NET `SqlClient` の `AccessToken` に設定。
- メタデータ同期: `POST https://api.fabric.microsoft.com/v1/workspaces/{wsId}/sqlEndpoints/{sqlEndpointId}/refreshMetadata?preview=true`
  - wsId: `<workspace-id>`
  - sqlEndpointId: `<sql-endpoint-id>`
- 調査用スクリプト（リポジトリ直下）:
  - `query_account.ps1 -Query "<T-SQL>"` … 任意クエリ実行
  - `scan_tables.ps1` … 全 dbo テーブルの行数スキャン（データ有無の一覧）

---

## 次のステップ候補

1. 選定シナリオの結合クエリ（T-SQL）作成
2. Fabric ノートブック/レイクハウスへの取り込み・整形パターン提示
3. Power BI 向けスタースキーマ設計案の作成
