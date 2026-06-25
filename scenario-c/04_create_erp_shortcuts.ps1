# フェーズ3-1: KQL DB に ERP テーブルへの OneLake ショートカットを作成
# external_table('<name>') で KQL から参照できるようになる。
. "$PSScriptRoot\fabric_common.ps1"

$info = Get-Content "$PSScriptRoot\rti_info.json" -Raw | ConvertFrom-Json
$kqlDbId = $info.databases[0].id

# ERP(Dataverse Link to Fabric) Lakehouse（config.local.json / 環境変数で指定）
$erpLakehouseId = $global:ErpLakehouseId
if (-not $erpLakehouseId) { throw "ErpLakehouseId が未設定です。config.local.json の erpLakehouseId を設定してください。" }

# 作成するショートカット: ショートカット名 => ERP テーブル(dbo)
$shortcuts = [ordered]@{
    'ERP_ReturnOrderDetail'      = 'msdyn_returnorderdetail'
    'ERP_FulfillmentOrder'       = 'msdyn_fulfillmentorder'
    'ERP_FulfillmentOrderDetail' = 'msdyn_fulfillmentorderdetail'
}

foreach ($name in $shortcuts.Keys) {
    $table = $shortcuts[$name]
    Write-Host "== ショートカット作成: $name -> Tables/$table =="
    $body = [ordered]@{
        path   = 'Tables'
        name   = $name
        target = [ordered]@{
            oneLake = [ordered]@{
                workspaceId = $WorkspaceId
                itemId      = $erpLakehouseId
                path        = "Tables/$table"
            }
        }
    }
    try {
        $r = Invoke-FabricRest -Method POST -Path "/workspaces/$WorkspaceId/items/$kqlDbId/shortcuts?shortcutConflictPolicy=CreateOrOverwrite" -Body $body
        Write-Host "  OK: $($r.name)"
    }
    catch {
        Write-Host "  失敗: $($_.Exception.Message)"
    }
}

Write-Host "== KQL DB のショートカット一覧 =="
$list = Invoke-FabricRest -Method GET -Path "/workspaces/$WorkspaceId/items/$kqlDbId/shortcuts"
$list.value | Select-Object name, path | Format-Table -AutoSize

# REST shortcuts API はショートカットを OneLake 上に作るだけで、
# KQL エンジンの external table メタデータは登録されない（ポータル経由だと自動登録される）。
# external_table('<name>') で参照できるよう、delta 形式の external table を明示的に作成する。
. "$PSScriptRoot\kql_common.ps1"
Write-Host "== external table 登録 (delta, スキーマ自動推論) =="
foreach ($name in $shortcuts.Keys) {
    $url = "https://onelake.dfs.fabric.microsoft.com/$WorkspaceId/$kqlDbId/Tables/$name"
    $cmd = ".create external table $name kind=delta (h@'$url;impersonate')"
    try {
        Invoke-Kql -Csl $cmd | Out-Null
        Write-Host "  OK: external_table('$name')"
    }
    catch {
        Write-Host "  失敗: $name : $($_.Exception.Message)"
    }
}
