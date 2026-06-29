import json
from pathlib import Path

from manufacturing_quality_agent.fixture_service import build_fixture_assessment
from manufacturing_quality_agent.models import ImpactClassification, InvestigationRequest, Persona

ROOT = Path(__file__).resolve().parents[2]


def load_request() -> InvestigationRequest:
    return InvestigationRequest.model_validate_json(
        (ROOT / "contracts" / "samples" / "investigation-request.json").read_text(
            encoding="utf-8"
        )
    )


def test_request_sample_is_valid() -> None:
    request = load_request()
    assert request.product_number == "CRCA"
    assert request.lot_id == "LOT-CRCA-20260625-001"


def test_product_level_order_is_candidate() -> None:
    assessment = build_fixture_assessment(load_request(), Persona.FACTORY)
    assert assessment.affected_orders
    assert assessment.affected_orders[0].impact_classification is ImpactClassification.CANDIDATE


def test_hypothesis_is_unverified() -> None:
    assessment = build_fixture_assessment(load_request(), Persona.FACTORY)
    assert assessment.hypotheses
    assert all(item.status == "unverified" for item in assessment.hypotheses)
