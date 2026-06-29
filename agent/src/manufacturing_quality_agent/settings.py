from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    foundry_project_endpoint: str
    azure_ai_model_deployment_name: str
    fabric_project_connection_id: str | None = None
    toolbox_endpoint: str | None = None
    toolbox_name: str = "manufacturing-quality-toolbox"
