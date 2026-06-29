from __future__ import annotations

from collections.abc import Iterable

from .models import (
    ResolvedStakeholder,
    RoleCode,
    RoutingContext,
    StakeholderRoutingRecord,
)


_FIELDS = ("plant_id", "line_id", "customer_name", "product_number")


def _normalized(value: str | None) -> str | None:
    if value is None:
        return None
    result = value.strip().casefold()
    return result or None


def _matches(record: StakeholderRoutingRecord, context: RoutingContext) -> bool:
    for field in _FIELDS:
        expected = _normalized(getattr(record, field))
        actual = _normalized(getattr(context, field))
        if expected is not None and expected != actual:
            return False
    return True


def _specificity(record: StakeholderRoutingRecord) -> int:
    return sum(_normalized(getattr(record, field)) is not None for field in _FIELDS)


def resolve_stakeholder(
    records: Iterable[StakeholderRoutingRecord],
    role_code: RoleCode,
    context: RoutingContext,
) -> ResolvedStakeholder | None:
    candidates = [
        record
        for record in records
        if record.active and record.role_code is role_code and _matches(record, context)
    ]
    if not candidates and role_code is not RoleCode.GLOBAL_FALLBACK:
        return resolve_stakeholder(records, RoleCode.GLOBAL_FALLBACK, context)
    if not candidates:
        return None

    selected = sorted(
        candidates,
        key=lambda item: (
            -_specificity(item),
            not item.is_primary,
            item.priority,
            item.routing_id,
        ),
    )[0]
    return ResolvedStakeholder(
        role_code=role_code,
        user_upn=selected.user_upn,
        routing_id=selected.routing_id,
        resolution_reason=(
            f"specificity={_specificity(selected)}, primary={selected.is_primary}, "
            f"priority={selected.priority}"
        ),
    )
