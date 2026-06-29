from __future__ import annotations

import argparse
import json
from pathlib import Path

from .fixture_service import build_fixture_assessment, build_tool_failure_assessment
from .models import InvestigationRequest, Persona
from .rendering import render_assessment


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("persona", choices=["factory", "sales"])
    parser.add_argument("request_path", type=Path)
    parser.add_argument("--json", action="store_true")
    parser.add_argument(
        "--tool-failure",
        action="store_true",
        help="ツール失敗時（捏造せず warnings を返す）の fixture を表示する",
    )
    args = parser.parse_args()

    payload = json.loads(args.request_path.read_text(encoding="utf-8"))
    request = InvestigationRequest.model_validate(payload)
    builder = build_tool_failure_assessment if args.tool_failure else build_fixture_assessment
    assessment = builder(request, Persona(args.persona))
    print(assessment.model_dump_json(indent=2) if args.json else render_assessment(assessment))


if __name__ == "__main__":
    main()
