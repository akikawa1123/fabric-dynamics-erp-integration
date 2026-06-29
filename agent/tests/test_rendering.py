from pathlib import Path

from manufacturing_quality_agent.fixture_service import build_fixture_assessment
from manufacturing_quality_agent.models import InvestigationRequest, Persona
from manufacturing_quality_agent.rendering import render_assessment

ROOT = Path(__file__).resolve().parents[2]


def test_rendering_contains_grounding_boundaries() -> None:
    request = InvestigationRequest.model_validate_json(
        (ROOT / "contracts" / "samples" / "investigation-request.json").read_text(
            encoding="utf-8"
        )
    )
    rendered = render_assessment(build_fixture_assessment(request, Persona.FACTORY))
    assert "確認済み事実" in rendered
    assert "原因仮説" in rendered
    assert "unverified" in rendered
    assert "製品レベルの候補" in rendered
    assert "8D-DEMO-001" in rendered
