from __future__ import annotations

from .models import Assessment


def render_assessment(assessment: Assessment) -> str:
    lines = [
        f"# 品質インシデント {assessment.incident_id}",
        "",
        "## 確認済み事実",
    ]
    lines.extend(f"- {item.statement}" for item in assessment.confirmed_facts)

    lines.extend(["", "## 影響する販売注文"])
    if assessment.affected_orders:
        for order in assessment.affected_orders:
            lines.append(
                f"- {order.sales_order_id} / {order.customer_name} / "
                f"{order.impact_classification.value}: {order.reason}"
            )
    else:
        lines.append("- 確認できた販売注文はありません。")

    lines.extend(["", "## 過去文書の根拠"])
    if assessment.document_evidence:
        for item in assessment.document_evidence:
            lines.append(f"- {item.document_title}（{item.document_id}）: {item.summary}")
    else:
        lines.append("- 取得できた文書はありません。")

    lines.extend(["", "## 原因仮説"])
    if assessment.hypotheses:
        for item in assessment.hypotheses:
            lines.append(f"- [{item.confidence}, {item.status}] {item.statement}")
    else:
        lines.append("- 現時点で原因仮説は作成していません。")

    lines.extend(["", "## 推奨アクション"])
    for item in sorted(assessment.recommended_actions, key=lambda value: value.priority):
        approval = "人の承認が必要" if item.requires_human_approval else "承認不要"
        lines.append(
            f"{item.priority}. {item.action}（担当役割: {item.owner_role}、{approval}）"
        )

    lines.extend(["", "## 未確認事項"])
    lines.extend(f"- {item}" for item in assessment.open_questions)

    lines.extend(["", "## 警告"])
    lines.extend(f"- {item}" for item in assessment.warnings)

    return "\n".join(lines)
