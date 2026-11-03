"""Settings read from environment variables (or a local `.env` file)."""

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # postgresql://user:password@host:5432/db — Neon and Render URLs work as is.
    database_url: str

    # HS256 signing key. No default on purpose: the server refuses to start
    # without one, so a forgotten variable can never mean a guessable secret.
    jwt_secret: str = Field(min_length=32)
    jwt_ttl_hours: int = 24

    # NFR-02. Tests lower it to keep the suite fast; never below 12 in production.
    bcrypt_rounds: int = Field(default=12, ge=4, le=16)

    # The phone app does not need CORS; list origins only for a browser client.
    cors_origins: list[str] = []

    # Login attempts per client IP per minute, on top of the account lockout.
    login_rate_limit_per_minute: int = 20

    # Bodies larger than this are rejected with 413 before they are parsed.
    max_body_bytes: int = 64 * 1024

    # Firebase service account key: the JSON itself, not a path, so it can live
    # in one Render environment variable. Empty = pushes are logged, not sent.
    fcm_service_account_json: str = ""

    # Times in push texts are shown in the students' zone.
    display_timezone: str = "Asia/Almaty"

    # Swagger UI at /docs is how the admin publishes for the demo (roadmap §3).
    enable_docs: bool = True


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]  # values come from the environment
