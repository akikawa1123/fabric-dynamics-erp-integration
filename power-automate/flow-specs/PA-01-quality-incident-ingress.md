# PA-01 Quality Incident Ingress

Trigger: Fabric Activator custom action

Inputs:
- activationTime
- plantId
- lineId
- stationId
- productNumber
- lotId
- metricName
- observedValue
- thresholdValue
- unit
- dashboardUrl

Actions:
1. `QI-yyyyMMdd-###`を生成
2. QualityIncidentsへ保存
3. StakeholderRoutingでfactory_quality_ownerを解決
4. factory-alert Adaptive Cardを送信
5. 解決できない場合はglobal_fallbackへ通知
