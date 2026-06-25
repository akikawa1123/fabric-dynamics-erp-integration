# フェーズ3(改): レイクハウス側で複合分析するための構成を作成
#   - 分析用 Lakehouse `lh_quality_analytics` を作成
#   - Telemetry(Eventhouse の OneLake 化テーブル) と ERP 3テーブルを OneLake ショートカット
#   - SQL エンドポイントで T-SQL 結合できるようにする (queries/lakehouse_analysis.sql)
. "$PSScriptRoot\fabric_common.ps1"

$info    = Get-Content "$PSScriptRoot\rti_info.json" -Raw | ConvertFrom-Json
$kqlDbId = $info.databases[0].id                         # Telemetry の OneLake 提供元(KQL DB)
$erpLakehouseId = $global:ErpLakehouseId                 # ERP(Dataverse Link to Fabric) Lakehouse
if (-not $erpLakehouseId) { throw "ErpLakehouseId が未設定です。config.local.json の erpLakehouseId を設定してください。" }
$lakehouseName  = 'lh_quality_analytics'

# --- 1) 分析用 Lakehouse を作成(既存なら再利用) ---
$items = Get-FabricItems
$lh = $items | Where-Object { $_.displayName -eq $lakehouseName -and $_.type -eq 'Lakehouse' } | Select-Object -First 1
if ($lh) {
    $lakehouseId = $lh.id
    Write-Host "Lakehouse 既存: $lakehouseName ($lakehouseId)"
}
else {
    Write-Host "== Lakehouse 作成: $lakehouseName =="
    $body = [ordered]@{ displayName = $lakehouseName; type = 'Lakehouse' }
    $res = Invoke-FabricRest -Method POST -Path "/workspaces/$WorkspaceId/items" -Body $body
    $lakehouseId = $res.id
    if (-not $lakehouseId) {
        Start-Sleep -Seconds 3
        $items = Get-FabricItems
        $lakehouseId = ($items | Where-Object { $_.displayName -eq $lakehouseName -and $_.type -eq 'Lakehouse' } | Select-Object -First 1).id
    }
    Write-Host "  OK: $lakehouseId"
}

# --- 2) ショートカット定義 (ショートカット名 => @{ itemId; path }) ---
$shortcuts = [ordered]@{
    'Telemetry'                  = @{ itemId = $kqlDbId;        path = 'Tables/Telemetry' }                  # Eventhouse OneLake
    'ERP_ReturnOrderDetail'      = @{ itemId = $erpLakehouseId; path = 'Tables/msdyn_returnorderdetail' }
    'ERP_FulfillmentOrder'       = @{ itemId = $erpLakehouseId; path = 'Tables/msdyn_fulfillmentorder' }
    'ERP_FulfillmentOrderDetail' = @{ itemId = $erpLakehouseId; path = 'Tables/msdyn_fulfillmentorderdetail' }
}

foreach ($name in $shortcuts.Keys) {
    $sc = $shortcuts[$name]
    Write-Host "== ショートカット作成: $name -> $($sc.path) =="
    $body = [ordered]@{
        path   = 'Tables'
        name   = $name
        target = [ordered]@{
            oneLake = [ordered]@{
                workspaceId = $WorkspaceId
                itemId      = $sc.itemId
                path        = $sc.path
            }
        }
    }
    try {
        $r = Invoke-FabricRest -Method POST -Path "/workspaces/$WorkspaceId/items/$lakehouseId/shortcuts?shortcutConflictPolicy=CreateOrOverwrite" -Body $body
        Write-Host "  OK: $($r.name)"
    }
    catch {
        Write-Host "  失敗: $($_.Exception.Message)"
    }
}

Write-Host "== Lakehouse のショートカット一覧 =="
$list = Invoke-FabricRest -Method GET -Path "/workspaces/$WorkspaceId/items/$lakehouseId/shortcuts"
$list.value | Select-Object name, path | Format-Table -AutoSize

# --- 3) SQL エンドポイント接続文字列を取得 ---
$lhDetail = Invoke-FabricRest -Method GET -Path "/workspaces/$WorkspaceId/lakehouses/$lakehouseId"
$sqlConn = $lhDetail.properties.sqlEndpointProperties.connectionString
$sqlEpId = $lhDetail.properties.sqlEndpointProperties.id

@{
    lakehouseId        = $lakehouseId
    lakehouseName      = $lakehouseName
    sqlEndpointId      = $sqlEpId
    sqlConnectionString = $sqlConn
} | ConvertTo-Json | Set-Content "$PSScriptRoot\lakehouse_info.json" -Encoding UTF8

Write-Host ""
Write-Host "完了。"
Write-Host "  Lakehouse        : $lakehouseName ($lakehouseId)"
Write-Host "  SQL エンドポイント : $sqlConn"
Write-Host "  DB(=Lakehouse名)  : $lakehouseName"
Write-Host ""
Write-Host "次: SQL エンドポイントで queries/lakehouse_analysis.sql を実行 (または .\08_run_lakehouse_analysis.ps1)。"
Write-Host "注意: Eventhouse->OneLake のミラーリングには数十分の遅延があります(現在約35分)。"
Write-Host "      Telemetry を即時に見たい場合は Eventhouse/ダッシュボード側(05)を使ってください。"
