-- ============================================================
-- レイクハウス側 複合分析 (lh_quality_analytics の SQL エンドポイント)
--   Telemetry(Eventhouse OneLake) × ERP(OneLake ショートカット) を T-SQL で結合
--   ※ Eventhouse->OneLake のミラーリングには数十分の遅延あり。
--      そのため時間窓は広め(直近6時間)にしています。デモ前に送信を済ませておくと確実。
-- ============================================================

-- ------------------------------------------------------------
-- [1] 品質異常検知 (lot 単位 不良率 > 20%)
-- ------------------------------------------------------------
SELECT
    product_number,
    lot_id,
    station_id,
    SUM(CASE WHEN status = 'fail' THEN 1 ELSE 0 END) AS fails,
    COUNT(*)                                          AS total,
    ROUND(AVG(torque_nm), 2)                          AS avg_torque,
    ROUND(MAX(torque_nm), 2)                          AS max_torque,
    ROUND(CAST(SUM(CASE WHEN status = 'fail' THEN 1 ELSE 0 END) AS float) / COUNT(*), 3) AS defect_rate
FROM Telemetry
WHERE event_time > DATEADD(hour, -6, SYSUTCDATETIME())
GROUP BY product_number, lot_id, station_id
HAVING COUNT(*) > 5
   AND CAST(SUM(CASE WHEN status = 'fail' THEN 1 ELSE 0 END) AS float) / COUNT(*) > 0.2
ORDER BY defect_rate DESC;


-- ------------------------------------------------------------
-- [2] トルク上限(50.0Nm)超過イベント 最新20件
-- ------------------------------------------------------------
SELECT TOP (20)
    event_time, station_id, product_number, lot_id, torque_nm, status
FROM Telemetry
WHERE event_time > DATEADD(hour, -6, SYSUTCDATETIME())
  AND torque_nm > 50.0
ORDER BY event_time DESC;


-- ------------------------------------------------------------
-- [3] 異常製品 × ERP 進行中出荷オーダー (出荷保留の判断材料)
--     結合: Telemetry.product_number = ReturnOrderDetail.msdyn_productnumber (製品コード->製品GUID ブリッジ)
--           -> FulfillmentOrderDetail.msdyn_product (製品GUID)
--           -> FulfillmentOrder.msdyn_fulfillmentorderid
-- ------------------------------------------------------------
WITH anomaly_products AS (
    SELECT product_number
    FROM Telemetry
    WHERE event_time > DATEADD(hour, -6, SYSUTCDATETIME())
    GROUP BY product_number
    HAVING COUNT(*) > 5
       AND CAST(SUM(CASE WHEN status = 'fail' THEN 1 ELSE 0 END) AS float) / COUNT(*) > 0.2
),
product_bridge AS (
    SELECT DISTINCT msdyn_productnumber, msdyn_productid, msdyn_productidname
    FROM ERP_ReturnOrderDetail
)
SELECT
    ap.product_number,
    pb.msdyn_productidname        AS product,
    fo.msdyn_name                 AS fulfillment_order,
    fo.msdyn_iomstatename         AS status,
    fo.msdyn_customername         AS customer,
    fo.msdyn_plannedshipmentdate  AS planned_ship,
    fo.msdyn_shiptocountry        AS ship_to_country
FROM anomaly_products ap
JOIN product_bridge pb
      ON ap.product_number = pb.msdyn_productnumber
JOIN ERP_FulfillmentOrderDetail fod
      ON pb.msdyn_productid = fod.msdyn_product
JOIN ERP_FulfillmentOrder fo
      ON fod.msdyn_fulfillmentid = fo.msdyn_fulfillmentorderid
WHERE fo.msdyn_iomstatename NOT IN ('Shipped', 'Cancelled', 'Closed')
ORDER BY fo.msdyn_plannedshipmentdate ASC;


-- ------------------------------------------------------------
-- [4] 異常製品 × ERP 返品履歴 (過去の品質問題の文脈)
-- ------------------------------------------------------------
WITH anomaly_products AS (
    SELECT product_number
    FROM Telemetry
    WHERE event_time > DATEADD(hour, -6, SYSUTCDATETIME())
    GROUP BY product_number
    HAVING COUNT(*) > 5
       AND CAST(SUM(CASE WHEN status = 'fail' THEN 1 ELSE 0 END) AS float) / COUNT(*) > 0.2
)
SELECT
    rod.msdyn_productnumber           AS product_number,
    MAX(rod.msdyn_productidname)      AS product,
    COUNT(*)                          AS return_lines
FROM anomaly_products ap
JOIN ERP_ReturnOrderDetail rod
      ON ap.product_number = rod.msdyn_productnumber
GROUP BY rod.msdyn_productnumber
ORDER BY return_lines DESC;
