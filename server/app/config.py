"""Settings read from environment variables (or a local `.env` file)."""

from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

# The checks of the /data-checks page; owned by the Data & Database member.
DATA_CHECKS_FILE = Path(__file__).with_name("checks") / "data_checks.sql"


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

    # ---------- /data-checks tool page (docs/tools/data-checks-spec.md) ----------

    # Who may run the data checks, comma-separated. A tool permission, not a role.
    # TODO(confirm): move the allow list to the database if it starts to change often.
    data_check_emails: str = (
        "laila@kbtu.kz,madina@kbtu.kz,akbota@kbtu.kz,nurassyl@kbtu.kz,union@kbtu.kz"
    )

    # Optional connection as the qatys_readonly role. Empty = the main pool; the
    # run is a READ ONLY transaction either way.
    database_url_readonly: str = ""

    data_checks_path: Path = DATA_CHECKS_FILE

    # Debug mode: re-read data_checks.sql on every run instead of once at start.
    data_checks_reload: bool = False

    @property
    def data_check_allow_list(self) -> frozenset[str]:
        return frozenset(
            email.strip().lower() for email in self.data_check_emails.split(",") if email.strip()
        )


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]  # values come from the environment
