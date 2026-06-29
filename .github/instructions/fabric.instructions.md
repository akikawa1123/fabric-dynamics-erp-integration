---
applyTo: "scenario-c/**/*.py,scenario-c/**/*.ps1,scenario-c/**/*.kql,scenario-c/**/*.sql,fabric-data-agent/**"
---

- 既存Fabricリソース名とスクリプト番号を維持する。
- KQLは対象期間を限定する。
- 異常文脈は`station_id + product_number + lot_id + detected_at`で識別する。
- `take_any(product_number)`だけでインシデント文脈を決定しない。
- 製品単位の受注突合結果は`candidate`として返す。
- Data Agent向け関数は読み取り専用にする。
- Data Agentの指示と例示クエリは英語で記述する。
