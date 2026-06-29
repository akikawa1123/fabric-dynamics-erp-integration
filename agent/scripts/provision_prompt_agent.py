"""Provision the OBO-capable Prompt Agent for the Teams / M365 Copilot demo.

なぜ Prompt Agent か:
- Fabric data agent ツールは **identity passthrough（OBO）専用**で、サインインした
  エンドユーザーの identity でクエリする（公式: foundry/agents/how-to/tools/fabric）。
- デプロイ済み **Hosted Agent** はコンテナの managed identity（unattended）で動くため、
  Teams/M365 Copilot 経由ではエンドユーザーの OBO が Fabric ツールまで伝播せず
  `No CustomKeys connection found for AzureFabric` で失敗する。
- **Prompt Agent**（サーバサイド定義）は Agent Service が OBO 交換を処理するため、
  Playground でも Teams/M365 Copilot でもエンドユーザー identity で Fabric を照会できる。
  → Teams へはこの Prompt Agent を公開する。

Hosted Agent（manufacturing-quality-agent）は Responses Protocol / ローカル fixture 用に
そのまま残す。本スクリプトは Teams 用の Prompt Agent を別途作成/更新する。

使い方:
  cd agent
  uv run --extra foundry python scripts/provision_prompt_agent.py
  # Foundry IQ も載せる場合（prompt agent の agent identity に Search Index Data Reader 付与後）:
  uv run --extra foundry python scripts/provision_prompt_agent.py --with-kb

注意:
- KB(MCP) ツールはツール列挙時に Search へアクセスするため、prompt agent の identity に
  `Search Index Data Reader` が無いと 403 になり、**エージェント全体（Fabric 含む）が失敗**する。
  RBAC 付与が済むまで KB は付けない（既定 off）。
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    FabricDataAgentToolParameters,
    MicrosoftFabricPreviewTool,
    PromptAgentDefinition,
    ToolProjectConnection,
)
from azure.identity import DefaultAzureCredential

PROMPT_PATH = (
    Path(__file__).resolve().parent.parent
    / "src"
    / "manufacturing_quality_agent"
    / "prompts"
    / "system.md"
)


def main() -> None:
    ap = argparse.ArgumentParser(description="Provision the OBO Prompt Agent (Teams entry)")
    ap.add_argument(
        "--project-endpoint",
        default=os.environ.get("FOUNDRY_PROJECT_ENDPOINT"),
        help="Foundry project endpoint (env: FOUNDRY_PROJECT_ENDPOINT)",
    )
    ap.add_argument(
        "--model",
        default=os.environ.get("PROMPT_AGENT_MODEL", "gpt-5.4-mini"),
        help=(
            "Model deployment for orchestration. Default gpt-5.4-mini: ~5-10s faster than "
            "gpt-5.4 (sales ~27s vs ~40s) which keeps M365 Copilot under its response budget, "
            "with candidate discipline / plain-text formatting preserved. Override via "
            "--model or env PROMPT_AGENT_MODEL."
        ),
    )
    ap.add_argument("--agent-name", default="manufacturing-quality-agent-obo")
    ap.add_argument("--fabric-connection-name", default="da_manufacturing_erp")
    ap.add_argument("--kb-connection-name", default="mq-quality-kb-mcp")
    ap.add_argument(
        "--with-kb",
        action="store_true",
        help="Foundry IQ の KB(MCP) ツールも付与（prompt agent identity に Search Index Data Reader が必要）",
    )
    args = ap.parse_args()
    if not args.project_endpoint:
        raise SystemExit("--project-endpoint（または env FOUNDRY_PROJECT_ENDPOINT）が必要です。")

    credential = DefaultAzureCredential()
    project = AIProjectClient(endpoint=args.project_endpoint, credential=credential)

    fabric_conn = project.connections.get(args.fabric_connection_name)
    instructions = PROMPT_PATH.read_text(encoding="utf-8")

    tools: list = [
        MicrosoftFabricPreviewTool(
            fabric_dataagent_preview=FabricDataAgentToolParameters(
                project_connections=[ToolProjectConnection(project_connection_id=fabric_conn.id)]
            )
        )
    ]

    if args.with_kb:
        kb_conn = project.connections.get(args.kb_connection_name)
        tools.append(
            {
                "type": "mcp",
                "server_label": "knowledge_base",
                "server_url": kb_conn.target,
                "project_connection_id": kb_conn.id,
                "require_approval": "never",
            }
        )

    agent = project.agents.create_version(
        agent_name=args.agent_name,
        definition=PromptAgentDefinition(
            model=args.model,
            instructions=instructions,
            tools=tools,
        ),
    )
    tool_names = "Fabric" + (" + Foundry IQ(KB)" if args.with_kb else "")
    print(f"[OK] Prompt Agent '{agent.name}' v{agent.version} を作成（tools: {tool_names}）")
    print("     Teams/M365 Copilot へはこのエージェントを公開すると Fabric が OBO で動作する。")
    print("     検証: Foundry Playground でこのエージェントに factory/sales 質問を投げる。")


if __name__ == "__main__":
    main()
