from __future__ import annotations

import argparse
import json
from pathlib import Path

from manufacturing_quality_agent.models import (
    Assessment,
    InvestigationRequest,
    StakeholderRoutingRecord,
    WorkPackage,
)

ROOT = Path(__file__).resolve().parents[2]
TARGETS = {
    ROOT / "contracts" / "generated" / "investigation-request.schema.json": InvestigationRequest.model_json_schema(),
    ROOT / "contracts" / "generated" / "assessment.schema.json": Assessment.model_json_schema(),
    ROOT / "contracts" / "generated" / "stakeholder-routing.schema.json": StakeholderRoutingRecord.model_json_schema(),
    ROOT / "contracts" / "generated" / "work-package.schema.json": WorkPackage.model_json_schema(),
}


def serialize(value: dict) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    mismatches: list[Path] = []

    for path, schema in TARGETS.items():
        expected = serialize(schema)
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != expected:
                mismatches.append(path)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(expected, encoding="utf-8")

    if mismatches:
        raise SystemExit("Schema files are out of date:\n" + "\n".join(map(str, mismatches)))


if __name__ == "__main__":
    main()
