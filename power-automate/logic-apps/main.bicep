@description('Logic App workflow name.')
param workflowName string = 'la-mq-incident-ingress'

@description('Logic App workflow name for factory decision to sales handoff.')
param handoffWorkflowName string = 'la-mq-factory-decision-handoff'

@description('Azure region for the Logic App Consumption workflow and API connection.')
param location string = resourceGroup().location

@description('SharePoint site URL that contains MQ_StakeholderRouting, MQ_QualityIncidents, and MQ_WorkPackages.')
param siteUrl string

@description('Stakeholder routing list display name.')
param routingListName string = 'MQ_StakeholderRouting'

@description('Quality incidents list display name.')
param incidentListName string = 'MQ_QualityIncidents'

@description('Work packages list display name.')
param workPackageListName string = 'MQ_WorkPackages'

resource sharePointConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'conn-sharepoint-mq-demo'
  location: location
  properties: {
    displayName: 'SharePoint - Manufacturing Quality Demo'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'sharepointonline')
    }
  }
}

resource workflow 'Microsoft.Logic/workflows@2019-05-01' = {
  name: workflowName
  location: location
  properties: {
    state: 'Enabled'
    parameters: {
      '$connections': {
        value: {
          sharepointonline: {
            connectionId: sharePointConnection.id
            connectionName: sharePointConnection.name
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'sharepointonline')
          }
        }
      }
      siteUrl: {
        value: siteUrl
      }
      routingListName: {
        value: routingListName
      }
      incidentListName: {
        value: incidentListName
      }
      workPackageListName: {
        value: workPackageListName
      }
    }
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          type: 'Object'
        }
        siteUrl: {
          type: 'String'
        }
        routingListName: {
          type: 'String'
        }
        incidentListName: {
          type: 'String'
        }
        workPackageListName: {
          type: 'String'
        }
      }
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
        Get_factory_owner: {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'sharepointonline\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/datasets/@{encodeURIComponent(encodeURIComponent(parameters(\'siteUrl\')))}/tables/@{encodeURIComponent(encodeURIComponent(parameters(\'routingListName\')))}/items'
            queries: {
              '$filter': 'role_code eq \'factory_quality_owner\' and plant_id eq \'@{triggerBody()?[\'plantId\']}\' and line_id eq \'@{triggerBody()?[\'lineId\']}\''
            }
          }
          runAfter: {}
        }
        Get_fallback_owner: {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'sharepointonline\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/datasets/@{encodeURIComponent(encodeURIComponent(parameters(\'siteUrl\')))}/tables/@{encodeURIComponent(encodeURIComponent(parameters(\'routingListName\')))}/items'
            queries: {
              '$filter': 'role_code eq \'global_fallback\''
            }
          }
          runAfter: {
            Get_factory_owner: [
              'Succeeded'
            ]
          }
        }
        Compose_incident_id: {
          type: 'Compose'
          inputs: '@{concat(\'QI-\', formatDateTime(utcNow(), \'yyyyMMdd-HHmmss\'))}'
          runAfter: {
            Get_fallback_owner: [
              'Succeeded'
            ]
          }
        }
        Compose_owner_upn: {
          type: 'Compose'
          inputs: '@{if(greater(length(body(\'Get_factory_owner\')?[\'value\']), 0), first(body(\'Get_factory_owner\')?[\'value\'])?[\'user_upn\'], first(body(\'Get_fallback_owner\')?[\'value\'])?[\'user_upn\'])}'
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
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'sharepointonline\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/datasets/@{encodeURIComponent(encodeURIComponent(parameters(\'siteUrl\')))}/tables/@{encodeURIComponent(encodeURIComponent(parameters(\'incidentListName\')))}/items'
            body: {
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
          runAfter: {
            Compose_work_package_id: [
              'Succeeded'
            ]
          }
        }
        Create_factory_work_package: {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'sharepointonline\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/datasets/@{encodeURIComponent(encodeURIComponent(parameters(\'siteUrl\')))}/tables/@{encodeURIComponent(encodeURIComponent(parameters(\'workPackageListName\')))}/items'
            body: {
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
          runAfter: {
            Create_incident: [
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
              resolvedOwnerUpn: '@{outputs(\'Compose_owner_upn\')}'
              routeUsed: '@{if(greater(length(body(\'Get_factory_owner\')?[\'value\']), 0), \'factory_quality_owner\', \'global_fallback\')}'
              incidentList: '@{parameters(\'incidentListName\')}'
              workPackageList: '@{parameters(\'workPackageListName\')}'
              message: 'Incident and factory work package created. Notify owner manually or add Teams connector/webhook.'
            }
          }
          runAfter: {
            Create_factory_work_package: [
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
  properties: {
    state: 'Enabled'
    parameters: {
      '$connections': {
        value: {
          sharepointonline: {
            connectionId: sharePointConnection.id
            connectionName: sharePointConnection.name
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'sharepointonline')
          }
        }
      }
      siteUrl: {
        value: siteUrl
      }
      routingListName: {
        value: routingListName
      }
      incidentListName: {
        value: incidentListName
      }
      workPackageListName: {
        value: workPackageListName
      }
    }
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          type: 'Object'
        }
        siteUrl: {
          type: 'String'
        }
        routingListName: {
          type: 'String'
        }
        incidentListName: {
          type: 'String'
        }
        workPackageListName: {
          type: 'String'
        }
      }
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
        Get_sales_owner: {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'sharepointonline\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/datasets/@{encodeURIComponent(encodeURIComponent(parameters(\'siteUrl\')))}/tables/@{encodeURIComponent(encodeURIComponent(parameters(\'routingListName\')))}/items'
            queries: {
              '$filter': 'role_code eq \'sales_owner\' and customer_name eq \'@{triggerBody()?[\'customerName\']}\' and product_number eq \'@{triggerBody()?[\'productNumber\']}\''
            }
          }
          runAfter: {}
        }
        Get_fallback_owner: {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'sharepointonline\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/datasets/@{encodeURIComponent(encodeURIComponent(parameters(\'siteUrl\')))}/tables/@{encodeURIComponent(encodeURIComponent(parameters(\'routingListName\')))}/items'
            queries: {
              '$filter': 'role_code eq \'global_fallback\''
            }
          }
          runAfter: {
            Get_sales_owner: [
              'Succeeded'
            ]
          }
        }
        Get_incident: {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'sharepointonline\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/datasets/@{encodeURIComponent(encodeURIComponent(parameters(\'siteUrl\')))}/tables/@{encodeURIComponent(encodeURIComponent(parameters(\'incidentListName\')))}/items'
            queries: {
              '$filter': 'incident_id eq \'@{triggerBody()?[\'incidentId\']}\''
            }
          }
          runAfter: {
            Get_fallback_owner: [
              'Succeeded'
            ]
          }
        }
        Compose_owner_upn: {
          type: 'Compose'
          inputs: '@{if(greater(length(body(\'Get_sales_owner\')?[\'value\']), 0), first(body(\'Get_sales_owner\')?[\'value\'])?[\'user_upn\'], first(body(\'Get_fallback_owner\')?[\'value\'])?[\'user_upn\'])}'
          runAfter: {
            Get_incident: [
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
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'sharepointonline\'][\'connectionId\']'
              }
            }
            method: 'patch'
            path: '/datasets/@{encodeURIComponent(encodeURIComponent(parameters(\'siteUrl\')))}/tables/@{encodeURIComponent(encodeURIComponent(parameters(\'incidentListName\')))}/items/@{encodeURIComponent(first(body(\'Get_incident\')?[\'value\'])?[\'ID\'])}'
            body: {
              factory_decision: '@{triggerBody()?[\'decision\']}'
              decision_time: '@{utcNow()}'
              factory_responder_upn: '@{outputs(\'Compose_owner_upn\')}'
            }
          }
          runAfter: {
            Compose_work_package_id: [
              'Succeeded'
            ]
          }
        }
        Create_sales_work_package: {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'sharepointonline\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/datasets/@{encodeURIComponent(encodeURIComponent(parameters(\'siteUrl\')))}/tables/@{encodeURIComponent(encodeURIComponent(parameters(\'workPackageListName\')))}/items'
            body: {
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
          runAfter: {
            Update_incident: [
              'Succeeded'
              'Skipped'
              'Failed'
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
              resolvedOwnerUpn: '@{outputs(\'Compose_owner_upn\')}'
              routeUsed: '@{if(greater(length(body(\'Get_sales_owner\')?[\'value\']), 0), \'sales_owner\', \'global_fallback\')}'
              workPackageId: '@{outputs(\'Compose_work_package_id\')}'
              message: 'Sales work package created. Notify owner manually or add Teams connector/webhook.'
            }
          }
          runAfter: {
            Create_sales_work_package: [
              'Succeeded'
            ]
          }
        }
      }
    }
  }
}

output workflowName string = workflow.name
output handoffWorkflowName string = handoffWorkflow.name
output sharePointConnectionName string = sharePointConnection.name
