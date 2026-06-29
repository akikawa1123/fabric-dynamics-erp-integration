from pathlib import Path

from manufacturing_quality_agent import fixture_cli
from manufacturing_quality_agent.fixture_service import (
    build_fixture_assessment,
    build_tool_failure_assessment,
)
from manufacturing_quality_agent.models import (
    EvidenceSource,
    InvestigationRequest,
    Persona,
    RoleCode,
    ToolState,
)

# 注: no-document / prompt-injection は実エージェント挙動の評価（evals/cases.jsonl の
# live eval）で扱う。ここではネットワーク非接続で検証できる構造的契約のみをテストする。

ROOT = Path(__file__).resolve().parents[2]
REQUEST_PATH = ROOT / "contracts" / "samples" / "investigation-request.json"
ROLE_CODES = {code.value for code in RoleCode}


def load_request() -> InvestigationRequest:
    return InvestigationRequest.model_validate_json(REQUEST_PATH.read_text(encoding="utf-8"))


def test_tool_failure_returns_warnings_without_fabrication() -> None:
    assessment = build_tool_failure_assessment(load_request(), Persona.FACTORY)
    assert assessment.tool_status
    assert all(status.state is ToolState.FAILED for status in assessment.tool_status)
    # ツール失敗時は注文・文書・仮説を捏造しない。
    assert assessment.affected_orders == []
    assert assessment.document_evidence == []
    assert assessment.hypotheses == []
    # 事実はインシデント由来の1件のみ（Fabric由来の測定値を捏造しない）。
    assert len(assessment.confirmed_facts) == 1
    assert assessment.confirmed_facts[0].source_type is EvidenceSource.INCIDENT_EVENT
    # 警告は「失敗」と「補完していない」を明示する。
    assert any("失敗" in w and "補完していない" in w for w in assessment.warnings)
    assert assessment.open_questions


def test_recommended_actions_use_deterministic_role_codes() -> None:
    for persona in (Persona.FACTORY, Persona.SALES):
        for builder in (build_fixture_assessment, build_tool_failure_assessment):
            assessment = builder(load_request(), persona)
            for action in assessment.recommended_actions:
                assert action.owner_role in ROLE_CODES, action.owner_role
                assert "@" not in action.owner_role
                assert action.priority >= 1


def test_sales_fixture_candidate_and_requires_human_approval() -> None:
    assessment = build_fixture_assessment(load_request(), Persona.SALES)
    assert any(
        order.impact_classification.value == "candidate"
        for order in assessment.affected_orders
    )
    assert any(action.requires_human_approval for action in assessment.recommended_actions)


def test_cli_tool_failure_dispatch(capsys, monkeypatch) -> None:
    monkeypatch.setattr(
        "sys.argv",
        ["mq-agent-fixture", "factory", str(REQUEST_PATH), "--tool-failure"],
    )
    fixture_cli.main()
    out = capsys.readouterr().out
    assert "確認できた販売注文はありません" in out
    assert "取得できた文書はありません" in out
