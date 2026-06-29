from __future__ import annotations

from agent_framework_foundry_hosting import ResponsesHostServer

from ..settings import Settings
from .agent_factory import build_agent


def run() -> None:
    settings = Settings()  # type: ignore[call-arg]
    server = ResponsesHostServer(build_agent(settings))
    server.run()


if __name__ == "__main__":
    run()
