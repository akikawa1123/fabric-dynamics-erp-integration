from __future__ import annotations

from .models import (
    AffectedOrder,
    Assessment,
    DocumentEvidence,
    EvidenceSource,
    Fact,
    Hypothesis,
    ImpactClassification,
    InvestigationRequest,
    Persona,
    RecommendedAction,
    ToolExecutionStatus,
    ToolName,
    ToolState,
)


def build_fixture_assessment(
    request: InvestigationRequest,
    persona: Persona,
) -> Assessment:
    facts = [
        Fact(
            id="F-001",
            statement=(
                f"{request.station_id}で{request.anomaly.metric_name}が"
                f"{request.anomaly.threshold_value}{request.anomaly.unit}を超過した。"
            ),
            source_type=EvidenceSource.INCIDENT_EVENT,
            source_id=request.incident_id,
            observed_at=request.detected_at,
        ),
        Fact(
            id="F-002",
            statement=(
                f"対象製品は{request.product_number}、対象ロットは{request.lot_id}である。"
            ),
            source_type=EvidenceSource.FABRIC,
            source_id="fn_quality_anomaly_context",
        ),
    ]
    orders = [
        AffectedOrder(
            sales_order_id="FO-DEMO-001",
            customer_name="Contoso",
            product_number=request.product_number,
            impact_classification=ImpactClassification.CANDIDATE,
            reason="製品番号は一致するが、販売注文へのロット引当は未確認。",
        )
    ]
    documents = [
        DocumentEvidence(
            id="D-001",
            summary="過去の圧入工程異常では、センサー校正状態の確認が初動に含まれていた。",
            document_id="8D-DEMO-001",
            document_title="圧入工程におけるトルク上限超過",
        )
    ]
    tool_status = [
        ToolExecutionStatus(tool=ToolName.FABRIC, state=ToolState.SUCCEEDED),
        ToolExecutionStatus(tool=ToolName.FOUNDRY_IQ, state=ToolState.SUCCEEDED),
    ]

    if persona is Persona.FACTORY:
        return Assessment(
            incident_id=request.incident_id,
            persona=persona,
            confirmed_facts=facts,
            affected_orders=orders,
            document_evidence=documents,
            hypotheses=[
                Hypothesis(
                    id="H-001",
                    statement="圧入工程の設定または校正状態に問題がある可能性がある。",
                    confidence="medium",
                    supporting_evidence_ids=["F-001", "D-001"],
                )
            ],
            recommended_actions=[
                RecommendedAction(
                    priority=1,
                    action="対象ロットを隔離し、圧入工程の校正状態を確認する。",
                    owner_role="factory_quality_owner",
                ),
                RecommendedAction(
                    priority=2,
                    action="同一製品の未出荷注文を営業へ影響候補として共有する。",
                    owner_role="production_planner",
                ),
            ],
            open_questions=["対象ロットと販売注文の引当関係を確認できるか。"],
            warnings=["販売注文への影響は製品レベルの候補であり、確定ではない。"],
            tool_status=tool_status,
        )

    return Assessment(
        incident_id=request.incident_id,
        persona=persona,
        confirmed_facts=facts,
        affected_orders=orders,
        document_evidence=documents,
        recommended_actions=[
            RecommendedAction(
                priority=1,
                action="工場品質・生産計画・物流との顧客影響確認会議を準備する。",
                owner_role="sales_owner",
            ),
            RecommendedAction(
                priority=2,
                action="顧客向け初報は影響確定後に送信する。",
                owner_role="sales_owner",
            ),
        ],
        open_questions=["予定出荷日までに再検査が完了するか。"],
        warnings=["顧客への通知前に工場責任者の判定が必要。"],
        tool_status=tool_status,
    )


def build_tool_failure_assessment(
    request: InvestigationRequest,
    persona: Persona,
) -> Assessment:
    """ツール失敗時の決定論的 Assessment。

    Fabric / Foundry IQ が失敗した場合に、取得できなかった事実・注文・文書を捏造せず、
    warnings と open_questions を返す契約を示す（AGENTS.md: ツール失敗時に値を補完しない）。
    """
    facts = [
        Fact(
            id="F-001",
            statement=(
                f"{request.station_id}で{request.anomaly.metric_name}が"
                f"{request.anomaly.threshold_value}{request.anomaly.unit}を超過した。"
            ),
            source_type=EvidenceSource.INCIDENT_EVENT,
            source_id=request.incident_id,
            observed_at=request.detected_at,
        )
    ]
    tool_status = [
        ToolExecutionStatus(
            tool=ToolName.FABRIC,
            state=ToolState.FAILED,
            detail="Fabric Data Agent の呼び出しに失敗した。",
        ),
        ToolExecutionStatus(
            tool=ToolName.FOUNDRY_IQ,
            state=ToolState.FAILED,
            detail="Foundry IQ の検索に失敗した。",
        ),
    ]
    owner_role = "factory_quality_owner" if persona is Persona.FACTORY else "sales_owner"
    return Assessment(
        incident_id=request.incident_id,
        persona=persona,
        confirmed_facts=facts,
        affected_orders=[],
        document_evidence=[],
        hypotheses=[],
        recommended_actions=[
            RecommendedAction(
                priority=1,
                action="Fabric Data Agent と Foundry IQ の接続を確認し、調査を再試行する。",
                owner_role=owner_role,
            )
        ],
        open_questions=[
            "Fabricの異常・受注・返品文脈を取得できていない。",
            "Foundry IQの過去文書を取得できていない。",
        ],
        warnings=[
            "ツール呼び出しに失敗したため、影響注文・測定値・文書根拠は取得できていない。"
            "未取得の値を補完していない。",
        ],
        tool_status=tool_status,
    )
