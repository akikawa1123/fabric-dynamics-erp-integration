# Copyright (c) Microsoft. All rights reserved.
#
# Adapted from the official Microsoft Foundry sample
# ``samples/python/hosted-agents/agent-framework/responses/17-foundry-iq-toolbox/provision_kb.py``
# (github.com/microsoft-foundry/foundry-samples). The official structure (search
# index + semantic config, knowledge source, answer-synthesis knowledge base,
# keyless Azure OpenAI via the search managed identity) is preserved verbatim.
#
# The only adaptations for this repo (Task 006) are:
#   * DOCUMENTS is no longer hard-coded ("Earth at night"). Instead we load our
#     five Japanese quality documents from ``foundry-iq/documents/*.md`` and
#     carry each doc's 文書ID (as the index key) + タイトル + 出典 (source path)
#     so the knowledge base can cite 文書名・文書ID・出典 in answers.
#   * The index gains a retrievable ``source`` field and the knowledge source
#     exposes it via ``sourceDataFields`` for citation metadata.
#   * Default index/knowledge-source/knowledge-base names are mq-quality-*.

"""Provision the Foundry IQ knowledge base for the manufacturing-quality agent.

Runs once, before the agent is deployed. It creates (or updates) four things in
the Azure AI Search service:

  1. A search index (``mq-quality-index``) with a semantic configuration.
  2. Seed documents loaded from ``foundry-iq/documents/*.md`` (our quality
     corpus: 8D report, PFMEA, control plan, calibration SOP, QA agreement).
  3. A knowledge source over the index.
  4. A knowledge base that orchestrates the knowledge source and synthesizes
     answers with an Azure OpenAI model (gpt-5.4).

The knowledge base exposes an MCP endpoint
(``{search}/knowledgebases/{kb}/mcp``) with a single ``knowledge_base_retrieve``
tool. The hosted agent reaches that endpoint through a Foundry toolbox.

Usage (from the repo root or this directory, with az login done)::

    pip install requests azure-identity python-dotenv
    python foundry-iq/provision_kb.py

Required env vars (also read from a local ``.env`` file if present)::

    AZURE_SEARCH_ENDPOINT          e.g. https://<your-search>.search.windows.net
    AZURE_OPENAI_ENDPOINT          e.g. https://<account>.services.ai.azure.com
    AZURE_AI_MODEL_DEPLOYMENT_NAME e.g. gpt-5.4

Optional env vars (sensible defaults shown)::

    AZURE_SEARCH_INDEX_NAME    mq-quality-index
    KNOWLEDGE_SOURCE_NAME      mq-quality-ks
    KNOWLEDGE_BASE_NAME        mq-quality-kb
    AZURE_AI_MODEL_NAME        (defaults to AZURE_AI_MODEL_DEPLOYMENT_NAME)

Your identity needs ``Search Service Contributor`` (to create the index and the
knowledge source/base) and ``Search Index Data Contributor`` (to upload
documents) on the search service.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import requests
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

SEARCH_SCOPE = "https://search.azure.com/.default"
API_VERSION = "2026-05-01-preview"
SEMANTIC_CONFIG_NAME = "default-semantic-config"

# Our quality corpus lives next to this script under ``documents/``. Each file
# begins with ``文書ID: <id>`` then ``タイトル: <title>`` (see foundry-iq/README.md).
DOCUMENTS_DIR = Path(__file__).resolve().parent / "documents"


def _parse_header(text: str, label: str) -> str:
    """Return the value after ``<label>:`` from the first matching line.

    Tolerates a half-width ``:`` or full-width ``：`` and surrounding spaces.
    """
    for line in text.splitlines():
        stripped = line.strip()
        for sep in (":", "："):
            prefix = f"{label}{sep}"
            if stripped.startswith(prefix):
                return stripped[len(prefix):].strip()
    return ""


def load_documents() -> list[dict[str, str]]:
    """Load the quality corpus from ``foundry-iq/documents/*.md``.

    The full file text is stored as ``content`` (so the 文書ID/タイトル header is
    always available to the synthesis model for citations). ``id`` is the 文書ID
    (a valid Azure AI Search document key), ``title`` is the タイトル, and
    ``source`` is the repo-relative path used as the 出典 citation.
    """
    if not DOCUMENTS_DIR.is_dir():
        print(f"ERROR: documents directory not found: {DOCUMENTS_DIR}", file=sys.stderr)
        sys.exit(1)

    documents: list[dict[str, str]] = []
    for path in sorted(DOCUMENTS_DIR.glob("*.md")):
        # utf-8-sig tolerates a possible BOM so the first-line header still parses.
        text = path.read_text(encoding="utf-8-sig")
        doc_id = _parse_header(text, "文書ID")
        title = _parse_header(text, "タイトル")
        if not doc_id:
            print(f"ERROR: '文書ID:' header not found in {path.name}", file=sys.stderr)
            sys.exit(1)
        documents.append(
            {
                "id": doc_id,
                "title": title or doc_id,
                "content": text,
                "source": f"foundry-iq/documents/{path.name}",
            }
        )

    if not documents:
        print(f"ERROR: no *.md documents found under {DOCUMENTS_DIR}", file=sys.stderr)
        sys.exit(1)
    print(f"Loaded {len(documents)} document(s) from {DOCUMENTS_DIR}:")
    for doc in documents:
        print(f"  - {doc['id']}  {doc['title']}")
    return documents


def _require(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        print(f"ERROR: required environment variable '{name}' is not set.", file=sys.stderr)
        sys.exit(1)
    return value


class SearchClient:
    def __init__(self, endpoint: str, token: str) -> None:
        self._endpoint = endpoint.rstrip("/")
        self._headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        }

    def put(self, path: str, body: dict) -> None:
        url = f"{self._endpoint}/{path}?api-version={API_VERSION}"
        response = requests.put(url, headers=self._headers, json=body, timeout=120)
        if response.status_code not in (200, 201, 204):
            print(f"ERROR: PUT {path} failed ({response.status_code}): {response.text}", file=sys.stderr)
            sys.exit(1)

    def post(self, path: str, body: dict) -> dict:
        url = f"{self._endpoint}/{path}?api-version={API_VERSION}"
        response = requests.post(url, headers=self._headers, json=body, timeout=120)
        if response.status_code not in (200, 201):
            print(f"ERROR: POST {path} failed ({response.status_code}): {response.text}", file=sys.stderr)
            sys.exit(1)
        return response.json() if response.content else {}


def create_index(client: SearchClient, index_name: str) -> None:
    print(f"Creating index '{index_name}'...")
    body = {
        "name": index_name,
        "fields": [
            {"name": "id", "type": "Edm.String", "key": True, "filterable": True, "retrievable": True},
            {"name": "title", "type": "Edm.String", "searchable": True, "retrievable": True},
            {"name": "content", "type": "Edm.String", "searchable": True, "retrievable": True},
            # 出典 (citation) metadata: the repo-relative path of the source doc.
            {"name": "source", "type": "Edm.String", "filterable": True, "retrievable": True},
        ],
        "semantic": {
            "configurations": [
                {
                    "name": SEMANTIC_CONFIG_NAME,
                    "prioritizedFields": {
                        "titleField": {"fieldName": "title"},
                        "prioritizedContentFields": [{"fieldName": "content"}],
                    },
                }
            ]
        },
    }
    client.put(f"indexes/{index_name}", body)


def upload_documents(client: SearchClient, index_name: str, documents: list[dict[str, str]]) -> None:
    print(f"Uploading {len(documents)} document(s) to '{index_name}'...")
    actions = [{"@search.action": "mergeOrUpload", **doc} for doc in documents]
    client.post(f"indexes/{index_name}/docs/index", {"value": actions})


def create_knowledge_source(client: SearchClient, ks_name: str, index_name: str) -> None:
    print(f"Creating knowledge source '{ks_name}'...")
    body = {
        "name": ks_name,
        "kind": "searchIndex",
        "searchIndexParameters": {
            "searchIndexName": index_name,
            "semanticConfigurationName": SEMANTIC_CONFIG_NAME,
            # title/content/source travel with each reference so the knowledge
            # base can cite 文書名・出典 alongside the synthesized answer.
            "sourceDataFields": [{"name": "title"}, {"name": "content"}, {"name": "source"}],
            "searchFields": [],
        },
    }
    client.put(f"knowledgesources/{ks_name}", body)


def create_knowledge_base(client: SearchClient, kb_name: str, ks_name: str) -> None:
    print(f"Creating knowledge base '{kb_name}'...")
    aoai_endpoint = _require("AZURE_OPENAI_ENDPOINT").rstrip("/")
    deployment = _require("AZURE_AI_MODEL_DEPLOYMENT_NAME")
    model_name = os.environ.get("AZURE_AI_MODEL_NAME", "").strip() or deployment
    body = {
        "name": kb_name,
        "description": "Foundry IQ knowledge base for the manufacturing-quality agent (品質文書).",
        "knowledgeSources": [{"name": ks_name}],
        "outputMode": "answerSynthesis",
        "retrievalReasoningEffort": {"kind": "low"},
        "models": [
            {
                "kind": "azureOpenAI",
                "azureOpenAIParameters": {
                    # Keyless: the search service managed identity has the
                    # Cognitive Services User role on the Foundry account.
                    "resourceUri": aoai_endpoint,
                    "deploymentId": deployment,
                    "modelName": model_name,
                },
            }
        ],
    }
    client.put(f"knowledgebases/{kb_name}", body)


def _set_azd_env(name: str, value: str) -> bool:
    """Best-effort: store ``value`` in the active azd environment.

    Returns ``True`` when ``azd env set`` succeeds. Falls back to ``False`` when
    azd isn't installed or there's no active environment, so the script still
    works when run standalone.
    """
    azd = shutil.which("azd")
    if not azd:
        return False
    try:
        subprocess.run([azd, "env", "set", name, value], check=True)
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


def main() -> None:
    load_dotenv()

    endpoint = _require("AZURE_SEARCH_ENDPOINT")
    index_name = os.environ.get("AZURE_SEARCH_INDEX_NAME", "").strip() or "mq-quality-index"
    ks_name = os.environ.get("KNOWLEDGE_SOURCE_NAME", "").strip() or "mq-quality-ks"
    kb_name = os.environ.get("KNOWLEDGE_BASE_NAME", "").strip() or "mq-quality-kb"

    documents = load_documents()

    token = DefaultAzureCredential().get_token(SEARCH_SCOPE).token
    client = SearchClient(endpoint, token)

    create_index(client, index_name)
    upload_documents(client, index_name, documents)
    create_knowledge_source(client, ks_name, index_name)
    create_knowledge_base(client, kb_name, ks_name)

    mcp_endpoint = f"{endpoint.rstrip('/')}/knowledgebases/{kb_name}/mcp?api-version={API_VERSION}"
    print()
    print(f"Knowledge base '{kb_name}' is ready.")
    print(f"MCP endpoint: {mcp_endpoint}")
    print()
    if _set_azd_env("KB_MCP_ENDPOINT", mcp_endpoint):
        print("Stored the MCP endpoint as KB_MCP_ENDPOINT in your azd environment.")
    else:
        print("Next: point the toolbox connection at this MCP endpoint. Set")
        print('  azd env set KB_MCP_ENDPOINT "' + mcp_endpoint + '"')


if __name__ == "__main__":
    main()
