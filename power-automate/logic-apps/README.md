# Logic Apps alternative for Task 009

Power Automate のUI作成が重い場合の代替として、Logic Apps Consumption で
「HTTP受信 → 決定論ルーティング → SharePoint List更新」を行う。

## デプロイ済み（2026-06-26）

- Resource group: `rg-seall-hackthon2026`
- Workflow: `la-mq-incident-ingress`
- API connection: `conn-sharepoint-mq-demo`
- Graph workflow: `la-mq-incident-ingress-graph`
- Graph workflow: `la-mq-factory-decision-handoff-graph`
- Graph GET link workflow: `la-mq-factory-decision-handoff-link-graph`
- Teams connection: `conn-teams-mq-demo`
- Notification channel: Operations Department / Manufacturing Quality Alerts
- SharePoint site: `https://contoso-demo.sharepoint.com/sites/ManufacturingQualityDemo`
- Lists:
  - `MQ_StakeholderRouting`
  - `MQ_QualityIncidents`
  - `MQ_WorkPackages`
- Runtime test: 認証後に HTTP trigger を実行し、`QI-20260626-133728` と
  `WP-F-20260626-133728` の作成を確認済み。
- Graph runtime test: Managed Identity + Microsoft Graph 版を実行し、
  `QI-20260626-140628`, `WP-F-20260626-140628`, `WP-S-20260626-140710`
  の作成/更新を確認済み。`routeUsed` は ingress=`factory_quality_owner`,
  handoff=`sales_owner`。
- Teams notification runtime test: `conn-teams-mq-demo` 認証後、Graph版 ingress / handoff
  の両方で Teams connector (`HttpRequest`) によるチャネル投稿が成功。Ingress通知は `manufacturing-quality-agent-obo` 直リンク（https://m365.cloud.microsoft/chat/agent/T_4d898c7f-59af-f0c7-ee98-7aba353f55b6.db594a1e-ebfb-46e1-bfe7-32286ca1707e）と営業引き継ぎGETリンクを含む。GETリンクから `WP-S-20260626-172041` 作成を確認済み。

## 構成

```text
Fabric Activator or curl
  -> HTTP trigger
  -> MQ_StakeholderRouting から factory_quality_owner を plant/line exact match
  -> fallback は global_fallback
  -> MQ_QualityIncidents に incident 作成
  -> MQ_WorkPackages に factory work package 作成
  -> JSON response（incidentId / resolvedOwnerUpn）
```

通知先:

- Team ID: `16bd70fa-21a9-4e65-8626-848405c9c95e`
- Team: `Operations Department`
- Channel ID: `19:780ec8d25d4f4b16b511f55cb76a1aef@thread.tacv2`
- Channel: `Manufacturing Quality Alerts`

Teams通知は Graph 版に追加済み。SharePoint への deterministic workflow は Managed Identity
+ Microsoft Graph で動作し、Teams 通知は `conn-teams-mq-demo` の Microsoft Teams connector を使う。

## 一度だけ必要な操作

Azure Portal で API connection `conn-sharepoint-mq-demo` を開き、SharePoint 接続を
`admin@example.com` で認証する。

> 2026-06-26時点: Portal上の接続状態表示が `Unauthenticated` のままでも、実行時には
> SharePoint への書き込みが成功するケースを確認済み。最終判断はテストpayloadの実行結果と
> SharePoint List の新規行で確認する。

Portal URL:

```text
https://portal.azure.com/#@/resource/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-seall-hackthon2026/providers/Microsoft.Web/connections/conn-sharepoint-mq-demo
```

Teams通知を使う場合は `conn-teams-mq-demo` も `admin@example.com`
で認証する。

```text
https://portal.azure.com/#@/resource/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-seall-hackthon2026/providers/Microsoft.Web/connections/conn-teams-mq-demo
```

接続状態が `Connected` / `Authenticated` になったら、下記で callback URL を取得してテストする。

## Callback URL取得

```powershell
$sub="00000000-0000-0000-0000-000000000000"
$rg="rg-seall-hackthon2026"
az rest --method post `
  --uri "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/la-mq-incident-ingress/triggers/manual/listCallbackUrl?api-version=2019-05-01" `
  --query value -o tsv
```

Graph版（推奨）:

```powershell
az rest --method post `
  --uri "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/la-mq-incident-ingress-graph/triggers/manual/listCallbackUrl?api-version=2019-05-01" `
  --query value -o tsv

az rest --method post `
  --uri "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/la-mq-factory-decision-handoff-graph/triggers/manual/listCallbackUrl?api-version=2019-05-01" `
  --query value -o tsv
```

## テストpayload

```powershell
$url="<callback-url>"
$body = @{
  activationTime = "2026-06-26T00:53:36Z"
  plantId = "JP-NAGOYA-01"
  lineId = "LINE-A"
  stationId = "ST-07-PRESS"
  productNumber = "CRCA"
  lotId = "LOT-CRCA-20260626-007"
  metricName = "torque_nm"
  observedValue = "51.81"
  thresholdValue = "50"
  unit = "Nm"
  dashboardUrl = ""
} | ConvertTo-Json
Invoke-RestMethod -Method POST -Uri $url -ContentType "application/json" -Body $body
```

handoff payload:

```powershell
$body = @{
  incidentId = "QI-20260626-140628"
  decision = "candidate"
  productNumber = "CRCA"
  lotId = "LOT-CRCA-20260626-007"
  customerName = "Contoso"
} | ConvertTo-Json
Invoke-RestMethod -Method POST -Uri $handoffUrl -ContentType "application/json" -Body $body
```

期待結果:

- HTTP 200
- response body に `workPackageId`, `resolvedOwnerUpn`, `routeUsed=sales_owner`
- `MQ_WorkPackages` に sales package
- `Manufacturing Quality Alerts` にTeams通知

期待結果:

- HTTP 200
- response body に `incidentId`, `resolvedOwnerUpn`, `routeUsed`
- `MQ_QualityIncidents` に新規 incident
- `MQ_WorkPackages` に factory package
- `Manufacturing Quality Alerts` にTeams通知

## 再デプロイ

```powershell
az deployment group create `
  -g rg-seall-hackthon2026 `
  -f power-automate/logic-apps/main.bicep `
  -p @power-automate/logic-apps/la-mq-incident-ingress.parameters.example.json
```

Graph版（推奨）:

```powershell
az deployment group create `
  -g rg-seall-hackthon2026 `
  -f power-automate/logic-apps/graph-main.bicep `
  -p @power-automate/logic-apps/graph.parameters.example.json
```

Graph版はLogic AppのSystem Assigned Managed Identityへ Microsoft Graph
`Sites.ReadWrite.All` application permission を付与する必要がある。今回のデモ環境では
`la-mq-incident-ingress-graph` / `la-mq-factory-decision-handoff-graph` の両方に付与済み。



## Persona routing update (2026-06-27)

- Factory roles (R-001〜R-005): `factory.owner@example.com`
- Sales roles (R-006/R-007): `sales.owner@example.com`
- Global fallback (R-999): `admin@example.com`
- Verified ingress resolves `factory_quality_owner` to factory persona and handoff resolves `sales_owner` to sales persona.

## Persona permissions update (2026-06-29)

- `factory.owner@example.com` / `sales.owner@example.com`
  - Microsoft 365 Copilot / Teams / E5 licenses assigned.
  - Foundry account/project RBAC assigned: `Foundry User`, `Foundry Agent Consumer`, `Foundry Project Runtime User`.
  - Fabric workspace role: `Contributor`.
- Activator `factory_activator` Teams message recipient is `factory.owner@example.com`.
- Activator message now points to the M365 Copilot agent direct link:
  `https://m365.cloud.microsoft/chat/agent/T_4d898c7f-59af-f0c7-ee98-7aba353f55b6.db594a1e-ebfb-46e1-bfe7-32286ca1707e`

## Activator direct orchestration option

Best Power-Automate-free architecture:

```text
Fabric Activator
  -> Fabric User Data Function triggerQualityIncident
  -> Logic App la-mq-incident-ingress-graph
  -> SharePoint + Teams
```

Prepared files:

- `scenario-c/user-data-functions/mq_incident_ingress/function-app.py`
- `scenario-c/user-data-functions/mq_incident_ingress/README.md`

Implemented:

- Fabric `factory_activator` KQL source query now includes `line_id`, `product_number`,
  and `lot_id` in addition to `トルク平均(Nm)` / `station_id`.
- UDF item shell `udf_mq_incident_ingress` was created in the workspace.

Remaining portal step:

- Publish the UDF code and configure Activator `torque_alert` action to **Run User Data Function**,
  mapping the Logic App callback URL and alert context to `triggerQualityIncident`.
  The callback URL is secret-like and must not be committed.


## Notification wording update (2026-06-29)

- Factory alert notification now uses the direct M365 Copilot agent link text: `AIで工場調査を開始`.
- Sales handoff link text is Japanese/business-friendly: `営業へ候補影響として引き継ぐ`.
- Verified after redeploy with `QI-20260629-031813` and `WP-S-20260629-031821`.


## Teams @mention notification update (2026-06-29)

- Factory notification mentions `Factory Owner` using Graph chatMessage `mentions`.
- Sales handoff notification mentions `Sales Owner` using Graph chatMessage `mentions`.
- Verified after redeploy:
  - ingress `Post_teams_notification` = `Succeeded` / `Created`
  - handoff `Post_teams_notification` = `Succeeded` / `Created`
  - sample IDs: `QI-20260629-033941`, `WP-S-20260629-034026`


## Final E2E notification verification (2026-06-29)

- Activator/UDF bridge path verified by sending real Eventhouse anomaly telemetry:
  - New `la-mq-incident-ingress-graph` run appeared and succeeded at `2026-06-29T03:31:45Z`.
  - SharePoint counts increased: incidents 9 -> 10, work packages 17 -> 18.
- Teams @mentions verified after redeploy:
  - Factory notification mentions `Factory Owner` and `Post_teams_notification` returned `Succeeded` / `Created` for `QI-20260629-034334`.
  - Sales handoff notification mentions `Sales Owner` and `Post_teams_notification` returned `Succeeded` / `Created` for `WP-S-20260629-034404`.
