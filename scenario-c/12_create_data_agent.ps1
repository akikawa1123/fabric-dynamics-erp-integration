# フェーズ4: Fabric データエージェント(Data Agent) 仕上げ — 単一 Lakehouse ソース構成
#   ソース: Lakehouse lh_quality_analytics (スキーマ dbo / NL2SQL)
#     - Telemetry                    … 工場ラインのリアルタイム品質テレメトリ (Eventhouse→OneLake ミラー)
#     - ERP_FulfillmentOrder         … ERP 受注ヘッダ
#     - ERP_FulfillmentOrderDetail   … ERP 受注明細
#     - ERP_ReturnOrderDetail        … ERP 返品明細 (製品コード↔GUID ブリッジ)
#   ※ 全テーブルが同一 Lakehouse のため Telemetry×ERP のクロスドメイン JOIN が 1 クエリで可能。
#
# このスクリプトは「ポータルで作成済みのエージェント (Lakehouse ソース追加済み)」を仕上げる:
#   1) getDefinition でポータルが生成した datasource.json を取得し、そのまま保持
#   2) AI 指示 (stage_config.aiInstructions) と few-shot を data_agent/ から読み込んで注入
#   3) draft と published の両方に書き込み、updateDefinition で更新・公開
#
# 前提: ポータルで Data Agent 'da_manufacturing_erp' に Lakehouse 'lh_quality_analytics' を追加済み。
# 参照: https://learn.microsoft.com/rest/api/fabric/articles/item-management/definitions/data-agent-definition
. "$PSScriptRoot\fabric_common.ps1"

$ErrorActionPreference = 'Stop'

$agentName = 'da_manufacturing_erp'

Write-Host "== 設定 =="
Write-Host "  WorkspaceId : $WorkspaceId"
Write-Host "  Agent       : $agentName"

# --- UTF-8 ファイル読み込み (PS5.1 の CP932 化け回避のため .NET で明示) ---
function Read-Utf8([string]$rel) {
    [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot $rel), [System.Text.Encoding]::UTF8)
}
function To-B64([string]$s) {
    [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($s))
}
function Obj-To-B64($obj) {
    To-B64 (($obj | ConvertTo-Json -Depth 30 -Compress))
}

$aiInstructions = Read-Utf8 'data_agent\ai_instructions.txt'
$dsInstr        = Read-Utf8 'data_agent\datasource_instructions.txt'
$fewshots       = Read-Utf8 'data_agent\fewshots.json'

# --- 対象エージェントを名前で特定 ---
Write-Host "== Data Agent 特定 =="
$list = Invoke-FabricRest -Method GET -Path "/workspaces/$WorkspaceId/dataAgents"
$agent = $list.value | Where-Object { $_.displayName -eq $agentName } | Select-Object -First 1
if (-not $agent) { throw "Data Agent '$agentName' が見つかりません。先にポータルで作成し Lakehouse ソースを追加してください。" }
$agentId = $agent.id
Write-Host "  AgentId : $agentId"

# --- 既存定義を取得し、ポータル生成の datasource.json を保持 ---
Write-Host "== 既存定義(getDefinition) を取得 =="
$def = Invoke-FabricRest -Method POST -Path "/workspaces/$WorkspaceId/items/$agentId/getDefinition"
$dsPart = $def.definition.parts | Where-Object { $_.path -like 'Files/Config/draft/*/datasource.json' } | Select-Object -First 1
if (-not $dsPart) { throw "datasource.json (draft) が定義に見つかりません。ポータルで Lakehouse ソースを追加済みか確認してください。" }

# データソースのフォルダ名 (例: lakehouse-tables-lh_quality_analytics) を抽出
$dsFolder = ($dsPart.path -replace '^Files/Config/draft/', '') -replace '/datasource\.json$', ''
$dsB64    = $dsPart.payload                       # ポータル生成 datasource.json
$dsInfo   = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($dsB64)) | ConvertFrom-Json
Write-Host "  DataSource : $($dsInfo.displayName) (type=$($dsInfo.type))"
Write-Host "  artifactId : $($dsInfo.artifactId)"
Write-Host "  folder     : $dsFolder"

# --- 注入する設定 ---
$dataAgentJson = [ordered]@{ '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/dataAgent/definition/dataAgent/2.1.0/schema.json' }
$stageConfig   = [ordered]@{
    '$schema'      = 'https://developer.microsoft.com/json-schemas/fabric/item/dataAgent/definition/stageConfiguration/1.0.0/schema.json'
    aiInstructions = $aiInstructions
}
$publishInfo   = [ordered]@{ '$schema' = '1.0.0'; description = '製造品質×ERP データエージェント (単一 Lakehouse / クロスドメイン T-SQL)' }

# Telemetry の varchar 列 event_time を非選択にして、エージェントが日時計算に使えないようにする
# (datetime2 の EventEnqueuedUtcTime を使わせ、SQL 生成時の変換エラーを防ぐ)
# ただし列を非選択にすると親テーブルの is_selected が False(部分選択)になり、
# Data Agent がテーブルごと対象外にしてしまうため、テーブルの is_selected は True に強制する。
function Set-ColumnDeselected($node, [string]$colName) {
    if ($null -eq $node) { return }
    foreach ($n in @($node)) {
        if ($n.PSObject.Properties['type'] -and $n.type -like '*column*' -and $n.display_name -eq $colName) {
            if ($n.PSObject.Properties['is_selected']) { $n.is_selected = $false }
            else { $n | Add-Member -NotePropertyName is_selected -NotePropertyValue $false -Force }
            Write-Host "  Deselected column: $colName"
        }
        if ($n.PSObject.Properties['children']) { Set-ColumnDeselected $n.children $colName }
    }
}
function Set-TableSelected($node, [string]$tableName) {
    if ($null -eq $node) { return }
    foreach ($n in @($node)) {
        if ($n.PSObject.Properties['type'] -and $n.type -like '*table*' -and $n.display_name -eq $tableName) {
            if ($n.PSObject.Properties['is_selected']) { $n.is_selected = $true }
            else { $n | Add-Member -NotePropertyName is_selected -NotePropertyValue $true -Force }
            Write-Host "  Forced table selected: $tableName"
        }
        if ($n.PSObject.Properties['children']) { Set-TableSelected $n.children $tableName }
    }
}
if ($dsInfo.PSObject.Properties['elements']) {
    Set-ColumnDeselected $dsInfo.elements 'event_time'
    Set-TableSelected    $dsInfo.elements 'Telemetry'
}

# データソースに dataSourceInstructions を載せ直す (ポータル生成のメタ/elements は保持)
$dsInfo | Add-Member -NotePropertyName dataSourceInstructions -NotePropertyValue $dsInstr -Force
$dsWithInstrB64 = To-B64 ($dsInfo | ConvertTo-Json -Depth 50 -Compress)

$stageB64 = Obj-To-B64 $stageConfig
$fsB64    = To-B64 $fewshots

# --- 公開定義 parts (draft と published の両方) ---
$parts = [System.Collections.Generic.List[object]]::new()
$parts.Add(@{ path = 'Files/Config/data_agent.json';                       payload = (Obj-To-B64 $dataAgentJson); payloadType = 'InlineBase64' })
$parts.Add(@{ path = 'Files/Config/draft/stage_config.json';               payload = $stageB64;        payloadType = 'InlineBase64' })
$parts.Add(@{ path = "Files/Config/draft/$dsFolder/datasource.json";       payload = $dsWithInstrB64;  payloadType = 'InlineBase64' })
$parts.Add(@{ path = "Files/Config/draft/$dsFolder/fewshots.json";         payload = $fsB64;           payloadType = 'InlineBase64' })
$parts.Add(@{ path = 'Files/Config/published/stage_config.json';           payload = $stageB64;        payloadType = 'InlineBase64' })
$parts.Add(@{ path = "Files/Config/published/$dsFolder/datasource.json";   payload = $dsWithInstrB64;  payloadType = 'InlineBase64' })
$parts.Add(@{ path = "Files/Config/published/$dsFolder/fewshots.json";     payload = $fsB64;           payloadType = 'InlineBase64' })
$parts.Add(@{ path = 'Files/Config/publish_info.json';                     payload = (Obj-To-B64 $publishInfo); payloadType = 'InlineBase64' })
$definition = @{ parts = $parts.ToArray() }

# --- 定義を更新(updateDefinition) ---
Write-Host "== 定義を更新(updateDefinition) =="
Invoke-FabricRest -Method POST -Path "/workspaces/$WorkspaceId/dataAgents/$agentId/updateDefinition" -Body @{ definition = $definition } | Out-Null

# --- 結果保存 ---
$out = [ordered]@{
    dataAgentId   = $agentId
    dataAgentName = $agentName
    workspaceId   = $WorkspaceId
    source        = [ordered]@{
        type        = $dsInfo.type
        artifactId  = $dsInfo.artifactId
        displayName = $dsInfo.displayName
        tables      = @('Telemetry', 'ERP_FulfillmentOrder', 'ERP_FulfillmentOrderDetail', 'ERP_ReturnOrderDetail')
    }
}
$out | ConvertTo-Json -Depth 10 | Set-Content "$PSScriptRoot\data_agent_info.json" -Encoding UTF8
Write-Host "== 保存: data_agent_info.json =="
$out | ConvertTo-Json -Depth 10

Write-Host ""
Write-Host "完了。ポータルで Data Agent '$agentName' を開き、次を試してください:"
Write-Host "  営業:   「Contoso の進行中の受注を一覧で。出荷予定日と状態も。」"
Write-Host "  工場:   「今、品質異常は出ている？どの製品・ロット・ステーション？」"
Write-Host "  横断:   「今 品質異常が出ている製品の進行中オーダー(顧客・出荷予定)を出して。」"
