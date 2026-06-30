@description('Graph-based incident ingress workflow name.')
param ingressWorkflowName string = 'la-mq-incident-ingress-graph'

@description('Graph-based factory decision handoff workflow name.')
param handoffWorkflowName string = 'la-mq-factory-decision-handoff-graph'

@description('GET-link factory decision handoff workflow name for Teams action links.')
param handoffLinkWorkflowName string = 'la-mq-factory-decision-handoff-link-graph'

@description('Azure region.')
param location string = resourceGroup().location

// Values below are sanitized for the public repo. The Teams @mention object IDs
// are zeroed placeholders (00000000-...0001/0002), and teamsTeamId/teamsChannelId/
// agentChatUrl default to placeholders. Set real Entra user object IDs, your Team/
// channel IDs, and your published M365 Copilot agent link at deploy time
// (e.g. via the parameters file) for mentions, notifications, and links to work.
@description('Microsoft Graph site path, for example contoso-demo.sharepoint.com:/sites/ManufacturingQualityDemo:')
param graphSitePath string

@description('SharePoint list ID for MQ_StakeholderRouting.')
param routingListId string

@description('SharePoint list ID for MQ_QualityIncidents.')
param incidentListId string

@description('SharePoint list ID for MQ_WorkPackages.')
param workPackageListId string

@description('Optional Microsoft Teams API connection shell name for later notification actions.')
param teamsConnectionName string = 'conn-teams-mq-demo'

@description('Team ID for demo notifications. Placeholder; set your real Team ID at deploy time.')
param teamsTeamId string = '00000000-0000-0000-0000-000000000000'

@description('Channel ID for demo notifications. Placeholder; set your real channel ID at deploy time.')
param teamsChannelId string = '19:00000000000000000000000000000000@thread.tacv2'

@description('M365 Copilot agent deep link used in Teams notifications. Placeholder; set your published agent link at deploy time.')
param agentChatUrl string = 'https://m365.cloud.microsoft/chat/agent/REPLACE_WITH_YOUR_AGENT_LINK'

var graphAudience = 'https://graph.microsoft.com'
var graphBase = 'https://graph.microsoft.com/v1.0/sites/${graphSitePath}'
var encodedTeamsChannelId = uriComponent(teamsChannelId)
var handoffLinkCallback = listCallbackUrl('${resourceId('Microsoft.Logic/workflows/triggers', handoffLinkWorkflowName, 'manual')}', '2019-05-01').value
var handoffPostCallback = listCallbackUrl('${resourceId('Microsoft.Logic/workflows/triggers', handoffWorkflowName, 'manual')}', '2019-05-01').value

resource teamsConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: teamsConnectionName
  location: location
  properties: {
    displayName: 'Microsoft Teams - Manufacturing Quality Demo'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'teams')
    }
  }
}

resource ingressWorkflow 'Microsoft.Logic/workflows@2019-05-01' = {
  name: ingressWorkflowName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  dependsOn: [
    handoffLinkWorkflow
  ]
  properties: {
    state: 'Enabled'
    connectionReferences: {
      shared_teams: {
        connection: {
          id: teamsConnection.id
        }
        api: {
          id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'teams')
        }
      }
    }
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2023-01-31-preview/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                activationTime: { type: 'string' }
                plantId: { type: 'string' }
                lineId: { type: 'string' }
                stationId: { type: 'string' }
                productNumber: { type: 'string' }
                lotId: { type: 'string' }
                metricName: { type: 'string' }
                observedValue: { type: 'string' }
                thresholdValue: { type: 'string' }
                unit: { type: 'string' }
                dashboardUrl: { type: 'string' }
              }
              required: [
                'plantId'
                'lineId'
                'stationId'
                'productNumber'
                'lotId'
                'observedValue'
                'thresholdValue'
              ]
            }
          }
        }
      }
      actions: {
        Get_routing_items: {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: '${graphBase}/lists/${routingListId}/items?expand=fields&$top=100'
            authentication: {
              type: 'ManagedServiceIdentity'
              audience: graphAudience
            }
          }
          runAfter: {}
        }
        Filter_factory_owner: {
          type: 'Query'
          inputs: {
            from: '@body(\'Get_routing_items\')?[\'value\']'
            where: '@and(equals(item()?[\'fields\']?[\'role_code\'], \'factory_quality_owner\'), equals(item()?[\'fields\']?[\'plant_id\'], triggerBody()?[\'plantId\']), equals(item()?[\'fields\']?[\'line_id\'], triggerBody()?[\'lineId\']))'
          }
          runAfter: {
            Get_routing_items: [
              'Succeeded'
            ]
          }
        }
        Filter_global_fallback: {
          type: 'Query'
          inputs: {
            from: '@body(\'Get_routing_items\')?[\'value\']'
            where: '@equals(item()?[\'fields\']?[\'role_code\'], \'global_fallback\')'
          }
          runAfter: {
            Filter_factory_owner: [
              'Succeeded'
            ]
          }
        }
        Compose_incident_id: {
          type: 'Compose'
          inputs: '@{concat(\'QI-\', formatDateTime(utcNow(), \'yyyyMMdd-HHmmss\'))}'
          runAfter: {
            Filter_global_fallback: [
              'Succeeded'
            ]
          }
        }
        Compose_owner_upn: {
          type: 'Compose'
          inputs: '@{if(greater(length(body(\'Filter_factory_owner\')), 0), first(body(\'Filter_factory_owner\'))?[\'fields\']?[\'user_upn\'], first(body(\'Filter_global_fallback\'))?[\'fields\']?[\'user_upn\'])}'
          runAfter: {
            Compose_incident_id: [
              'Succeeded'
            ]
          }
        }
        Compose_work_package_id: {
          type: 'Compose'
          inputs: '@{concat(\'WP-F-\', formatDateTime(utcNow(), \'yyyyMMdd-HHmmss\'))}'
          runAfter: {
            Compose_owner_upn: [
              'Succeeded'
            ]
          }
        }
        Create_incident: {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '${graphBase}/lists/${incidentListId}/items'
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              fields: {
                Title: '@{outputs(\'Compose_incident_id\')}'
                incident_id: '@{outputs(\'Compose_incident_id\')}'
                activation_time: '@{coalesce(triggerBody()?[\'activationTime\'], utcNow())}'
                plant_id: '@{triggerBody()?[\'plantId\']}'
                line_id: '@{triggerBody()?[\'lineId\']}'
                station_id: '@{triggerBody()?[\'stationId\']}'
                product_number: '@{triggerBody()?[\'productNumber\']}'
                lot_id: '@{triggerBody()?[\'lotId\']}'
                metric_name: '@{coalesce(triggerBody()?[\'metricName\'], \'torque_nm\')}'
                observed_value: '@{triggerBody()?[\'observedValue\']}'
                threshold_value: '@{triggerBody()?[\'thresholdValue\']}'
                unit: '@{coalesce(triggerBody()?[\'unit\'], \'Nm\')}'
                status: 'open'
                dashboard_url: '@{triggerBody()?[\'dashboardUrl\']}'
                factory_decision: 'pending'
              }
            }
            authentication: {
              type: 'ManagedServiceIdentity'
              audience: graphAudience
            }
          }
          runAfter: {
            Compose_work_package_id: [
              'Succeeded'
            ]
          }
        }
        Create_factory_work_package: {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '${graphBase}/lists/${workPackageListId}/items'
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              fields: {
                Title: '@{outputs(\'Compose_work_package_id\')}'
                work_package_id: '@{outputs(\'Compose_work_package_id\')}'
                incident_id: '@{outputs(\'Compose_incident_id\')}'
                work_package_type: 'factory'
                created_time: '@{utcNow()}'
                status: 'open'
                product_number: '@{triggerBody()?[\'productNumber\']}'
                lot_id: '@{triggerBody()?[\'lotId\']}'
                impact_level: 'candidate'
                candidate_or_confirmed: 'candidate'
                required_participants_upn: '@{outputs(\'Compose_owner_upn\')}'
                resolved_owner_upn: '@{outputs(\'Compose_owner_upn\')}'
                summary: '@{concat(triggerBody()?[\'stationId\'], \' torque > \', triggerBody()?[\'thresholdValue\'], \' \', coalesce(triggerBody()?[\'unit\'], \'Nm\'), \' anomaly for product \', triggerBody()?[\'productNumber\'], \' lot \', triggerBody()?[\'lotId\'])}'
                open_questions: 'Confirm lot allocation and root cause.'
              }
            }
            authentication: {
              type: 'ManagedServiceIdentity'
              audience: graphAudience
            }
          }
          runAfter: {
            Create_incident: [
              'Succeeded'
            ]
          }
        }
        Post_teams_notification: {
          type: 'OpenApiConnection'
          inputs: {
            host: {
              connection: {
                referenceName: 'shared_teams'
              }
              operationId: 'HttpRequest'
              apiId: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'teams')
            }
            parameters: {
              Method: 'POST'
              Uri: 'beta/teams/${teamsTeamId}/channels/${encodedTeamsChannelId}/messages'
              ContentType: 'application/json'
              Body: {
                body: {
                  contentType: 'html'
                  content: '<at id="0">Factory Owner</at><br/><b>製造品質異常を検知しました</b><br/>Incident: @{outputs(\'Compose_incident_id\')}<br/>Product: @{triggerBody()?[\'productNumber\']}<br/>Lot: @{triggerBody()?[\'lotId\']}<br/>Station: @{triggerBody()?[\'stationId\']}<br/>Torque: @{triggerBody()?[\'observedValue\']} @{coalesce(triggerBody()?[\'unit\'], \'Nm\')} &gt; @{triggerBody()?[\'thresholdValue\']} @{coalesce(triggerBody()?[\'unit\'], \'Nm\')}<br/>Owner: @{outputs(\'Compose_owner_upn\')}<br/>WorkPackage: @{outputs(\'Compose_work_package_id\')}<br/><br/><b>次のアクション</b><br/>1. <a href=\'${agentChatUrl}\'>AIで工場調査を開始</a><br/>2. 質問: <i>トルクが規格上限(50Nm)を超えた直近イベントを、製品・ロット・ステーション・ライン・トルク・時刻・状態つきで教えて。営業へcandidate引き継ぎが必要かも一言で。</i><br/>3. 品質文書も確認: <i>圧入工程でトルクが規格上限を超えた場合の初動対応と過去の8D事例を品質文書から教えて。8Dなど専門用語は初見でも分かるよう一言で説明し、文書IDと出典も。</i><br/>4. 顧客影響の可能性がある場合は <a href=\'${handoffLinkCallback}&incidentId=@{outputs(\'Compose_incident_id\')}&decision=candidate&productNumber=@{triggerBody()?[\'productNumber\']}&lotId=@{triggerBody()?[\'lotId\']}&customerName=Contoso\'>営業へ候補影響として引き継ぐ</a><br/>5. <a href=\'https://m365.cloud.microsoft/agents/cowork\'>Cowork</a> を開き、この WorkPackage を起点に対応準備（会議作成・設備停止・出荷停止は承認後）。入力例: <i>SharePointのMQ_WorkPackagesにある私担当のfactory Work Package（@{outputs(\'Compose_work_package_id\')}）を起点に、暫定封じ込め会議の最短30分枠、暫定封じ込め計画書(Word)、再検査チェックリスト(Excel)を草案で用意して。必須参加者UPNは変えない。会議作成・設備停止・出荷停止は私の承認後。</i>'
                }
                mentions: [
                  {
                    id: 0
                    mentionText: 'Factory Owner'
                    mentioned: {
                      user: {
                        '@@odata.type': '#microsoft.graph.teamworkUserIdentity'
                        id: '00000000-0000-0000-0000-000000000001'
                        displayName: 'Factory Owner'
                        userIdentityType: 'aadUser'
                      }
                    }
                  }
                ]
              }
            }
          }
          runAfter: {
            Create_factory_work_package: [
              'Succeeded'
            ]
          }
        }
        Response: {
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 200
            body: {
              incidentId: '@{outputs(\'Compose_incident_id\')}'
              workPackageId: '@{outputs(\'Compose_work_package_id\')}'
              resolvedOwnerUpn: '@{outputs(\'Compose_owner_upn\')}'
              routeUsed: '@{if(greater(length(body(\'Filter_factory_owner\')), 0), \'factory_quality_owner\', \'global_fallback\')}'
            }
          }
          runAfter: {
            Post_teams_notification: [
              'Succeeded'
            ]
          }
        }
      }
    }
  }
}

resource handoffWorkflow 'Microsoft.Logic/workflows@2019-05-01' = {
  name: handoffWorkflowName
  location: location
  identity: {
    type: 'SystemAssigned'
  }

  properties: {
    state: 'Enabled'
    connectionReferences: {
      shared_teams: {
        connection: {
          id: teamsConnection.id
        }
        api: {
          id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'teams')
        }
      }
    }
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2023-01-31-preview/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                incidentId: { type: 'string' }
                decision: { type: 'string' }
                productNumber: { type: 'string' }
                lotId: { type: 'string' }
                customerName: { type: 'string' }
              }
              required: [
                'incidentId'
                'decision'
                'productNumber'
                'lotId'
                'customerName'
              ]
            }
          }
        }
      }
      actions: {
        Get_routing_items: {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: '${graphBase}/lists/${routingListId}/items?expand=fields&$top=100'
            authentication: {
              type: 'ManagedServiceIdentity'
              audience: graphAudience
            }
          }
          runAfter: {}
        }
        Filter_sales_owner: {
          type: 'Query'
          inputs: {
            from: '@body(\'Get_routing_items\')?[\'value\']'
            where: '@and(equals(item()?[\'fields\']?[\'role_code\'], \'sales_owner\'), equals(item()?[\'fields\']?[\'customer_name\'], triggerBody()?[\'customerName\']), equals(item()?[\'fields\']?[\'product_number\'], triggerBody()?[\'productNumber\']))'
          }
          runAfter: {
            Get_routing_items: [
              'Succeeded'
            ]
          }
        }
        Filter_global_fallback: {
          type: 'Query'
          inputs: {
            from: '@body(\'Get_routing_items\')?[\'value\']'
            where: '@equals(item()?[\'fields\']?[\'role_code\'], \'global_fallback\')'
          }
          runAfter: {
            Filter_sales_owner: [
              'Succeeded'
            ]
          }
        }
        Get_incidents: {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: '${graphBase}/lists/${incidentListId}/items?expand=fields&$top=100'
            authentication: {
              type: 'ManagedServiceIdentity'
              audience: graphAudience
            }
          }
          runAfter: {
            Filter_global_fallback: [
              'Succeeded'
            ]
          }
        }
        Filter_incident: {
          type: 'Query'
          inputs: {
            from: '@body(\'Get_incidents\')?[\'value\']'
            where: '@equals(item()?[\'fields\']?[\'incident_id\'], triggerBody()?[\'incidentId\'])'
          }
          runAfter: {
            Get_incidents: [
              'Succeeded'
            ]
          }
        }
        Compose_owner_upn: {
          type: 'Compose'
          inputs: '@{if(greater(length(body(\'Filter_sales_owner\')), 0), first(body(\'Filter_sales_owner\'))?[\'fields\']?[\'user_upn\'], first(body(\'Filter_global_fallback\'))?[\'fields\']?[\'user_upn\'])}'
          runAfter: {
            Filter_incident: [
              'Succeeded'
            ]
          }
        }
        Compose_work_package_id: {
          type: 'Compose'
          inputs: '@{concat(\'WP-S-\', formatDateTime(utcNow(), \'yyyyMMdd-HHmmss\'))}'
          runAfter: {
            Compose_owner_upn: [
              'Succeeded'
            ]
          }
        }
        Update_incident: {
          type: 'Http'
          inputs: {
            method: 'PATCH'
            uri: '${graphBase}/lists/${incidentListId}/items/@{first(body(\'Filter_incident\'))?[\'id\']}/fields'
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              factory_decision: '@{triggerBody()?[\'decision\']}'
              decision_time: '@{utcNow()}'
              factory_responder_upn: '@{outputs(\'Compose_owner_upn\')}'
            }
            authentication: {
              type: 'ManagedServiceIdentity'
              audience: graphAudience
            }
          }
          runAfter: {
            Compose_work_package_id: [
              'Succeeded'
            ]
          }
        }
        Create_sales_work_package: {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '${graphBase}/lists/${workPackageListId}/items'
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              fields: {
                Title: '@{outputs(\'Compose_work_package_id\')}'
                work_package_id: '@{outputs(\'Compose_work_package_id\')}'
                incident_id: '@{triggerBody()?[\'incidentId\']}'
                work_package_type: 'sales'
                created_time: '@{utcNow()}'
                status: 'open'
                product_number: '@{triggerBody()?[\'productNumber\']}'
                lot_id: '@{triggerBody()?[\'lotId\']}'
                customer_name: '@{triggerBody()?[\'customerName\']}'
                impact_level: 'candidate'
                candidate_or_confirmed: 'candidate'
                required_participants_upn: '@{outputs(\'Compose_owner_upn\')}'
                resolved_owner_upn: '@{outputs(\'Compose_owner_upn\')}'
                summary: '@{concat(\'Candidate \', triggerBody()?[\'customerName\'], \' order impact for \', triggerBody()?[\'productNumber\'], \'; product-level match only.\')}'
                open_questions: 'Confirm lot allocation before customer notification.'
              }
            }
            authentication: {
              type: 'ManagedServiceIdentity'
              audience: graphAudience
            }
          }
          runAfter: {
            Update_incident: [
              'Succeeded'
            ]
          }
        }
        Post_teams_notification: {
          type: 'OpenApiConnection'
          inputs: {
            host: {
              connection: {
                referenceName: 'shared_teams'
              }
              operationId: 'HttpRequest'
              apiId: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'teams')
            }
            parameters: {
              Method: 'POST'
              Uri: 'beta/teams/${teamsTeamId}/channels/${encodedTeamsChannelId}/messages'
              ContentType: 'application/json'
              Body: {
                body: {
                  contentType: 'html'
                  content: '<at id="0">Sales Owner</at><br/><b>営業引き継ぎ Work Package を作成しました</b><br/>Incident: @{triggerBody()?[\'incidentId\']}<br/>WorkPackage: @{outputs(\'Compose_work_package_id\')}<br/>Customer: @{triggerBody()?[\'customerName\']}<br/>Product: @{triggerBody()?[\'productNumber\']}<br/>Impact: 候補影響(candidate)<br/>Owner: @{outputs(\'Compose_owner_upn\')}<br/><br/><b>次のアクション</b><br/>1. <a href=\'${agentChatUrl}\'>AIで営業調査を開始</a><br/>2. 質問: <i>今回の品質異常は @{triggerBody()?[\'productNumber\']} / @{triggerBody()?[\'lotId\']} です。Contoso 関連の進行中受注のうち影響候補を一覧で。ロット引当が未確認なら candidate として扱って。</i><br/>3. ロット引当が確認できるまで顧客影響は <b>候補影響(candidate)</b> として扱う<br/>4. <a href=\'https://m365.cloud.microsoft/agents/cowork\'>Cowork</a> を開き、この WorkPackage を起点に対応準備（送信・会議作成は承認後）。入力例: <i>MQ_WorkPackagesの私担当のsales Work Package（@{outputs(\'Compose_work_package_id\')}）を起点に、顧客影響確認会議の最短30分枠、顧客説明のPowerPoint、初報メール案を草案で用意して。confirmedとcandidateを分け、candidate/未確定と明記。必須参加者UPNは変えない。送信・会議作成は私の承認後。</i>'
                }
                mentions: [
                  {
                    id: 0
                    mentionText: 'Sales Owner'
                    mentioned: {
                      user: {
                        '@@odata.type': '#microsoft.graph.teamworkUserIdentity'
                        id: '00000000-0000-0000-0000-000000000002'
                        displayName: 'Sales Owner'
                        userIdentityType: 'aadUser'
                      }
                    }
                  }
                ]
              }
            }
          }
          runAfter: {
            Create_sales_work_package: [
              'Succeeded'
            ]
          }
        }
        Response: {
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 200
            body: {
              incidentId: '@{triggerBody()?[\'incidentId\']}'
              decision: '@{triggerBody()?[\'decision\']}'
              workPackageId: '@{outputs(\'Compose_work_package_id\')}'
              resolvedOwnerUpn: '@{outputs(\'Compose_owner_upn\')}'
              routeUsed: '@{if(greater(length(body(\'Filter_sales_owner\')), 0), \'sales_owner\', \'global_fallback\')}'
            }
          }
          runAfter: {
            Post_teams_notification: [
              'Succeeded'
            ]
          }
        }
      }
    }
  }
}

resource handoffLinkWorkflow 'Microsoft.Logic/workflows@2019-05-01' = {
  name: handoffLinkWorkflowName
  location: location
  dependsOn: [
    handoffWorkflow
  ]
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            method: 'GET'
            schema: {
              type: 'object'
            }
          }
        }
      }
      actions: {
        Call_handoff_workflow: {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: handoffPostCallback
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              incidentId: '@{triggerOutputs()?[\'queries\']?[\'incidentId\']}'
              decision: '@{coalesce(triggerOutputs()?[\'queries\']?[\'decision\'], \'candidate\')}'
              productNumber: '@{triggerOutputs()?[\'queries\']?[\'productNumber\']}'
              lotId: '@{triggerOutputs()?[\'queries\']?[\'lotId\']}'
              customerName: '@{coalesce(triggerOutputs()?[\'queries\']?[\'customerName\'], \'Contoso\')}'
            }
          }
          runAfter: {}
        }
        Browser_response: {
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 200
            headers: {
              'Content-Type': 'text/html; charset=utf-8'
            }
            body: '<html><body style="font-family:Segoe UI,sans-serif"><h2>営業へ引き継ぎました（candidate）</h2><p>Incident: @{triggerOutputs()?[\'queries\']?[\'incidentId\']}</p><p>判定: @{coalesce(triggerOutputs()?[\'queries\']?[\'decision\'], \'candidate\')}</p><p>営業 WorkPackage: <b>@{body(\'Call_handoff_workflow\')?[\'workPackageId\']}</b></p><p>営業担当へ Teams 通知を送信しました。Cowork では、この WorkPackage を起点に顧客影響会議・説明資料・初報メール案を準備できます（送信・会議作成は承認後）。</p><p>このタブを閉じて Teams に戻ってください。</p></body></html>'
          }
          runAfter: {
            Call_handoff_workflow: [
              'Succeeded'
            ]
          }
        }
      }
    }
  }
}

output ingressWorkflowName string = ingressWorkflow.name
output ingressPrincipalId string = ingressWorkflow.identity.principalId
output handoffWorkflowName string = handoffWorkflow.name
output handoffPrincipalId string = handoffWorkflow.identity.principalId
output handoffLinkWorkflowName string = handoffLinkWorkflow.name
output teamsConnectionName string = teamsConnection.name

