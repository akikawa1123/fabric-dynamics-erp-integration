# Fabric User Data Function: MQ incident ingress

This User Data Function is the Power-Automate-free bridge:

```text
Fabric Activator
  -> User Data Function triggerQualityIncident
  -> Logic App la-mq-incident-ingress-graph
  -> SharePoint Incident / WorkPackage
  -> Teams notification
```

## Why this exists

Fabric Activator does not expose a first-class "POST arbitrary HTTP endpoint"
action in the rule editor. The supported Fabric-native way to run custom code
without Power Automate is to run a Fabric item, including **User Data Functions**.

## Files

- `function-app.py` — function code to paste/publish in Fabric User Data Functions.

## Portal setup

1. Fabric workspace: `71a5ad36-8678-4f2e-9137-3070a9a069e6`.
2. Create or open User Data Function item: `udf_mq_incident_ingress`.
3. In Develop mode, replace `function-app.py` with the code from this folder.
4. Publish the function.
5. Test `triggerQualityIncident` manually with:
   - `logicAppUrl`: callback URL for `la-mq-incident-ingress-graph`
   - `plantId`: `JP-NAGOYA-01`
   - `lineId`: `LINE-A`
   - `stationId`: `ST-07-PRESS`
   - `productNumber`: `CRCA`
   - `lotId`: `LOT-CRCA-20260629-007` (or current demo lot)
   - `observedValue`: latest torque value (for example `57.41`)
   - `thresholdValue`: `50`

## Logic App callback URL

The callback URL is secret-like. Retrieve it when configuring Activator and do
not commit it:

```powershell
$sub="00000000-0000-0000-0000-000000000000"
$rg="rg-seall-hackthon2026"
az rest --method post `
  --uri "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/la-mq-incident-ingress-graph/triggers/manual/listCallbackUrl?api-version=2019-05-01" `
  --query value -o tsv
```

## Activator action mapping

In Fabric Activator rule `factory_activator` / `torque_alert`:

1. Action: **Run Fabric item** / **User Data Function**.
2. Function: `udf_mq_incident_ingress.triggerQualityIncident`.
3. Parameters:

| UDF parameter | Recommended value |
|---|---|
| `logicAppUrl` | Logic App callback URL (static, secret-like) |
| `plantId` | `JP-NAGOYA-01` |
| `lineId` | dynamic `line_id` if exposed; otherwise `LINE-A` |
| `stationId` | dynamic `station_id` |
| `productNumber` | dynamic `product_number` if exposed; otherwise `CRCA` |
| `lotId` | dynamic `lot_id` if exposed; otherwise current demo lot |
| `observedValue` | dynamic torque attribute / `トルク平均(Nm)` |
| `thresholdValue` | `50` |
| `metricName` | `torque_nm` |
| `unit` | `Nm` |
| `dashboardUrl` | optional |

## Important

- This function returns failure details if Logic Apps invocation fails; it never
  fabricates a successful result.
- If Fabric capacity is paused, Activator and UDF execution will not run.
- Keep the Logic App HTTP trigger fallback available for demos.



## REST automation attempt

A `UserDataFunction` item shell can be created through Fabric REST, but in this environment `updateDefinition` returned a null response and `getDefinition` still returned null even when using the documented Git representation (`definitions.json`, `function-app.py`, `resources/functions.json`, `.platform`). Therefore, publish the code through Fabric portal or the Fabric VS Code extension.
