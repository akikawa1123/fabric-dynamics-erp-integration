from __future__ import annotations

from pathlib import Path
from typing import Any

from ..settings import Settings

# prompts/ はパッケージ直下にあるため、integrations/ から1つ上のディレクトリを参照する。
PROMPT_PATH = Path(__file__).resolve().parent.parent / "prompts" / "system.md"


def build_agent(settings: Settings) -> Any:
    # 公式scaffoldへ統合する前もfixtureテストが動くように遅延importする。
    import httpx
    from agent_framework import Agent, MCPStreamableHTTPTool
    from agent_framework.foundry import FoundryChatClient
    from azure.identity import DefaultAzureCredential, get_bearer_token_provider

    credential = DefaultAzureCredential()
    tools: list[Any] = []

    if settings.fabric_project_connection_id:
        # Workaround for agent-framework-foundry 1.8.2: FoundryChatClient.get_fabric_tool()
        # returns an azure-core model, and the preview-tool sanitizer only shallow-copies it,
        # leaving the nested FabricDataAgentToolParameters non-JSON-serializable (the Responses
        # request body then fails json.dumps). .as_dict() deep-converts to plain dicts so the
        # tool serializes correctly. Verified live against the SALES/ERP path
        # (da_manufacturing_erp). Remove once the SDK serializes preview tools natively.
        tools.append(
            FoundryChatClient.get_fabric_tool(
                connection_id=settings.fabric_project_connection_id
            ).as_dict()
        )

    if settings.toolbox_endpoint:
        token_provider = get_bearer_token_provider(
            credential,
            "https://ai.azure.com/.default",
        )

        class ToolboxAuth(httpx.Auth):
            def auth_flow(self, request: httpx.Request):  # type: ignore[no-untyped-def]
                request.headers["Authorization"] = f"Bearer {token_provider()}"
                yield request

        http_client = httpx.AsyncClient(
            auth=ToolboxAuth(),
            headers={"Foundry-Features": "Toolboxes=V1Preview"},
            timeout=120.0,
        )
        tools.append(
            MCPStreamableHTTPTool(
                name=settings.toolbox_name,
                url=settings.toolbox_endpoint,
                http_client=http_client,
                load_prompts=False,
            )
        )

    return Agent(
        client=FoundryChatClient(
            project_endpoint=settings.foundry_project_endpoint,
            model=settings.azure_ai_model_deployment_name,
            credential=credential,
        ),
        instructions=PROMPT_PATH.read_text(encoding="utf-8"),
        tools=tools,
        default_options={"store": False},
    )
