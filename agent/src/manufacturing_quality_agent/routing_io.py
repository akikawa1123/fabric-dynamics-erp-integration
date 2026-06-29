from __future__ import annotations

import csv
from pathlib import Path

from .models import StakeholderRoutingRecord


def load_routing_csv(path: Path) -> list[StakeholderRoutingRecord]:
    rows: list[StakeholderRoutingRecord] = []
    with path.open(encoding="utf-8-sig", newline="") as stream:
        for raw in csv.DictReader(stream):
            data = dict(raw)
            data["is_primary"] = str(data.get("is_primary", "")).casefold() == "true"
            data["active"] = str(data.get("active", "")).casefold() == "true"
            data["priority"] = int(data.get("priority") or 100)
            for key in ("plant_id", "line_id", "customer_name", "product_number"):
                data[key] = data.get(key) or None
            rows.append(StakeholderRoutingRecord.model_validate(data))
    return rows
