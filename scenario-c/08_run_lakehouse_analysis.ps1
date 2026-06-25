# フェーズ3(改) 実行: レイクハウス SQL エンドポイントで複合分析を実行 (05 の T-SQL 版)
# 前提: 07/09 実行済み。Telemetry は Eventstream の Lakehouse 宛先から直接書き込まれる(遅延約1分)。
# 認証: az のログインユーザーで SQL エンドポイントに AAD アクセストークン接続。
$ErrorActionPreference = 'Stop'

$info = Get-Content "$PSScriptRoot\lakehouse_info.json" -Raw | ConvertFrom-Json
$server   = $info.sqlConnectionString
$database = $info.lakehouseName

# SQL エンドポイント用 AAD トークン (Azure SQL リソース)
$token = az account get-access-token --resource https://database.windows.net --query accessToken -o tsv

function Invoke-SqlEndpoint($title, $sql) {
    Write-Host ""
    Write-Host "==================================================================="
    Write-Host " $title"
    Write-Host "==================================================================="
    $conn = New-Object System.Data.SqlClient.SqlConnection
    $conn.ConnectionString = "Server=$server;Database=$database;Encrypt=True;TrustServerCertificate=False;Connection Timeout=60;"
    $conn.AccessToken = $token
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $sql
        $cmd.CommandTimeout = 120
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
        $dt = New-Object System.Data.DataTable
        [void]$adapter.Fill($dt)
        if ($dt.Rows.Count -eq 0) { Write-Host "  (該当データなし)" }
        else { $dt | Format-Table -AutoSize }
    }
    catch {
        Write-Host "  エラー: $($_.Exception.Message)"
    }
    finally {
        $conn.Close()
    }
}

# [1] 品質異常検知 (lot 単位 不良率 > 20%)
Invoke-SqlEndpoint "[1] 品質異常検知 (lot 単位 不良率 > 20%)" @"
SELECT product_number, lot_id, station_id,
       SUM(CASE WHEN status = 'fail' THEN 1 ELSE 0 END) AS fails,
       COUNT(*) AS total,
       ROUND(AVG(torque_nm), 2) AS avg_torque,
       ROUND(MAX(torque_nm), 2) AS max_torque,
       ROUND(CAST(SUM(CASE WHEN status = 'fail' THEN 1 ELSE 0 END) AS float) / COUNT(*), 3) AS defect_rate
FROM Telemetry
WHERE event_time > DATEADD(hour, -6, SYSUTCDATETIME())
GROUP BY product_number, lot_id, station_id
HAVING COUNT(*) > 5
   AND CAST(SUM(CASE WHEN status = 'fail' THEN 1 ELSE 0 END) AS float) / COUNT(*) > 0.2
ORDER BY defect_rate DESC;
"@

# [2] トルク上限(50.0Nm)超過イベント 最新20件
Invoke-SqlEndpoint "[2] トルク上限(50.0Nm)超過イベント 最新20件" @"
SELECT TOP (20) event_time, station_id, product_number, lot_id, torque_nm, status
FROM Telemetry
WHERE event_time > DATEADD(hour, -6, SYSUTCDATETIME()) AND torque_nm > 50.0
ORDER BY event_time DESC;
"@

# [3] 異常製品 × ERP 進行中出荷オーダー
Invoke-SqlEndpoint "[3] 異常製品 × ERP 進行中出荷オーダー" @"
WITH anomaly_products AS (
    SELECT product_number FROM Telemetry
    WHERE event_time > DATEADD(hour, -6, SYSUTCDATETIME())
    GROUP BY product_number
    HAVING COUNT(*) > 5
       AND CAST(SUM(CASE WHEN status = 'fail' THEN 1 ELSE 0 END) AS float) / COUNT(*) > 0.2
),
product_bridge AS (
    SELECT DISTINCT msdyn_productnumber, msdyn_productid, msdyn_productidname
    FROM ERP_ReturnOrderDetail
)
SELECT ap.product_number, pb.msdyn_productidname AS product,
       fo.msdyn_name AS fulfillment_order, fo.msdyn_iomstatename AS status,
       fo.msdyn_customername AS customer, fo.msdyn_plannedshipmentdate AS planned_ship,
       fo.msdyn_shiptocountry AS ship_to_country
FROM anomaly_products ap
JOIN product_bridge pb ON ap.product_number = pb.msdyn_productnumber
JOIN ERP_FulfillmentOrderDetail fod ON pb.msdyn_productid = fod.msdyn_product
JOIN ERP_FulfillmentOrder fo ON fod.msdyn_fulfillmentid = fo.msdyn_fulfillmentorderid
WHERE fo.msdyn_iomstatename NOT IN ('Shipped', 'Cancelled', 'Closed')
ORDER BY fo.msdyn_plannedshipmentdate ASC;
"@

# [4] 異常製品 × ERP 返品履歴
Invoke-SqlEndpoint "[4] 異常製品 × ERP 返品履歴" @"
WITH anomaly_products AS (
    SELECT product_number FROM Telemetry
    WHERE event_time > DATEADD(hour, -6, SYSUTCDATETIME())
    GROUP BY product_number
    HAVING COUNT(*) > 5
       AND CAST(SUM(CASE WHEN status = 'fail' THEN 1 ELSE 0 END) AS float) / COUNT(*) > 0.2
)
SELECT rod.msdyn_productnumber AS product_number,
       MAX(rod.msdyn_productidname) AS product,
       COUNT(*) AS return_lines
FROM anomaly_products ap
JOIN ERP_ReturnOrderDetail rod ON ap.product_number = rod.msdyn_productnumber
GROUP BY rod.msdyn_productnumber
ORDER BY return_lines DESC;
"@

Write-Host ""
Write-Host "完了。Telemetry が空の場合は telemetry_sender --mode eventstream を未送信か、Lakehouse 宛先反映待ち(約1分)。"
