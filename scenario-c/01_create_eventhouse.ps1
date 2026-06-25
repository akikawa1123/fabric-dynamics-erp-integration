# フェーズ1: Eventhouse + KQL DB(自動生成) の作成
. "$PSScriptRoot\fabric_common.ps1"

$ehName = 'eh_manufacturing_rti'

Write-Host "== 既存 Eventhouse を確認 =="
$existing = Get-FabricItems -Type 'Eventhouse' | Where-Object { $_.displayName -eq $ehName }
if ($existing) {
    Write-Host "既に存在: $($existing.id)"
    $eh = $existing
} else {
    Write-Host "== Eventhouse 作成: $ehName =="
    $eh = Invoke-FabricRest -Method POST -Path "/workspaces/$WorkspaceId/eventhouses" -Body @{
        displayName = $ehName
        description = 'Scenario C RTI telemetry eventhouse'
    }
    Write-Host "作成完了: $($eh.id)"
}

# 子 KQL Database 一覧（Eventhouse 作成時に同名DBが自動生成される）
Write-Host "== KQL Database 一覧 =="
$dbs = Invoke-FabricRest -Method GET -Path "/workspaces/$WorkspaceId/kqlDatabases"
$dbs.value | Where-Object { $_.properties.parentEventhouseItemId -eq $eh.id } |
    Select-Object id, displayName, @{n='queryUri';e={$_.properties.queryServiceUri}}, @{n='ingestUri';e={$_.properties.ingestionServiceUri}} |
    Format-List

# 結果を JSON に保存
$out = [ordered]@{
    eventhouseId   = $eh.id
    eventhouseName = $ehName
    databases = @($dbs.value | Where-Object { $_.properties.parentEventhouseItemId -eq $eh.id } | ForEach-Object {
        [ordered]@{
            id        = $_.id
            name      = $_.displayName
            queryUri  = $_.properties.queryServiceUri
            ingestUri = $_.properties.ingestionServiceUri
        }
    })
}
$out | ConvertTo-Json -Depth 10 | Set-Content "$PSScriptRoot\rti_info.json" -Encoding utf8
Write-Host "== rti_info.json に保存しました =="
Get-Content "$PSScriptRoot\rti_info.json"
