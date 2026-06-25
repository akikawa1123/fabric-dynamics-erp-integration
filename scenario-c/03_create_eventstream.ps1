# フェーズ2: Eventstream 作成（CustomEndpoint ソース → Eventhouse 宛先）
# 作成後、CustomEndpoint の Event Hub 互換 接続文字列を取得して保存する。
. "$PSScriptRoot\fabric_common.ps1"

$esName = 'es_client_telemetry'
$info = Get-Content "$PSScriptRoot\rti_info.json" -Raw | ConvertFrom-Json
$eventhouseId = $info.eventhouseId
$kqlDbId      = $info.databases[0].id     # Eventhouse 宛先には KQL Database の item id を指定
$dbName       = $info.databases[0].name   # = Eventhouse 名と同じ KQL DB 名

function B64([string]$s) {
    [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($s))
}

# --- トポロジ JSON ---
$srcId    = [guid]::NewGuid().ToString()
$dstId    = [guid]::NewGuid().ToString()
$streamId = [guid]::NewGuid().ToString()

$topology = [ordered]@{
    sources = @(
        [ordered]@{
            id         = $srcId
            name       = 'ClientTelemetry'
            type       = 'CustomEndpoint'
            properties = @{}
        }
    )
    destinations = @(
        [ordered]@{
            id   = $dstId
            name = 'ToEventhouse'
            type = 'Eventhouse'
            properties = [ordered]@{
                dataIngestionMode  = 'ProcessedIngestion'
                workspaceId        = $WorkspaceId
                itemId             = $kqlDbId
                databaseName       = $dbName
                tableName          = 'Telemetry'
                inputSerialization = @{ type = 'Json'; properties = @{ encoding = 'UTF8' } }
            }
            inputNodes = @(@{ name = 'ClientTelemetry-stream' })
        }
    )
    operators = @()
    streams = @(
        [ordered]@{
            id         = $streamId
            name       = 'ClientTelemetry-stream'
            type       = 'DefaultStream'
            properties = @{}
            inputNodes = @(@{ name = 'ClientTelemetry' })
        }
    )
    compatibilityLevel = '1.1'
}
$topologyJson = $topology | ConvertTo-Json -Depth 30

$platform = [ordered]@{
    '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json'
    metadata  = [ordered]@{ type = 'Eventstream'; displayName = $esName }
    config    = [ordered]@{ version = '2.0'; logicalId = '00000000-0000-0000-0000-000000000000' }
}
$platformJson = $platform | ConvertTo-Json -Depth 10

# --- 既存確認 ---
$existing = Get-FabricItems -Type 'Eventstream' | Where-Object { $_.displayName -eq $esName }
if ($existing) {
    Write-Host "既に存在: Eventstream $($existing.id)"
    $esId = $existing.id
} else {
    Write-Host "== Eventstream 作成: $esName =="
    $body = [ordered]@{
        displayName = $esName
        description = 'Scenario C client real-time telemetry ingress'
        definition  = [ordered]@{
            parts = @(
                @{ path = 'eventstream.json'; payload = (B64 $topologyJson); payloadType = 'InlineBase64' }
                @{ path = '.platform';        payload = (B64 $platformJson);  payloadType = 'InlineBase64' }
            )
        }
    }
    $es = Invoke-FabricRest -Method POST -Path "/workspaces/$WorkspaceId/eventstreams" -Body $body
    $esId = $es.id
    if (-not $esId) {
        # LRO の結果に id が無い場合は一覧から取得
        Start-Sleep -Seconds 5
        $esId = (Get-FabricItems -Type 'Eventstream' | Where-Object { $_.displayName -eq $esName }).id
    }
    Write-Host "作成完了: Eventstream $esId"
}

# --- トポロジから CustomEndpoint ソース id を取得 ---
Write-Host "== トポロジ取得（ソースID特定）=="
$topo = Invoke-FabricRest -Method GET -Path "/workspaces/$WorkspaceId/eventstreams/$esId/topology"
$customSrc = $topo.sources | Where-Object { $_.type -eq 'CustomEndpoint' } | Select-Object -First 1
if (-not $customSrc) { throw 'CustomEndpoint ソースが見つかりません' }
Write-Host "CustomEndpoint source id: $($customSrc.id)"

# --- ソース接続（Event Hub 互換 接続文字列）取得 ---
Write-Host "== 接続文字列取得 =="
$conn = Invoke-FabricRest -Method GET -Path "/workspaces/$WorkspaceId/eventstreams/$esId/sources/$($customSrc.id)/connection"

$connOut = [ordered]@{
    eventstreamId            = $esId
    eventstreamName          = $esName
    sourceId                 = $customSrc.id
    fullyQualifiedNamespace  = $conn.fullyQualifiedNamespace
    eventHubName             = $conn.eventHubName
    primaryConnectionString  = $conn.accessKeys.primaryConnectionString
}
$connOut | ConvertTo-Json -Depth 10 | Set-Content "$PSScriptRoot\.eventstream_connection.json" -Encoding utf8
Write-Host "== .eventstream_connection.json に保存しました（秘密情報・gitignore済）=="
Write-Host "  namespace : $($conn.fullyQualifiedNamespace)"
Write-Host "  eventHub  : $($conn.eventHubName)"
Write-Host "  接続文字列は .eventstream_connection.json を参照"
