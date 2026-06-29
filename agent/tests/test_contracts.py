import json
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]


def test_investigation_request_matches_generated_schema() -> None:
    schema = json.loads(
        (ROOT / "contracts" / "generated" / "investigation-request.schema.json").read_text(
            encoding="utf-8"
        )
    )
    payload = json.loads(
        (ROOT / "contracts" / "samples" / "investigation-request.json").read_text(
            encoding="utf-8"
        )
    )
    Draft202012Validator(schema).validate(payload)
