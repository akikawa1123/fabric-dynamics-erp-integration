from __future__ import annotations

import argparse
import json
from pathlib import Path

from .models import RoleCode, RoutingContext
from .routing import resolve_stakeholder
from .routing_io import load_routing_csv


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("routing_csv", type=Path)
    parser.add_argument("context_json", type=Path)
    parser.add_argument("role_code", choices=[item.value for item in RoleCode])
    args = parser.parse_args()

    records = load_routing_csv(args.routing_csv)
    context = RoutingContext.model_validate_json(
        args.context_json.read_text(encoding="utf-8")
    )
    resolved = resolve_stakeholder(records, RoleCode(args.role_code), context)
    if resolved is None:
        raise SystemExit("No stakeholder or global fallback was found.")
    print(resolved.model_dump_json(indent=2))


if __name__ == "__main__":
    main()
