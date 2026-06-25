# フェーズ2(改): Eventstream に Lakehouse 宛先を追加し、Telemetry を低遅延で
#   lh_quality_analytics に Delta 書き込みする (Eventhouse OneLake ミラーの数十分遅延を回避)。
#   - 既存トポロジ(CustomEndpoint -> DefaultStream -> Eventhouse)はそのまま維持
#   - 同じ DefaultStream を入力に Lakehouse 宛先(Telemetry, 最小行数=1, 最大期間=60s)を追加
#   - lh_quality_analytics の既存 Telemetry ショートカット(Eventhouse ミラー)は名前衝突するので削除
. "$PSScriptRoot\fabric_common.ps1"

$lhInfo      = Get-Content "$PSScriptRoot\lakehouse_info.json" -Raw | ConvertFrom-Json
$lakehouseId = $lhInfo.lakehouseId

$es   = Get-FabricItems -Type 'Eventstream' | Where-Object { $_.displayName -eq 'es_client_telemetry' }
$esId = $es.id
Write-Host "Eventstream: $esId / Lakehouse: $lakehouseId"

# --- 1) 既存定義を取得 ---
$def = Invoke-FabricRest -Method POST -Path "/workspaces/$WorkspaceId/items/$esId/getDefinition"
$esPart   = $def.definition.parts | Where-Object { $_.path -eq 'eventstream.json' }
$platPart = $def.definition.parts | Where-Object { $_.path -eq '.platform' }
$topoJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($esPart.payload))
$topo = $topoJson | ConvertFrom-Json

# --- 2) DefaultStream 名を特定 ---
$defaultStream = $topo.streams | Where-Object { $_.type -eq 'DefaultStream' } | Select-Object -First 1
$streamName = $defaultStream.name
Write-Host "DefaultStream: $streamName"

# --- 3) Lakehouse 宛先がなければ追加 ---
$hasLh = $topo.destinations | Where-Object { $_.type -eq 'Lakehouse' }
if ($hasLh) {
    Write-Host "既に Lakehouse 宛先あり: $($hasLh.name) -> 更新スキップ"
}
else {
    $lhDest = [ordered]@{
        id   = [guid]::NewGuid().ToString()
        name = 'ToLakehouse'
        type = 'Lakehouse'
        properties = [ordered]@{
            workspaceId              = $WorkspaceId
            itemId                   = $lakehouseId
            schema                   = ''
            deltaTable               = 'Telemetry'
            minimumRows              = 1       # 1行から書き込み(低遅延)
            maximumDurationInSeconds = 60      # 最大60秒でフラッシュ
            inputSerialization       = [ordered]@{ type = 'Json'; properties = [ordered]@{ encoding = 'UTF8' } }
        }
        inputNodes = @(@{ name = $streamName })
    }
    # destinations 配列に追加(更新時は既存ノードの id も必須。GET 由来なので保持される)
    $topo.destinations = @($topo.destinations) + $lhDest

    $newTopoJson = $topo | ConvertTo-Json -Depth 40
    $newTopoB64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($newTopoJson))

    $body = [ordered]@{
        definition = [ordered]@{
            parts = @(
                [ordered]@{ path = 'eventstream.json'; payload = $newTopoB64;        payloadType = 'InlineBase64' }
                [ordered]@{ path = '.platform';        payload = $platPart.payload;   payloadType = 'InlineBase64' }
            )
        }
    }
    Write-Host "== Lakehouse 宛先を追加 (updateDefinition) =="
    Invoke-FabricRest -Method POST -Path "/workspaces/$WorkspaceId/items/$esId/updateDefinition" -Body $body | Out-Null
    Write-Host "  OK"
}

# --- 4) 既存 Telemetry ショートカット(Eventhouse ミラー)を削除して名前衝突を回避 ---
Write-Host "== Lakehouse の Telemetry ショートカットを削除 =="
try {
    Invoke-FabricRest -Method DELETE -Path "/workspaces/$WorkspaceId/items/$lakehouseId/shortcuts/Tables/Telemetry" | Out-Null
    Write-Host "  削除 OK (Eventstream が Telemetry を Delta テーブルとして新規作成します)"
}
catch {
    Write-Host "  スキップ/失敗: $($_.Exception.Message)"
}

# --- 5) 確認 ---
Write-Host "== 更新後の宛先一覧 =="
$topo2 = Invoke-FabricRest -Method GET -Path "/workspaces/$WorkspaceId/eventstreams/$esId/topology"
$topo2.destinations | Select-Object name, type | Format-Table -AutoSize

Write-Host ""
Write-Host "完了。次の点に注意:"
Write-Host " - Eventstream を一度 telemetry_sender で流すと lh_quality_analytics に Telemetry(Delta) が作成されます。"
Write-Host "   反映遅延は約1分(最小行数=1/最大60s)。Eventhouse ミラー(数十分)より大幅に高速。"
Write-Host " - --mode eventstream で送信してください(--mode kusto は Eventhouse 直送なので Lakehouse には届きません)。"
Write-Host " - 小さな Delta ファイルが増えるため、必要に応じてノートブックの OPTIMIZE を実行。"
