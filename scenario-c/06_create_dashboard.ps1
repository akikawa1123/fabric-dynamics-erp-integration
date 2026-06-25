# フェーズ4-1: Real-Time Dashboard (KQLDashboard) を定義付きで作成
# センサー時系列→ライン稼働→品質異常→ERP複合分析 の流れで 8 タイル:
#   トルク推移 / 振動推移 / 温度推移 / 寸法偏差推移 (4センサー時系列) /
#   ライン×ステーション稼働 / 品質異常検知(lot) /
#   異常製品×出荷オーダー / 異常製品×返品履歴
. "$PSScriptRoot\fabric_common.ps1"

$info = Get-Content "$PSScriptRoot\rti_info.json" -Raw | ConvertFrom-Json
$db = $info.databases[0]
$clusterUri = $db.queryUri
$dbId = $db.id
$dbName = $db.name

function New-Guid2 { [guid]::NewGuid().ToString() }

$dsId    = New-Guid2
$pageId  = New-Guid2
$paramId = New-Guid2

# --- KQL クエリ（タイル別）---
# 品質異常検知（lot 単位の不良率 > 20%）
# → アラートは設定しないため ERP テーブルと同様に直近5分のみ参照
$qAnomaly = @"
Telemetry
| where event_time > ago(5m)
| summarize fails = countif(status == 'fail'), total = count(),
            avg_torque = round(avg(torque_nm),2), max_torque = round(max(torque_nm),2)
        by product_number, lot_id, station_id
| extend defect_rate = round(todouble(fails) / total, 3)
| where total > 5 and defect_rate > 0.2
| order by defect_rate desc
"@

# === 4センサー 時系列グラフ（30秒ビン・ステーション別系列）===
# 時間軸はダッシュボードの時間範囲パラメーターに連動（アラート設定の前提）
# トルク推移
$qTorque = @"
Telemetry
| where event_time between (_startTime .. _endTime)
| summarize ['トルク平均(Nm)'] = round(avg(torque_nm), 2) by bin(event_time, 30s), station_id
| order by event_time asc
"@

# 振動推移
$qVibration = @"
Telemetry
| where event_time between (_startTime .. _endTime)
| summarize ['振動平均(mm/s)'] = round(avg(vibration_mm_s), 2) by bin(event_time, 30s), station_id
| order by event_time asc
"@

# 温度推移
$qTemperature = @"
Telemetry
| where event_time between (_startTime .. _endTime)
| summarize ['温度平均(℃)'] = round(avg(temperature_c), 2) by bin(event_time, 30s), station_id
| order by event_time asc
"@

# 寸法偏差推移
$qDimension = @"
Telemetry
| where event_time between (_startTime .. _endTime)
| summarize ['寸法偏差平均(µm)'] = round(avg(dimension_dev_um), 2) by bin(event_time, 30s), station_id
| order by event_time asc
"@

# ライン×ステーションの稼働状況（工場全体像）
# → アラートは設定しないため ERP テーブルと同様に直近5分のみ参照
$qLineStation = @"
Telemetry
| where event_time > ago(5m)
| summarize ['件数'] = count(),
            ['不良'] = countif(status == 'fail'),
            ['警告'] = countif(status == 'warn')
        by line_id, station_id
| extend ['不良率(%)'] = round(100.0 * ['不良'] / ['件数'], 1)
| order by line_id asc, station_id asc
"@

$qErpOrders = @"
let anomaly_products =
    Telemetry
    | where event_time > ago(5m)
    | summarize fails = countif(status == 'fail'), total = count() by product_number
    | where total > 5 and todouble(fails) / total > 0.2
    | project product_number;
let product_bridge =
    external_table('ERP_ReturnOrderDetail')
    | summarize by msdyn_productnumber, msdyn_productid, msdyn_productidname;
anomaly_products
| join kind=inner product_bridge on `$left.product_number == `$right.msdyn_productnumber
| join kind=inner (external_table('ERP_FulfillmentOrderDetail')) on `$left.msdyn_productid == `$right.msdyn_product
| join kind=inner (external_table('ERP_FulfillmentOrder')) on `$left.msdyn_fulfillmentid == `$right.msdyn_fulfillmentorderid
| where msdyn_iomstatename !in ('Shipped', 'Cancelled', 'Closed')
| project product_number, product = msdyn_productidname,
          fulfillment_order = msdyn_name, status = msdyn_iomstatename,
          customer = msdyn_customername, planned_ship = msdyn_plannedshipmentdate,
          ship_to_country = msdyn_shiptocountry
| order by planned_ship asc
"@

$qErpReturns = @"
let anomaly_products =
    Telemetry
    | where event_time > ago(5m)
    | summarize fails = countif(status == 'fail'), total = count() by product_number
    | where total > 5 and todouble(fails) / total > 0.2
    | project product_number;
anomaly_products
| join kind=inner (external_table('ERP_ReturnOrderDetail')) on `$left.product_number == `$right.msdyn_productnumber
| summarize return_lines = count() by product_number, product = msdyn_productidname
| order by return_lines desc
"@

# タイル定義（id, title, visualType, query, layout）
# 上段: 4センサーの時系列グラフ（ステーション別系列）
$tileDefs = @(
    @{ title = 'トルク推移 (ステーション別 30秒)';     visualType = 'timechart'; query = $qTorque;
       x = 0;  y = 0;  w = 12; h = 7;
       visualOptions = [ordered]@{ xColumn = 'event_time'; yColumns = @('トルク平均(Nm)'); seriesColumns = @('station_id') } }
    @{ title = '振動推移 (ステーション別 30秒)';       visualType = 'timechart'; query = $qVibration;
       x = 12; y = 0;  w = 12; h = 7;
       visualOptions = [ordered]@{ xColumn = 'event_time'; yColumns = @('振動平均(mm/s)'); seriesColumns = @('station_id') } }
    @{ title = '温度推移 (ステーション別 30秒)';       visualType = 'timechart'; query = $qTemperature;
       x = 0;  y = 7;  w = 12; h = 7;
       visualOptions = [ordered]@{ xColumn = 'event_time'; yColumns = @('温度平均(℃)'); seriesColumns = @('station_id') } }
    @{ title = '寸法偏差推移 (ステーション別 30秒)';   visualType = 'timechart'; query = $qDimension;
       x = 12; y = 7;  w = 12; h = 7;
       visualOptions = [ordered]@{ xColumn = 'event_time'; yColumns = @('寸法偏差平均(µm)'); seriesColumns = @('station_id') } }
    # 下段: 稼働状況・品質異常・ERP複合分析
    @{ title = 'ライン×ステーション 稼働状況';   visualType = 'table';       query = $qLineStation;    x = 0;  y = 14; w = 12; h = 7 }
    @{ title = '品質異常検知 (lot 不良率 > 20%)'; visualType = 'table';       query = $qAnomaly;        x = 12; y = 14; w = 12; h = 7 }
    @{ title = '異常製品 × 進行中出荷オーダー';   visualType = 'table';       query = $qErpOrders;      x = 0;  y = 21; w = 24; h = 7 }
    @{ title = '異常製品 × 返品履歴';             visualType = 'table';       query = $qErpReturns;     x = 0;  y = 28; w = 24; h = 5 }
)

$tiles = @()
$queries = @()
foreach ($t in $tileDefs) {
    $qid = New-Guid2
    $tiles += [ordered]@{
        id            = New-Guid2
        title         = $t.title
        visualType    = $t.visualType
        pageId        = $pageId
        layout        = [ordered]@{ x = $t.x; y = $t.y; width = $t.w; height = $t.h }
        queryRef      = [ordered]@{ kind = 'query'; queryId = $qid }
        visualOptions = if ($t.visualOptions) { $t.visualOptions } else { [ordered]@{} }
    }
    # 時間範囲パラメーターを参照するクエリは usedVariables に登録しないと
    # 「Failed to resolve scalar expression named '_startTime'」になる。
    # 空配列は ConvertTo-Json で null 化されないよう必ず配列として保持する。
    if ($t.query -match '_startTime|_endTime') {
        [string[]]$uv = @('_startTime', '_endTime')
    } else {
        [string[]]$uv = @()
    }
    $queries += [ordered]@{
        dataSource    = [ordered]@{ kind = 'inline'; dataSourceId = $dsId }
        text          = $t.query
        id            = $qid
        usedVariables = $uv
    }
}

$dashboard = [ordered]@{
    '$schema'      = 'https://pbiadx.powerbi.com/static/d/schema/60/dashboard.json'
    id             = New-Guid2
    title          = 'RTI 製造品質モニタリング'
    tiles          = $tiles
    baseQueries    = @()
    parameters     = @(
        [ordered]@{
            kind              = 'duration'
            id                = $paramId
            displayName       = 'Time range'
            description       = ''
            beginVariableName = '_startTime'
            endVariableName   = '_endTime'
            defaultValue      = [ordered]@{ kind = 'dynamic'; count = 1; unit = 'hours' }
            showOnPages       = [ordered]@{ kind = 'all' }
        }
    )
    dataSources    = @(
        [ordered]@{
            kind       = 'kusto-trident'
            scopeId    = 'kusto-trident'
            clusterUri = $clusterUri
            database   = $dbId
            name       = $dbName
            id         = $dsId
            workspace  = $WorkspaceId
        }
    )
    pages          = @( [ordered]@{ name = 'Overview'; id = $pageId } )
    queries        = $queries
    schema_version = '60'
    autoRefresh    = [ordered]@{ enabled = $true; defaultInterval = '30s'; minInterval = '10s' }
}

$dashJson = $dashboard | ConvertTo-Json -Depth 30
$dashB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($dashJson))

# .platform ファイル
$platform = [ordered]@{
    '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json'
    metadata  = [ordered]@{ type = 'KQLDashboard'; displayName = 'RTI 製造品質モニタリング' }
    config    = [ordered]@{ version = '2.0'; logicalId = (New-Guid2) }
}
$platformB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($platform | ConvertTo-Json -Depth 10)))

$body = [ordered]@{
    displayName = 'RTI 製造品質モニタリング'
    type        = 'KQLDashboard'
    definition  = [ordered]@{
        parts = @(
            [ordered]@{ path = 'RealTimeDashboard.json'; payload = $dashB64; payloadType = 'InlineBase64' }
            [ordered]@{ path = '.platform'; payload = $platformB64; payloadType = 'InlineBase64' }
        )
    }
}

# 既存の同名ダッシュボードがあれば updateDefinition で上書き、無ければ新規作成
$existing = Get-FabricItems | Where-Object { $_.displayName -eq 'RTI 製造品質モニタリング' -and $_.type -eq 'KQLDashboard' } | Select-Object -First 1
if ($existing) {
    Write-Host "== Real-Time Dashboard 更新中 (既存: $($existing.id)) =="
    $updateBody = [ordered]@{ definition = $body.definition }
    Invoke-FabricRest -Method POST -Path "/workspaces/$WorkspaceId/items/$($existing.id)/updateDefinition?updateMetadata=true" -Body $updateBody | Out-Null
    $dashId = $existing.id
}
else {
    Write-Host "== Real-Time Dashboard 作成中 =="
    $res = Invoke-FabricRest -Method POST -Path "/workspaces/$WorkspaceId/items" -Body $body
    $res | ConvertTo-Json -Depth 5 | Write-Host
    $dashId = $res.id
    if (-not $dashId) {
        # LRO 経由の場合は一覧から取得
        $items = Get-FabricItems
        $dashId = ($items | Where-Object { $_.displayName -eq 'RTI 製造品質モニタリング' -and $_.type -eq 'KQLDashboard' } | Select-Object -First 1).id
    }
}
Write-Host "Dashboard itemId: $dashId"

# 情報保存
@{ dashboardId = $dashId; name = 'RTI 製造品質モニタリング' } | ConvertTo-Json |
    Set-Content "$PSScriptRoot\dashboard_info.json" -Encoding UTF8
Write-Host "完了。ポータルで Real-Time Dashboard を開いて確認してください。"
