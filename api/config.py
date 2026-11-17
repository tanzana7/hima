"""Application settings (env / api/.env)."""
from __future__ import annotations

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

_ENV_FILE = Path(__file__).resolve().parent / ".env"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=str(_ENV_FILE), env_file_encoding="utf-8", extra="ignore"
    )

    database_url: str = "postgresql+psycopg://postgres:postgres@localhost:5432/atsumaro"
    bot_api_secret: str = ""
    api_jwt_secret: str = ""
    discord_bot_token: str = ""
    discord_client_id: str = ""
    discord_client_secret: str = ""


settings = Settings()
