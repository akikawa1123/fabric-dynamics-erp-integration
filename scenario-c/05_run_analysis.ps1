# フェーズ3 実行: 品質異常検知 × ERP 複合分析クエリを実行
# 前提: 01〜04 実行済み、Python sender で Telemetry にデータ投入中（または投入済み）
. "$PSScriptRoot\kql_common.ps1"

function Show-Section($title, $csl) {
    Write-Host ""
    Write-Host "==================================================================="
    Write-Host " $title"
    Write-Host "==================================================================="
    try {
        Invoke-Kql -Csl $csl -Query | Format-Table -AutoSize
    }
    catch {
        Write-Host "  エラー: $($_.Exception.Message)"
    }
}

# [1] 直近5分の品質異常検知（不良率ベース）
Show-Section "[1] 品質異常検知 (lot 単位 不良率 > 20%)" @"
Telemetry
| where event_time > ago(5m)
| summarize fails = countif(status == 'fail'), total = count(),
            avg_torque = round(avg(torque_nm),2), max_torque = round(max(torque_nm),2)
        by product_number, lot_id, station_id
| extend defect_rate = round(todouble(fails) / total, 3)
| where total > 5 and defect_rate > 0.2
| order by defect_rate desc
"@

# [2] トルク上限超過イベント（最新20件）
Show-Section "[2] トルク上限(50.0Nm)超過イベント 最新20件" @"
Telemetry
| where event_time > ago(15m)
| where torque_nm > 50.0
| project event_time, station_id, product_number, lot_id, torque_nm, status
| order by event_time desc
| take 20
"@

# [3] 異常製品 × 進行中出荷オーダー（出荷保留の判断材料）
Show-Section "[3] 異常製品 × ERP 進行中出荷オーダー" @"
let anomaly_products =
    Telemetry
    | where event_time > ago(15m)
    | summarize fails = countif(status == 'fail'), total = count() by product_number
    | where total > 5 and todouble(fails) / total > 0.2
    | project product_number;
let product_bridge =
    external_table('ERP_ReturnOrderDetail')
    | summarize by msdyn_productnumber, msdyn_productid, msdyn_productidname;
anomaly_products
| join kind=inner product_bridge on `$left.product_number == `$right.msdyn_productnumber
| join kind=inner (external_table('ERP_FulfillmentOrderDetail')) on `$left.msdyn_productid == `$right.msdyn_product
| join kind=inner (external_table('ERP_FulfillmentOrder')) on `$left.msdyn_fulfillmentid == `$right.msdyn_fulfillmentorderid
| where msdyn_iomstatename !in ('Shipped', 'Cancelled', 'Closed')
| project product_number, product = msdyn_productidname,
          fulfillment_order = msdyn_name, status = msdyn_iomstatename,
          customer = msdyn_customername, planned_ship = msdyn_plannedshipmentdate,
          ship_to_country = msdyn_shiptocountry
| order by planned_ship asc
"@

# [4] 異常製品 × 返品履歴（過去の品質問題の文脈）
Show-Section "[4] 異常製品 × ERP 返品履歴" @"
let anomaly_products =
    Telemetry
    | where event_time > ago(15m)
    | summarize fails = countif(status == 'fail'), total = count() by product_number
    | where total > 5 and todouble(fails) / total > 0.2
    | project product_number;
anomaly_products
| join kind=inner (external_table('ERP_ReturnOrderDetail')) on `$left.product_number == `$right.msdyn_productnumber
| summarize return_lines = count(), lots = make_set(msdyn_returninginventorylotid, 10)
        by product_number, product = msdyn_productidname
| order by return_lines desc
"@

Write-Host ""
Write-Host "完了。異常が出ない場合は Python sender を --normal-seconds 短め + 異常フェーズ込みで実行してください。"
