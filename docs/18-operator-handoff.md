# 運用者ハンドオフ（あなたがやること）

このリポジトリのコア実装（Hosted Agent / factory・sales live / Foundry IQ / 決定論ルーティング）は
**完成・デプロイ・ライブ検証済み**。本書は「人が手で行う必要があるポータル操作」と「今すぐできるデモ」を、
判明済みの値をすべて埋めた形でまとめる。CLI から実行できない操作（Teams/SharePoint/Power Platform/
Cowork/Copilot Studio のポータル、および外部アクションの自動実行）だけが残りである。

更新: 2026-06-26。

## 0. 今すぐデモできる（追加設定ゼロ）

デプロイ済みエージェント `manufacturing-quality-agent`（v4 / active）。

- **Foundry Playground**（推奨・最短）:
  https://ai.azure.com/nextgen/r/cFgijL35TQe0qLtRvLu-Eg,rg-seall-hackthon2026,,ai-seall-hackthon2026-eastus2-001,pj-seall-hackthon/build/agents/manufacturing-quality-agent/build?version=4
  - 工場: 「今、品質異常は出ていますか？製品・ロット・ステーションと、トルクが規格上限(50Nm)を超えた直近イベントを」
  - 営業: 「Contoso の進行中の受注を一覧で。出荷予定日・状態・製品・数量も」
  - 文書: 「圧入工程でトルクが規格上限を超えた場合の初動と過去の8Dを教えて」
- **Responses API エンドポイント**（プログラム呼び出し用）:
  https://ai-seall-hackthon2026-eastus2-001.services.ai.azure.com/api/projects/pj-seall-hackthon/agents/manufacturing-quality-agent/endpoint/protocols/openai/responses?api-version=v1
- **ローカル invoke**: `agent/` で `uv run azd ai agent invoke`（上記 Responses API でも可。詳細は docs/17）。

**デモ前チェック**（これだけ）:
1. Fabric 容量 `seallfabric` が **Active**（Paused なら Azure ポータル/CLI で resume）。
2. 直近データが必要なら再シード（容量 Active 時）:
   ```powershell
   uv run --no-project --with deltalake --with pyarrow --with azure-identity `
     python scenario-c/seed_lakehouse_telemetry_direct.py `
     --workspace-id 71a5ad36-8678-4f2e-9137-3070a9a069e6 `
     --lakehouse-id 2c580bf3-6fde-4416-b082-1dc4cc15a5bb --keep-open
   ```
   （既定は `--mode overwrite` で Telemetry を置換する。Eventstream 再開の前後は Fabric 担当と調整。追記したい場合のみ `--mode append`。）
   `--keep-open` は異常を最新時刻まで継続させ回復帯を抑制し、工場AIが「解消済み」ではなく **open/継続中** を確実に返すようにする（candidate引き継ぎ推奨が安定）。

> 注: 直近で品質異常が出ない場合、シードの異常帯（最新から6〜25分）が古くなっただけ。上記再シードで MAX が現在時刻に更新され復活する。

**デモ前 preflight チェックリスト（本番直前に1分で）**:
1. Fabric 容量 `seallfabric` が Active（連続クエリで429が出るならF8へスケールアウト）。
2. `--keep-open` で Lakehouse 再シード → 最新が異常（解消済み表示の回避）。
3. SharePoint 3リストに想定行あり、最新 incident が open。
4. Teams `Manufacturing Quality Alerts` の @メンション対象が解決する。
5. 営業AIが影響候補を1件以上返す（理想は3件）。
6. 工場AIが「open/継続中」「candidate引き継ぎ推奨」を返す。
7. 公開リポに実テナント識別子が無いこと（example.com/contoso-demo）。

## 1. 任意の拡張（Task 008–011）— あなたのポータル操作が必要

CLI（私）からは実行できない。各手順は判明済みの値で埋めてある。**実 UPN・実メールアドレスは公開リポジトリへ commit しない**こと。

### 008 Teams 直接公開（Foundry ポータル）
CLI 不可（`azd ai agent` に Teams 公開コマンドは無い）。Foundry ポータルから公開する。
1. Foundry ポータル → `pj-seall-hackthon` → Agents → `manufacturing-quality-agent`（v4）→ **Publish**（または Channels）。
2. 公開先に **Microsoft Teams**（必要なら M365 Copilot も）を選択。
3. **Azure Bot Service** を新規/既存でリンク（Teams への接続ブリッジ。`rg-seall-hackthon2026` に作成可）。
4. Teams アプリのメタデータ（名前＝例「製造品質調査エージェント」、アイコン、説明＝`copilot-studio/README.md` の Connected Agent description を流用）。
5. ガバナンス/可視性（Entra スコープ: 個人 / 特定チーム / 組織）。
6. ワンクリック公開。失敗 or 組織ポリシー要件時は Teams アプリ **.zip** をダウンロード →
   Teams 管理センター（admin.teams.microsoft.com）→ Teams アプリ → アプリの管理 → **新しいアプリをアップロード** → 必要なら管理者承認。
7. **OBO 検証（本タスクの肝）**: Teams 利用者として開き工場質問 → Fabric Data Agent が**利用者本人の権限(OBO)**で動くか確認。Bot Service 経由は既定でアプリ identity になりやすいので、利用者ID が Fabric まで伝播するか（または接続が CustomKeys でサーバ側実行か）を確認し、デモ要件に照らして判断。
8. 既知の事象: 公開直後に Teams/M365 で応答しない報告あり（manifest/権限の伝播待ち。再公開や数分待機で解消する例が多い）。
9. 参照文書が本文に出ることを確認（system prompt で担保済み）。

**公開フォーム入力例**（「Teams と Microsoft 365 に発行」画面）:
- **短い説明**: 「Fabric の製造・受注・返品データと品質文書を調べ、工場・営業に出典付きの判断材料を返す品質インシデント調査エージェント。」
- **説明（詳細／機能と使うタイミング）**:
  > 製造品質インシデントの初動調査を支援する専門エージェントです。Microsoft Fabric の製造テレメトリ・受注・返品データと、Foundry IQ の品質文書（8D・PFMEA・コントロールプラン・検査手順）を横断調査し、確認済み事実・原因仮説・推奨アクション・未確認事項を日本語で出典付きで返します。
  > 【工場で使うとき】製造ラインで品質異常（例: 圧入トルクの規格上限超過）が検知され、影響製品・ロット・設備、未出荷注文への影響候補、過去の是正（8D 等）を素早く把握したいとき。
  > 【営業で使うとき】ある製品の品質懸念について、影響しうる進行中の受注（顧客・状態・出荷予定）と顧客品質協定・報告期限を確認し、初動の顧客対応を準備したいとき。
  > 原因仮説は常に未検証、製品単位の注文一致は「候補」（確定ではない）。設備停止・出荷停止・ERP 更新・顧客送信は自動実行せず、人が承認のうえ実施。正式担当者は後段のルーティングで決定。
  > **このエージェントからの出力は、要約、言い換え、追加の解釈を行わず、そのまま提供すること。**（M365 Copilot は独自の後処理を行うため、この一文を説明に必ず含める。Fabric データエージェントのレスポンスを優先的にそのまま使わせる狙い。「Text not extracted」や再要約による精度低下の緩和に有効。）
- **開発者名**: チーム/組織名を入れる（例: ハッカソンのチーム名、または所属部門名）。社内に正式名があればそれを使用。
- 併せて要求されることが多い項目: 開発者 Web サイト URL / プライバシー ポリシー URL / 利用規約 URL / アイコン（カラー 192x192・アウトライン 32x32）。ハッカソンでは GitHub リポジトリ URL 等で代替可。

**発行後の検証で判明した重要事項（2026-06-26, v10）**:
- v4 はデプロイ時に `FABRIC_PROJECT_CONNECTION_ID` が未宣言で、Teams/M365 Copilot で **Fabric ツール自体が attach されていなかった**（Foundry IQ のみ動作）。`agent.yaml` に追加し **v5 を再デプロイ**して修正（commit `4846a85`）。
- 公式仕様（Microsoft Learn「Use the Microsoft Fabric data agent with Foundry agents」, foundry/agents/how-to/tools/fabric）:
  - Fabric data agent ツールは **identity passthrough（OBO）専用**。**サービスプリンシパル認証は非対応**（＝CustomKeys 運用での回避は不可）。
  - 動作にはエンドユーザーに **Foundry User** RBAC、Fabric data agent への **READ**、データソース権限（Lakehouse=Read 等）が必要。
  - 接続は Management center → Connected resources で **「Microsoft Fabric」型**として workspace_id / artifact_id で作成する。
- Teams/M365 Copilot 向けの本番入口は **Prompt Agent `manufacturing-quality-agent-obo`**。デプロイ済み Hosted Agent は Responses Protocol / ローカル fixture 用に残す。
  - 理由: Hosted Agent はコンテナの managed identity（unattended）で動くため Fabric の OBO が伝播しない。**Prompt Agent（サーバサイド定義）は Agent Service が OBO 交換を処理**するため、Teams/M365 Copilot でもエンドユーザー identity で Fabric を照会できる。
  - 作成/更新: `cd agent; uv run --extra foundry python scripts/provision_prompt_agent.py --with-kb`（agent 名 `manufacturing-quality-agent-obo`）。
  - Teams 公開: 008 と同手順で、公開対象を `manufacturing-quality-agent-obo` にする。既存公開アプリが古いバージョンに pin されている場合は、**再発行 → M365 admin center 承認 → 新規チャット**が必要。
- **Foundry IQ（品質文書）**:
  - 現状の Prompt Agent SDK では `PromptAgentDefinition` に native Azure AI Search の `tool_resources` を直接付与できないため、Foundry IQ KB は **MCP 接続（`mq-quality-kb-mcp`）**として使う。
  - prompt agent の identity（`instance_identity` と `blueprint` の principal_id）に Search サービス `srch-seall-hackthon2026-eastus-001` の **Search Index Data Reader** が必要。本環境では付与済み。別名で作り直す場合は、その新 identity へ同ロールを付与する（未付与だと KB ツール列挙が 403 になり、エージェント全体が失敗する）。
  - 付与コマンド例: `az role assignment create --assignee-object-id <principalId> --assignee-principal-type ServicePrincipal --role "Search Index Data Reader" --scope <search service resource id>`
- **Teams/M365 Copilot 実機テスト結果（2026-06-26, v10 再発行後）**:
  - Test1 工場（Fabric/OBO）: 成功。CRCA / `LOT-CRCA-20260626-007` / `ST-07-PRESS` / トルク超過を Fabric 出典付きで返却。
  - Test2 営業（Fabric/OBO）: 成功。v10 の固定テンプレート（`customer name contains 'Contoso' (partial match, not exact)`）により、`Contoso Coffee` / `Contoso, Ltd.` / `Contoso Pharmaceuticals` / `Contoso Suites` の進行中受注（FO-ORD）を Fabric 出典付きで返却。
  - Test3 品質文書（Foundry IQ/MCP + Fabric）: 成功。`8D-2025-014` / `CP-ST07-PRESS` / `PFMEA-PRESS-001` / `INSP-TORQUE-CAL-001` を出典付きで返却し、Fabric の CRCA 異常・candidate 注文フレーミングも保持。
  - 注: 再発行・admin 承認後は新規チャットで再テストする。Test3 が一度「問題が発生しました。後で応答します」となった場合も、公開バージョンの pin / 反映待ちの可能性がある。
- **工場/営業ペルソナ権限（2026-06-29）**:
  - `factory.owner@example.com` / `sales.owner@example.com` は account enabled、`Microsoft_365_Copilot` / Teams / E5 ライセンス割当済み。
  - 両ユーザーへ Foundry account/project の `Foundry User` / `Foundry Agent Consumer` / `Foundry Project Runtime User` を付与済み。
  - Fabric workspace `71a5ad36-8678-4f2e-9137-3070a9a069e6` で両ユーザーを `Contributor` に設定済み（Fabric Data Agent / Lakehouse OBO 前提）。

### 009 StakeholderRouting List + Power Automate

**(A) SharePoint リスト**
- `StakeholderRouting`: `routing/stakeholder-routing.sample.csv` をインポート。`@example.com` を実デモ利用者の UPN に置換してから取り込む（実値は commit しない）。列:
  | 列 | 型 | 例 |
  |---|---|---|
  | routing_id | 単一行テキスト | R-001 |
  | role_code | 単一行テキスト | factory_quality_owner |
  | scope_type | 単一行テキスト | plant_line / plant / customer_product / customer / global |
  | plant_id / line_id / customer_name / product_number | 単一行テキスト | JP-NAGOYA-01 / LINE-A / Contoso / CRCA |
  | user_upn | 単一行テキスト | quality.owner@… |
  | is_primary / active | 単一行テキスト（値: `true` / `false`） | true |
  | priority | 数値 | 10 / 20 / 999 |

  ※ `is_primary` / `active` を Yes/No 列にしたい場合は、まず単一行テキストで取り込み、インポート後に変換する。
- 併せて `QualityIncidents`（incident 保存）と `WorkPackages`（factory/sales、解決済み UPN 保存）も作成。

**(B) PA-01 — incident ingress**（spec: `power-automate/flow-specs/PA-01-quality-incident-ingress.md`）
1. Power Automate → 自動化したクラウドフロー。トリガは **「HTTP 要求の受信時」**（POST URL を取得）。`scenario-c/11_create_activator.ps1` の Fabric Activator のアクションでこの URL を呼ぶ（Activator に Power Automate アクションがあればそれで本フローを起動）。body は PA-01 の Inputs（plantId / lineId / stationId / productNumber / lotId / metricName / observedValue / thresholdValue / unit / dashboardUrl）。
2. 手順: **JSON の解析** → `QI-yyyyMMdd-###` 生成 → SharePoint **項目の作成**（QualityIncidents）→ **担当者解決（決定論・AIなし）**: SharePoint **複数の項目の取得**（StakeholderRouting, `active eq 1` かつ scope/plant/line 一致）を specificity（plant_line > plant > global）と priority で先頭採用、無ければ `R-999`（global_fallback）→ **Teams: アダプティブ カードを投稿**（`adaptive-cards/factory-alert.json`）を factory_quality_owner へ。判断は factory-decision カードを「投稿して応答を待機」。解決不可は global_fallback へ。

**(C) PA-02 — factory decision → sales handoff**（spec: `power-automate/flow-specs/PA-02-factory-decision-sales-handoff.md`）
1. トリガ: 工場判断の応答（PA-01 末尾の「応答を待機」結果、または別トリガ）。
2. 手順: decision / responder / timestamp を QualityIncidents へ更新 → decision が candidate/confirmed なら affected order の customer/product を取得（**製品単位一致は候補扱い厳守・確定ロット影響を主張しない**）→ **sales_owner を解決**（specificity: customer_product > customer）→ **Teams: sales-alert カード**（`adaptive-cards/sales-alert.json`）を sales_owner へ → SharePoint に **factory / sales Work Package** 作成（**解決済み UPN を保存**）→ fallback 使用時は警告を記録。

> 決定論ルーティング（参考・私の側で検証済み）: factory→R-001 / sales→R-006。**担当者は必ず StakeholderRouting のルックアップで決め、AI に推測させない**（AGENTS.md #8）。候補/確定の区別と「承認前に出荷停止・メール送信しない」を守る。
> Power Automate を使わない最小デモも可（`power-automate/README.md`）: Activator から Teams 直接通知 + 利用者が Agent を開く（工場→営業は手動）。

**009 実環境作成状況（2026-06-26）**:
- SharePoint site 作成済み: `https://contoso-demo.sharepoint.com/sites/ManufacturingQualityDemo`
- Graph device code で `admin@example.com` に `Sites.Manage.All` / `Sites.ReadWrite.All` delegated consent を取得し、以下を作成・初期データ投入済み:
  - `MQ_StakeholderRouting`: `https://contoso-demo.sharepoint.com/sites/ManufacturingQualityDemo/Lists/MQ_StakeholderRouting`（8件: R-001〜R-007/R-999）
  - `MQ_QualityIncidents`: `https://contoso-demo.sharepoint.com/sites/ManufacturingQualityDemo/Lists/MQ_QualityIncidents`（1件: QI-20260626-001）
  - `MQ_WorkPackages`: `https://contoso-demo.sharepoint.com/sites/ManufacturingQualityDemo/Lists/MQ_WorkPackages`（2件: WP-F/WP-S）
- 以後、Power Automate からはこの3リストを使う。`user_upn` / owner はデモ用ペルソナに更新済み（factory=`factory.owner@example.com`, sales=`sales.owner@example.com`, fallback=`admin@example.com`）。

**009 を追加でPower Automate化する場合の最短手順（ポータル操作）**:
- Power Platform 環境: `V4`。ユーザー: `admin@example.com`。
- 推奨サイト: 新規 SharePoint Team site `Manufacturing Quality Demo`（URL例: `https://contoso-demo.sharepoint.com/sites/ManufacturingQualityDemo`）。既存 `Operations Department` site でも可。
- 作成する List:
  1. `MQ_StakeholderRouting`: `routing_id`, `role_code`, `scope_type`, `plant_id`, `line_id`, `customer_name`, `product_number`, `user_upn`, `is_primary`(Yes/No), `priority`(Number), `active`(Yes/No), `resolution_note`。
  2. `MQ_QualityIncidents`: `incident_id`, `activation_time`, `plant_id`, `line_id`, `station_id`, `product_number`, `lot_id`, `metric_name`, `observed_value`, `threshold_value`, `unit`, `status`, `dashboard_url`, `factory_decision`, `factory_responder_upn`, `decision_time`。
  3. `MQ_WorkPackages`: `work_package_id`, `incident_id`, `work_package_type`, `created_time`, `status`, `product_number`, `lot_id`, `customer_name`, `impact_level`, `candidate_or_confirmed`, `required_participants_upn`, `resolved_owner_upn`, `summary`, `open_questions`。
- ルーティング初期データ: `R-001`〜`R-007`, `R-999` を作成し、`user_upn` は全て `admin@example.com` にする（デモ用）。`R-006` は `role_code=sales_owner`, `scope_type=customer_product`, `customer_name=Contoso`, `product_number=CRCA`, `priority=10`, `active=Yes`。
- デモ用 incident: `QI-20260626-001`（JP-NAGOYA-01 / LINE-A / ST-07-PRESS / CRCA / LOT-CRCA-20260626-007 / torque_nm 51.81 > 50 / status=open / factory_decision=candidate）。
- デモ用 Work Package:
  - `WP-F-20260626-001`（factory, CRCA, LOT-CRCA-20260626-007, candidate, owner=admin）。
  - `WP-S-20260626-001`（sales, customer=Contoso, CRCA, candidate, owner=admin）。
- PA-01（最小）: Manual trigger → `MQ_StakeholderRouting` から `factory_quality_owner` を plant/line exact match で取得（0件なら `global_fallback`）→ `MQ_QualityIncidents` 作成 → `factory-alert.json` を Teams で admin に投稿。
- PA-02（最小）: Manual trigger（incidentId/decision/productNumber/lotId/customerName）→ `sales_owner` を `customer_name=Contoso and product_number=CRCA` で取得（0件なら fallback）→ incident 更新 → `MQ_WorkPackages` sales 作成 → `sales-alert.json` を Teams で admin に投稿。
- 私のCLIで試した範囲: `admin@example.com` で Graph/SharePoint 読み取りは可能。初期トークンでは List 作成が `accessDenied` だったが、Graph device code で `Sites.Manage.All` / `Sites.ReadWrite.All` delegated consent を取得し、3リストの作成・初期データ投入まで完了。一時 Graph app-only 権限の試行は削除済み。

**Logic Apps 代替（Power Automate UIが重い場合）**:
- `power-automate/logic-apps/main.bicep`（SharePoint connector版）と `power-automate/logic-apps/graph-main.bicep`（Managed Identity + Microsoft Graph版）を追加し、Azure Logic Apps Consumption の最小版をデプロイ済み。
- Azure resources:
  - Connector workflow: `la-mq-incident-ingress`
  - Connector API connection: `conn-sharepoint-mq-demo`
  - Graph workflow（推奨）: `la-mq-incident-ingress-graph`
  - Graph workflow（推奨）: `la-mq-factory-decision-handoff-graph`
  - Graph GET link workflow（Teams通知リンク用）: `la-mq-factory-decision-handoff-link-graph`
  - Teams API connection: `conn-teams-mq-demo`
  - Resource group: `rg-seall-hackthon2026`
- 処理: HTTP trigger → `MQ_StakeholderRouting` で owner を deterministic に解決 → `MQ_QualityIncidents` / `MQ_WorkPackages` を作成/更新 → JSON応答。
- Teams通知: Graph版に追加済み。Microsoft Teams connector (`conn-teams-mq-demo`) の `HttpRequest` で `Operations Department / Manufacturing Quality Alerts` に投稿する。
- 実行テスト済み:
  - connector版 ingress: `QI-20260626-133728` と `WP-F-20260626-133728` を作成。
  - Graph版 ingress: `QI-20260626-140628` と `WP-F-20260626-140628` を作成、`routeUsed=factory_quality_owner`。現在の `resolvedOwnerUpn` は `factory.owner@example.com`。
  - Graph版 handoff: `WP-S-20260626-140710` を作成し、incident `QI-20260626-140628` の `factory_decision=candidate` を更新、`routeUsed=sales_owner`。現在の `resolvedOwnerUpn` は `sales.owner@example.com`。
  - Teams通知: `conn-teams-mq-demo` 認証後、ingress / handoff の両方でチャネル投稿成功。Ingress通知は `manufacturing-quality-agent-obo` 直リンクと営業引き継ぎGETリンクを含む。GETリンクから `WP-S-20260626-172041` 作成を確認済み。
- Graph版は connector認証不要。Logic App の System Assigned Managed Identity に Microsoft Graph `Sites.ReadWrite.All` application permission を付与済み。

- 2026-06-29: Teams通知の次アクション文言を改善。工場通知は「AIで工場調査を開始」直リンク、営業引き継ぎは「顧客影響の可能性がある場合は営業へ候補影響として引き継ぐ」に変更。再デプロイ後、`QI-20260629-031813` / `WP-S-20260629-031821` で ingress + handoff link の成功を確認。


**Activator設定（2026-06-29）**:
- Fabric item: `factory_activator`（Reflex, itemId `b08718ac-433c-4ebd-9aa2-fc9be34d6570`）。
- 監視: Eventhouse `eh_manufacturing_rti` / `Telemetry` を60秒間隔でKQL集計し、`station_id` ごとの `トルク平均(Nm)` を監視。UDF/Logic Apps連携で文脈を渡せるよう、KQL source queryには `line_id`, `product_number`, `lot_id` も含めるよう更新済み。
- Rule: `torque_alert`, condition `トルク平均(Nm) >= 50`, `shouldRun=true`。
- Action: Teams message to `factory.owner@example.com`。
- 通知本文は `manufacturing-quality-agent-obo` のM365 Copilot直リンクへ更新済み（リンクはデプロイ時に自分の公開エージェントのものを設定。bicep param `agentChatUrl`）:
  `https://m365.cloud.microsoft/chat/agent/<your-agent-link>`
- ベスト構成（Power Automateなし）: **Activator → User Data Function → Logic Apps**。
  - UDFコードは `scenario-c/user-data-functions/mq_incident_ingress/function-app.py` に用意済み。
  - UDF `triggerQualityIncident` はActivatorから受け取った文脈を `la-mq-incident-ingress-graph` のcallback URLへPOSTする。
  - Logic Apps callback URLはsecret相当のため、ソースにはコミットしない。ActivatorのUDF action parameterとして静的値で渡す。
  - Fabric RESTでは `UserDataFunction` item shell `udf_mq_incident_ingress` を作成済み。ただしUDFコードのpublish/Activator action割当はFabric portal/VS Code extension前提のため、ポータルで最終設定する。
- 注意: 現時点で完全検証済みなのは、Logic Apps HTTP triggerを直接呼ぶ業務フロー。Activator→UDF→Logic Apps はベスト実装案としてコードと設定手順を準備済み。

### 010 Cowork（SharePoint Work Package 起点）
- スキル既存（承認ゲート・自動実行なしを内蔵）:
  - `cowork/skills/factory-quality-response/SKILL.md`（封じ込め会議 + Word/Excel 資料、承認後に Teams 会議作成）。
  - `cowork/skills/sales-customer-impact-response/SKILL.md`（顧客影響会議 + PowerPoint + 初報メール案、承認前に送信・作成しない）。
- 実行は Cowork（M365）上で、SharePoint `ManufacturingQuality/WorkPackages` の未処理 Work Package に対して行う。

### 011 Copilot Studio（任意スパイク）
1. 先に「Teams 利用者の文脈で Fabric Data Agent が成功する」ことを 008 で確認。
2. 成功時のみ、Copilot Studio で Foundry エージェントを **Connected Agent** として追加（説明文は `copilot-studio/README.md` に用意済み）。
3. 失敗時は Teams 直接公開（008）を維持し、コアコードを分岐させない。

## 2. 私（CLI）が代行できない理由
- Teams 公開 / SharePoint List・Work Package / Power Automate クラウドフロー / Cowork の会議・資料・メール / Copilot Studio は、いずれも**対話的なポータル/M365 操作**で、この CLI 環境からは到達できない。
- かつ AGENTS.md の絶対条件として、Hosted Agent からの設備停止・出荷停止・ERP 更新・メール送信等の**外部実行は禁止**。Teams 通知は Activator / Power Automate の設定済みフローとして、必要な承認・運用責任のもとで行う（Hosted Agent が直接送信するのではない）。

## 3. デモ運用メモ
- 容量 `seallfabric` を Active に保つ（データは OneLake に永続。照会のみ Active 必要）。
- コストと teardown は docs/17 を参照（AI Search Basic ≈ $74/mo、F2 Active 時）。

## 4. 実務リアリティ重視のデモ台本

このデモは「異常検知から、担当者通知、AI調査、人間判断、営業引き継ぎ」までを
Microsoftテクノロジーでつなぐストーリーとして見せる。

### Step 1: 異常発生 / Activator相当

デモでは Fabric Activator 相当として `la-mq-incident-ingress-graph` の HTTP trigger を実行する。

入力例:
- plant/line/station: `JP-NAGOYA-01` / `LINE-A` / `ST-07-PRESS`
- product/lot: `CRCA` / `LOT-CRCA-20260626-007`
- metric: `torque_nm = 51.81 > 50`

見せるもの:
- Logic App run が Succeeded
- `MQ_QualityIncidents` に新規 incident
- `MQ_WorkPackages` に factory work package
- Teams `Operations Department / Manufacturing Quality Alerts` に工場通知

### Step 2: 工場担当者が通知からAI調査へ

Teams通知には `manufacturing-quality-agent-obo` の直リンクを入れる。

担当者（工場ペルソナ）: `factory.owner@example.com`

M365 Copilotで聞く（まず軽い異常確認＋candidate推奨）:

```text
トルクが規格上限(50Nm)を超えた直近イベントを、製品・ロット・ステーション・ライン・トルク・時刻・状態つきで教えて。営業へcandidate引き継ぎが必要かも一言で。
```

続けて品質文書（任意の2問目。1ターンに詰め込むとタイムアウトしやすいので分ける）:

```text
圧入工程でトルクが規格上限を超えた場合の初動対応と、過去の8D事例を品質文書から教えて。8Dなど専門用語は初見でも分かるよう一言で説明して。文書IDと出典も。
```

見せるもの:
- 冒頭1行サマリ（CRCA/LOT/ST-07-PRESS、50Nm超過、candidate引き継ぎ推奨）
- Fabric OBOでCRCA/LOT/ST-07-PRESSの事実、2問目でFoundry IQの8D/PFMEA/Control Plan/校正手順（8D等は平易な注釈つき）
- 原因仮説は未検証、設備停止/出荷停止は自動実行しない（推奨は人のレビュー用）

### Step 3: 工場担当者が営業へcandidate引き継ぎ

Teams通知内の「営業へcandidateとして引き継ぐ」リンクから
`la-mq-factory-decision-handoff-link-graph` を起動する。

裏側では `la-mq-factory-decision-handoff-graph` が実行される。

見せるもの:
- incident の `factory_decision=candidate`
- `MQ_WorkPackages` に sales work package
- sales owner: `sales.owner@example.com`
- Teamsに営業引き継ぎ通知

### Step 4: 営業担当者がAI調査

担当者（営業ペルソナ）: `sales.owner@example.com`

M365 Copilotで聞く（異常連動で影響候補を絞る）:

```text
今回の品質異常は CRCA / LOT-CRCA-20260629-007 です。Contoso 関連の進行中受注のうち影響候補になり得るものを一覧で。出荷予定日・状態・製品・数量も。ロット引当が未確認なら confirmed ではなく candidate として扱って。
```

見せるもの:
- 冒頭1行サマリ（Contoso候補N件、candidate）
- `Contoso Coffee` / `Contoso, Ltd.` / `Contoso Pharmaceuticals` などを部分一致で取得
- `FO-ORD...` の進行中受注
- 製品一致は candidate。ロット引当が確認できるまで confirmed にしない

### Step 5: Coworkへつなぐ（任意）

`MQ_WorkPackages` の factory / sales work package を起点に、Coworkで次を準備できる。

- 工場: 封じ込め会議、再検査チェックリスト、工場資料
- 営業: 顧客影響会議、説明資料、初報メール案

会議作成・メール送信は承認後に行う。

**Coworkでの入力例**（スキルは Cowork 側に導入済み。WorkPackage ID を指定して起動する）:

工場（`factory-quality-response`、対象は例: `WP-F-...`）:

```text
SharePointのMQ_WorkPackagesにある私担当の未処理factory Work Package（WP-F-YYYYMMDD-XXXXXX）を起点に、暫定封じ込め対応を準備して。確認済み事実・影響候補・必須参加者UPNを読み、必須参加者は変えずに全員が空いている最短30分枠を提案。暫定封じ込め計画書(Word)と再検査チェックリスト(Excel)のドラフトも作って。会議作成は私が承認するまでしないで。設備停止や出荷停止はしないで。
```

営業（`sales-customer-impact-response`、対象は例: `WP-S-...`）:

```text
MQ_WorkPackagesの私担当の未処理sales Work Package（WP-S-YYYYMMDD-XXXXXX）を起点に、顧客影響対応を準備して。confirmedとcandidateを分けて読み、必須参加者UPNは変えずに空き時間を確認、顧客影響確認会議を提案。顧客説明のPowerPointと初報メール案も作って。原因は未確定、影響はcandidateと明記。私の承認前に会議作成やメール送信はしないで。
```

入力のコツ:

- WorkPackage ID を必ず指定（曖昧だと別案件を拾う）。
- 「承認するまで会議作成・メール送信しない」を毎回明記（スキルにも内蔵だが念押し）。
- candidate / 未検証を維持（営業は confirmed にしない）。
- 参加者は `required_participants_upn` をそのまま使い、増減させない。

### デモの一言

> Fabric Activator相当のイベントをLogic Appsが受け取り、StakeholderRoutingで担当者を決定し、
> Teamsへ通知します。通知を受けた担当者はM365 Copilot上のFoundry AgentでFabricと
> Foundry IQを横断調査し、人間の判断後にLogic Appsが営業へWork Packageを引き継ぎます。
> AIは調査と整理、担当者決定と業務引き継ぎは決定論的ワークフローが担当します。





**メンション通知検証（2026-06-29）**:
- Teams通知本文に Graph `mentions` を追加済み。
  - 工場通知: `<at id="0">Factory Owner</at>` / user id `00000000-0000-0000-0000-000000000001`
  - 営業通知: `<at id="0">Sales Owner</at>` / user id `00000000-0000-0000-0000-000000000002`
- 再デプロイ後、ingress と handoff の `Post_teams_notification` がどちらも `Succeeded` / `Created` を返すことを確認済み。
- 検証例: `QI-20260629-033941`, `WP-S-20260629-034026`。

**実務リアリティを上げるためのペルソナ設定（2026-06-27）**:
- `MQ_StakeholderRouting` を実務ペルソナへ更新済み。
  - factory系（R-001〜R-005）: `factory.owner@example.com`
  - sales系（R-006/R-007）: `sales.owner@example.com`
  - fallback（R-999）: `admin@example.com`
- Logic App再実行で、ingress は `factory_quality_owner` → `factory.owner@example.com`、handoff は `sales_owner` → `sales.owner@example.com` を返すことを検証済み。


## Final E2E notification verification (2026-06-29)

- Activator/UDF bridge path verified by sending real Eventhouse anomaly telemetry:
  - New `la-mq-incident-ingress-graph` run appeared and succeeded at `2026-06-29T03:31:45Z`.
  - SharePoint counts increased: incidents 9 -> 10, work packages 17 -> 18.
- Teams @mentions verified after redeploy:
  - Factory notification mentions `Factory Owner` and `Post_teams_notification` returned `Succeeded` / `Created` for `QI-20260629-034334`.
  - Sales handoff notification mentions `Sales Owner` and `Post_teams_notification` returned `Succeeded` / `Created` for `WP-S-20260629-034404`.
