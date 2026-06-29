from pathlib import Path

from manufacturing_quality_agent.models import RoleCode, RoutingContext
from manufacturing_quality_agent.routing import resolve_stakeholder
from manufacturing_quality_agent.routing_io import load_routing_csv

ROOT = Path(__file__).resolve().parents[2]


def records():
    return load_routing_csv(ROOT / "routing" / "stakeholder-routing.sample.csv")


def test_exact_customer_product_sales_owner_wins() -> None:
    resolved = resolve_stakeholder(
        records(),
        RoleCode.SALES_OWNER,
        RoutingContext(customer_name="Contoso", product_number="CRCA"),
    )
    assert resolved is not None
    assert resolved.user_upn == "sales.owner@example.com"
    assert resolved.routing_id == "R-006"


def test_factory_plant_line_owner() -> None:
    resolved = resolve_stakeholder(
        records(),
        RoleCode.FACTORY_QUALITY_OWNER,
        RoutingContext(plant_id="JP-NAGOYA-01", line_id="LINE-A"),
    )
    assert resolved is not None
    assert resolved.routing_id == "R-001"


def test_global_fallback_is_used() -> None:
    resolved = resolve_stakeholder(
        records(),
        RoleCode.SALES_OWNER,
        RoutingContext(customer_name="Unknown", product_number="UNKNOWN"),
    )
    assert resolved is not None
    assert resolved.user_upn == "quality.operations@example.com"
