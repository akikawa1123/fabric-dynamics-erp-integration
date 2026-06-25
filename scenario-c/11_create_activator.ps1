# フェーズ4-2: Activator (Reflex) を定義付きで作成
#   Eventhouse(KQL) を 60 秒間隔でクエリし、4 センサーの異常値を検知したら
#   通知先 (config の alertRecipient) へ Teams 通知を送る。
#   オブジェクト: 製造ステーション (station_id)
#   ルール: トルク>50Nm / 振動>4.6mm/s / 温度>65℃ / 寸法偏差>15µm
. "$PSScriptRoot\fabric_common.ps1"

$reflexName = 'act_quality_alerts'
$recipient  = $global:AlertRecipient
if (-not $recipient) { throw "AlertRecipient が未設定です。config.local.json の alertRecipient を設定してください。" }

$info         = Get-Content "$PSScriptRoot\rti_info.json" -Raw | ConvertFrom-Json
$eventhouseId = $info.eventhouseId

function New-Guid2 { [guid]::NewGuid().ToString() }
function B64([string]$s) { [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($s)) }
# テンプレート instance は「JSON 文字列」として埋め込む必要があるため compress して返す
function To-Instance($obj) { $obj | ConvertTo-Json -Depth 50 -Compress }

# --- エンティティ GUID ---
$contId = New-Guid2
$srcId  = New-Guid2
$evtId  = New-Guid2
$objId  = New-Guid2
$idAttr = New-Guid2
$aTorque = New-Guid2; $aVib = New-Guid2; $aTemp = New-Guid2; $aDim = New-Guid2

# --- KQL ソースクエリ（60秒ごと・ステーション別に各センサーの最大値を取得）---
$kqlQuery = @'
Telemetry
| where event_time > ago(2m)
| summarize
    torque_nm        = round(max(torque_nm), 2),
    vibration_mm_s   = round(max(vibration_mm_s), 2),
    temperature_c    = round(max(temperature_c), 2),
    dimension_dev_um = round(max(dimension_dev_um), 2),
    product_number   = take_any(product_number),
    line_id          = take_any(line_id)
  by station_id
'@

# --- instance ビルダー ---------------------------------------------------
function Arg($name, $type, $value) { [ordered]@{ name = $name; type = $type; value = $value } }

function New-BasicAttrInstance([string]$eventEntityId, [string]$fieldName) {
    To-Instance ([ordered]@{
        templateId      = 'BasicEventAttribute'
        templateVersion = '1.1'
        steps           = @(
            [ordered]@{
                name = 'EventSelectStep'; id = (New-Guid2)
                rows = @(
                    [ordered]@{ name = 'EventSelector'; kind = 'Event'; arguments = @(
                        [ordered]@{ kind = 'EventReference'; type = 'complex'; name = 'event'
                                    arguments = @( (Arg 'entityId' 'string' $eventEntityId) ) }
                    ) }
                    [ordered]@{ name = 'EventFieldSelector'; kind = 'EventField'; arguments = @( (Arg 'fieldName' 'string' $fieldName) ) }
                )
            }
            [ordered]@{
                name = 'EventComputeStep'; id = (New-Guid2)
                rows = @(
                    [ordered]@{ name = 'TypeAssertion'; kind = 'TypeAssertion'; arguments = @( (Arg 'op' 'string' 'Number'), (Arg 'format' 'string' '') ) }
                )
            }
        )
    })
}

function New-IdentityInstance {
    To-Instance ([ordered]@{
        templateId      = 'IdentityPartAttribute'
        templateVersion = '1.1'
        steps           = @(
            [ordered]@{
                name = 'IdPartStep'; id = (New-Guid2)
                rows = @(
                    [ordered]@{ name = 'TypeAssertion'; kind = 'TypeAssertion'; arguments = @( (Arg 'op' 'string' 'Text'), (Arg 'format' 'string' '') ) }
                )
            }
        )
    })
}

function New-RuleInstance([string]$attrEntityId, [double]$threshold, [string]$headline, [string]$message) {
    To-Instance ([ordered]@{
        templateId      = 'AttributeTrigger'
        templateVersion = '1.1'
        steps           = @(
            [ordered]@{
                name = 'ScalarSelectStep'; id = (New-Guid2)
                rows = @(
                    [ordered]@{ name = 'AttributeSelector'; kind = 'Attribute'; arguments = @(
                        [ordered]@{ kind = 'AttributeReference'; type = 'complex'; name = 'attribute'
                                    arguments = @( (Arg 'entityId' 'string' $attrEntityId) ) }
                    ) }
                    [ordered]@{ name = 'NumberSummary'; kind = 'NumberSummary'; arguments = @(
                        (Arg 'op' 'string' 'Average')
                        [ordered]@{ kind = 'TimeDrivenWindowSpec'; type = 'complex'; name = 'window'
                                    arguments = @( (Arg 'width' 'timeSpan' 60000.0), (Arg 'hop' 'timeSpan' 60000.0) ) }
                    ) }
                )
            }
            [ordered]@{
                name = 'ScalarDetectStep'; id = (New-Guid2)
                rows = @(
                    [ordered]@{ name = 'NumberBecomes'; kind = 'NumberBecomes'; arguments = @( (Arg 'op' 'string' 'BecomesGreaterThan'), (Arg 'value' 'number' $threshold) ) }
                    [ordered]@{ name = 'OccurrenceOption'; kind = 'EachTime'; arguments = @() }
                )
            }
            [ordered]@{
                name = 'ActStep'; id = (New-Guid2)
                rows = @(
                    [ordered]@{ name = 'TeamsBinding'; kind = 'TeamsMessage'; arguments = @(
                        (Arg 'messageLocale' 'string' 'ja-jp')
                        [ordered]@{ name = 'recipients'; type = 'array'; values = @( [ordered]@{ type = 'string'; value = $recipient } ) }
                        [ordered]@{ name = 'headline'; type = 'array'; values = @( [ordered]@{ type = 'string'; value = $headline } ) }
                        [ordered]@{ name = 'optionalMessage'; type = 'array'; values = @( [ordered]@{ type = 'string'; value = $message } ) }
                        [ordered]@{ name = 'additionalInformation'; type = 'array'; values = @( [ordered]@{ type = 'string'; value = 'plant=JP-NAGOYA-01' } ) }
                    ) }
                )
            }
        )
    })
}

# --- エンティティ配列 ----------------------------------------------------
$entities = @(
    # コンテナ
    [ordered]@{ uniqueIdentifier = $contId; type = 'container-v1'
        payload = [ordered]@{ name = '製造品質アラート'; type = 'kqlQueries' } }

    # KQL データソース（Eventhouse を 60 秒間隔でクエリ）
    [ordered]@{ uniqueIdentifier = $srcId; type = 'kqlSource-v1'
        payload = [ordered]@{
            name           = 'Telemetry センサー監視'
            runSettings    = [ordered]@{ executionIntervalInSeconds = 60 }
            query          = [ordered]@{ queryString = $kqlQuery }
            eventhouseItem = [ordered]@{ targetUniqueIdentifier = $eventhouseId }
            parentContainer = [ordered]@{ targetUniqueIdentifier = $contId }
        } }

    # イベントビュー（ソースからイベントを選択）
    [ordered]@{ uniqueIdentifier = $evtId; type = 'timeSeriesView-v1'
        payload = [ordered]@{
            name = 'センサーイベント'
            parentContainer = [ordered]@{ targetUniqueIdentifier = $contId }
            definition = [ordered]@{ type = 'Event'
                instance = (To-Instance ([ordered]@{
                    templateId = 'SourceEvent'; templateVersion = '1.1'
                    steps = @(
                        [ordered]@{ name = 'SourceEventStep'; id = (New-Guid2)
                            rows = @( [ordered]@{ name = 'SourceSelector'; kind = 'SourceReference'; arguments = @( (Arg 'entityId' 'string' $srcId) ) } ) }
                    )
                })) }
        } }

    # オブジェクト（製造ステーション）
    [ordered]@{ uniqueIdentifier = $objId; type = 'timeSeriesView-v1'
        payload = [ordered]@{
            name = '製造ステーション'
            parentContainer = [ordered]@{ targetUniqueIdentifier = $contId }
            definition = [ordered]@{ type = 'Object' }
        } }

    # 識別属性（station_id）— 名前を出力列名に一致させる
    [ordered]@{ uniqueIdentifier = $idAttr; type = 'timeSeriesView-v1'
        payload = [ordered]@{
            name = 'station_id'
            parentObject = [ordered]@{ targetUniqueIdentifier = $objId }
            parentContainer = [ordered]@{ targetUniqueIdentifier = $contId }
            definition = [ordered]@{ type = 'Attribute'; instance = (New-IdentityInstance) }
        } }

    # センサー属性 ×4
    [ordered]@{ uniqueIdentifier = $aTorque; type = 'timeSeriesView-v1'
        payload = [ordered]@{ name = 'トルク (Nm)'
            parentObject = [ordered]@{ targetUniqueIdentifier = $objId }
            parentContainer = [ordered]@{ targetUniqueIdentifier = $contId }
            definition = [ordered]@{ type = 'Attribute'; instance = (New-BasicAttrInstance $evtId 'torque_nm') } } }
    [ordered]@{ uniqueIdentifier = $aVib; type = 'timeSeriesView-v1'
        payload = [ordered]@{ name = '振動 (mm/s)'
            parentObject = [ordered]@{ targetUniqueIdentifier = $objId }
            parentContainer = [ordered]@{ targetUniqueIdentifier = $contId }
            definition = [ordered]@{ type = 'Attribute'; instance = (New-BasicAttrInstance $evtId 'vibration_mm_s') } } }
    [ordered]@{ uniqueIdentifier = $aTemp; type = 'timeSeriesView-v1'
        payload = [ordered]@{ name = '温度 (℃)'
            parentObject = [ordered]@{ targetUniqueIdentifier = $objId }
            parentContainer = [ordered]@{ targetUniqueIdentifier = $contId }
            definition = [ordered]@{ type = 'Attribute'; instance = (New-BasicAttrInstance $evtId 'temperature_c') } } }
    [ordered]@{ uniqueIdentifier = $aDim; type = 'timeSeriesView-v1'
        payload = [ordered]@{ name = '寸法偏差 (µm)'
            parentObject = [ordered]@{ targetUniqueIdentifier = $objId }
            parentContainer = [ordered]@{ targetUniqueIdentifier = $contId }
            definition = [ordered]@{ type = 'Attribute'; instance = (New-BasicAttrInstance $evtId 'dimension_dev_um') } } }

    # ルール ×4（しきい値超過で Teams 通知）
    [ordered]@{ uniqueIdentifier = (New-Guid2); type = 'timeSeriesView-v1'
        payload = [ordered]@{ name = '[品質異常] 圧入トルク超過 (>50Nm)'
            parentObject = [ordered]@{ targetUniqueIdentifier = $objId }
            parentContainer = [ordered]@{ targetUniqueIdentifier = $contId }
            definition = [ordered]@{ type = 'Rule'
                instance = (New-RuleInstance $aTorque 50.0 '[品質異常] 圧入トルク超過' '製造ステーションでトルクが規格上限 50Nm を超過しました。圧入工程を確認してください。')
                settings = [ordered]@{ shouldRun = $true; shouldApplyRuleOnUpdate = $false } } } }
    [ordered]@{ uniqueIdentifier = (New-Guid2); type = 'timeSeriesView-v1'
        payload = [ordered]@{ name = '[品質異常] 振動超過 (>4.6mm/s)'
            parentObject = [ordered]@{ targetUniqueIdentifier = $objId }
            parentContainer = [ordered]@{ targetUniqueIdentifier = $contId }
            definition = [ordered]@{ type = 'Rule'
                instance = (New-RuleInstance $aVib 4.6 '[品質異常] 振動超過' '製造ステーションで振動が 4.6mm/s を超過しました。設備の状態を確認してください。')
                settings = [ordered]@{ shouldRun = $true; shouldApplyRuleOnUpdate = $false } } } }
    [ordered]@{ uniqueIdentifier = (New-Guid2); type = 'timeSeriesView-v1'
        payload = [ordered]@{ name = '[品質異常] 温度超過 (>65℃)'
            parentObject = [ordered]@{ targetUniqueIdentifier = $objId }
            parentContainer = [ordered]@{ targetUniqueIdentifier = $contId }
            definition = [ordered]@{ type = 'Rule'
                instance = (New-RuleInstance $aTemp 65.0 '[品質異常] 温度超過' '製造ステーションで温度が 65℃ を超過しました。冷却・加工条件を確認してください。')
                settings = [ordered]@{ shouldRun = $true; shouldApplyRuleOnUpdate = $false } } } }
    [ordered]@{ uniqueIdentifier = (New-Guid2); type = 'timeSeriesView-v1'
        payload = [ordered]@{ name = '[品質異常] 寸法偏差超過 (>15µm)'
            parentObject = [ordered]@{ targetUniqueIdentifier = $objId }
            parentContainer = [ordered]@{ targetUniqueIdentifier = $contId }
            definition = [ordered]@{ type = 'Rule'
                instance = (New-RuleInstance $aDim 15.0 '[品質異常] 寸法偏差超過' '製造ステーションで寸法偏差が 15µm を超過しました。加工精度を確認してください。')
                settings = [ordered]@{ shouldRun = $true; shouldApplyRuleOnUpdate = $false } } } }
)

$entitiesJson = $entities | ConvertTo-Json -Depth 60
$entitiesB64  = B64 $entitiesJson

# .platform
$platform = [ordered]@{
    '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json'
    metadata  = [ordered]@{ type = 'Reflex'; displayName = $reflexName }
    config    = [ordered]@{ version = '2.0'; logicalId = (New-Guid2) }
}
$platformB64 = B64 ($platform | ConvertTo-Json -Depth 10)

$definition = [ordered]@{
    parts  = @(
        [ordered]@{ path = 'ReflexEntities.json'; payload = $entitiesB64; payloadType = 'InlineBase64' }
        [ordered]@{ path = '.platform';           payload = $platformB64; payloadType = 'InlineBase64' }
    )
}

# 作成方式: 定義なしで Reflex を作成 → updateDefinition で定義を流し込む
# (このキャパシティでは create-with-definition が ALM で弾かれるため)
$existing = Get-FabricItems | Where-Object { $_.displayName -eq $reflexName -and $_.type -eq 'Reflex' } | Select-Object -First 1
if ($existing) {
    $reflexId = $existing.id
    Write-Host "== 既存 Activator: $reflexId =="
}
else {
    Write-Host "== Activator 作成中 (定義なし): $reflexName =="
    $res = Invoke-FabricRest -Method POST -Path "/workspaces/$WorkspaceId/reflexes" -Body ([ordered]@{ displayName = $reflexName })
    $reflexId = $res.id
    if (-not $reflexId) {
        Start-Sleep -Seconds 5
        $reflexId = (Get-FabricItems | Where-Object { $_.displayName -eq $reflexName -and $_.type -eq 'Reflex' } | Select-Object -First 1).id
    }
}

Write-Host "== 定義を反映中 (updateDefinition) =="
$defImported = $false
try {
    Invoke-FabricRest -Method POST -Path "/workspaces/$WorkspaceId/reflexes/$reflexId/updateDefinition" -Body ([ordered]@{ definition = $definition }) | Out-Null
    $defImported = $true
    Write-Host "定義の反映に成功しました。"
}
catch {
    Write-Warning "Activator のパブリック定義インポートが当キャパシティで未対応のため、ルール定義を流し込めませんでした。"
    Write-Warning "詳細: $_"
    Write-Host ""
    Write-Host "空の Activator '$reflexName' は作成済みです。ポータルで以下を手動設定してください:"
    Write-Host "  1) Activator を開く → [データの取得] → Eventhouse '$($info.databases[0].name)' / Telemetry を KQL ソースに追加"
    Write-Host "  2) オブジェクト = station_id、属性 = torque_nm / vibration_mm_s / temperature_c / dimension_dev_um"
    Write-Host "  3) 各属性にルール作成: トルク>50 / 振動>4.6 / 温度>65 / 寸法偏差>15 → アクション=Teams → 宛先 $recipient"
    Write-Host "  ※ あるいは Real-Time Dashboard の各センサータイルから [アラートの設定] でも同等に作成できます。"
}

Write-Host "Activator itemId: $reflexId"

@{ activatorId = $reflexId; name = $reflexName; recipient = $recipient } | ConvertTo-Json |
    Set-Content "$PSScriptRoot\activator_info.json" -Encoding UTF8
Write-Host "完了。ポータルで Activator '$reflexName' を開き、各ルールの状態と Teams 接続を確認してください。"
