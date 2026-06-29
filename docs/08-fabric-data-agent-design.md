# Fabric Data Agent設計

## Data source

Eventhouse KQL Database `eh_manufacturing_rti`。

## 公開する問い合わせ面

- `fn_quality_anomaly_context`
- `fn_candidate_affected_orders`
- `fn_product_return_context`

生テーブルを自由に結合させるより、意味と安全境界が固定された関数を使う。

## 英語の固定質問

factory:

```text
Investigate the anomaly for product {product_number}, lot {lot_id},
station {station_id}, detected at {detected_at}.
Return confirmed measurements, counts, defect rate, candidate unshipped orders,
and historical return context. Never classify a product-level match as confirmed lot impact.
```

sales:

```text
For product {product_number}, return at most 10 candidate unshipped fulfillment orders
with customer, status, and planned shipment date. Include historical return context.
Treat every product-level order match as candidate unless lot allocation is explicitly verified.
```

## 権限

- End user: Foundry User
- Fabric Data Agent: READ
- KQL DB: Reader
- Foundry projectとFabricは同一tenant
- service principalではなくuser identity
