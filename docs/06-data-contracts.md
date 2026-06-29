# データ契約

## InvestigationRequest

Agentへincident_idだけを渡さず、Fabric検索に必要な文脈も渡す。

```text
incident_id
detected_at
plant_id
line_id
station_id
product_number
lot_id
anomaly
```

## Assessment

```text
confirmed_facts
affected_orders
document_evidence
hypotheses
recommended_actions
open_questions
warnings
tool_status
```

## WorkPackage

```text
persona
assignee_upn
required_attendees
meeting
artifacts
assessment_uri
safety_notes
```

## 顧客影響

```text
confirmed: 対象ロット引当を確認
candidate: 製品一致、ロット未確認
not_affected: 非影響を確認
```
