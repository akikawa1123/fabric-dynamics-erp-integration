# フェーズ4-2: 既存 Real-Time Dashboard を「(old)」バックアップとして複製
# 元のダッシュボードは一切変更しない。getDefinition で定義を取得し、
# .platform の displayName/logicalId だけ差し替えて新規アイテムとして作成する。
. "$PSScriptRoot\fabric_common.ps1"

$info       = Get-Content "$PSScriptRoot\dashboard_info.json" -Raw | ConvertFrom-Json
$srcId      = $info.dashboardId
$oldName    = "$($info.name) (old)"

Write-Host "== 元ダッシュボード定義を取得 (getDefinition) =="
$def = Invoke-FabricRest -Method POST -Path "/workspaces/$WorkspaceId/items/$srcId/getDefinition"
$parts = $def.definition.parts
if (-not $parts) { throw "定義パーツを取得できませんでした" }

# .platform を書き換え (displayName を (old) に、logicalId を新規採番)
$newParts = @()
foreach ($p in $parts) {
    if ($p.path -eq '.platform') {
        $platJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p.payload))
        $plat = $platJson | ConvertFrom-Json
        $plat.metadata.displayName = $oldName
        $plat.config.logicalId     = [guid]::NewGuid().ToString()
        $platB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($plat | ConvertTo-Json -Depth 10)))
        $newParts += [ordered]@{ path = '.platform'; payload = $platB64; payloadType = 'InlineBase64' }
    }
    else {
        $newParts += [ordered]@{ path = $p.path; payload = $p.payload; payloadType = 'InlineBase64' }
    }
}

$body = [ordered]@{
    displayName = $oldName
    type        = 'KQLDashboard'
    definition  = [ordered]@{ parts = $newParts }
}

Write-Host "== 複製を作成中: $oldName =="
$res = Invoke-FabricRest -Method POST -Path "/workspaces/$WorkspaceId/items" -Body $body
$res | ConvertTo-Json -Depth 5 | Write-Host

$newId = $res.id
if (-not $newId) {
    $items = Get-FabricItems -Type 'KQLDashboard'
    $newId = ($items | Where-Object { $_.displayName -eq $oldName } | Select-Object -First 1).id
}

Write-Host ""
Write-Host "完了。"
Write-Host "  元(現行): $($info.name) / $srcId  ← 変更なし"
Write-Host "  複製(old): $oldName / $newId"
