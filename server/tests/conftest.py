"""Tests run against a real PostgreSQL 16 (docker compose up -d db).

The database in TEST_DATABASE_URL is wiped before every test.
"""

import os
from collections.abc import Iterator
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta

import psycopg
import pytest
from fastapi.testclient import TestClient
from psycopg.rows import dict_row

from app.config import Settings
from app.db import apply_schema
from app.main import create_app
from app.security import hash_password, login_rate_limiter
from app.services.push import PushMessage, SendResult

TEST_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL", "postgresql://qatys:qatys@localhost:5432/qatys_test"
)
PASSWORD = "correct-horse-1"
ROUNDS = 4  # bcrypt cost for tests only; production default is 12


@dataclass
class FakePushSender:
    """Records every push; `results` maps a token to the answer FCM would give."""

    sent: list[PushMessage] = field(default_factory=list)
    results: dict[str, SendResult] = field(default_factory=dict)

    def send(self, message: PushMessage) -> SendResult:
        self.sent.append(message)
        return self.results.get(message.token, SendResult.SENT)


@pytest.fixture
def settings() -> Settings:
    return Settings(
        database_url=TEST_DATABASE_URL,
        jwt_secret="test-secret-that-is-at-least-32-characters",
        bcrypt_rounds=ROUNDS,
        login_rate_limit_per_minute=1000,
        _env_file=None,  # type: ignore[call-arg]
    )


@pytest.fixture
def db() -> Iterator[psycopg.Connection]:
    with psycopg.connect(
        TEST_DATABASE_URL,
        autocommit=True,
        row_factory=dict_row,
        options="-c timezone=UTC",
    ) as conn:
        apply_schema(conn)
        yield conn


@pytest.fixture
def push() -> FakePushSender:
    return FakePushSender()


@pytest.fixture
def client(
    settings: Settings, db: psycopg.Connection, push: FakePushSender
) -> Iterator[TestClient]:
    login_rate_limiter.reset()
    with TestClient(create_app(settings, push)) as test_client:
        yield test_client


# ---------- data helpers (plain SQL, independent of the code under test) ----------


class Data:
    def __init__(self, conn: psycopg.Connection, client: TestClient | None) -> None:
        self.conn = conn
        self.client = client
        self._count = 0

    def student(self, email: str | None = None, password: str = PASSWORD) -> int:
        self._count += 1
        email = email or f"student{self._count}@kbtu.kz"
        row = self.conn.execute(
            "INSERT INTO student (email, full_name, password_hash) VALUES (%s, %s, %s) "
            "RETURNING student_id",
            (email, f"Student {self._count}", hash_password(password, ROUNDS)),
        ).fetchone()
        return row["student_id"]

    def community(self, owner_id: int, *, confirmed: bool = True, name: str | None = None) -> int:
        self._count += 1
        row = self.conn.execute(
            "INSERT INTO community (name, owner_id, is_confirmed) VALUES (%s, %s, %s) "
            "RETURNING community_id",
            (name or f"Community {self._count}", owner_id, confirmed),
        ).fetchone()
        return row["community_id"]

    def subscribe(self, student_id: int, community_id: int) -> None:
        self.conn.execute(
            "INSERT INTO subscription (student_id, community_id) VALUES (%s, %s)",
            (student_id, community_id),
        )

    def event(
        self,
        community_id: int,
        *,
        limit: int = 30,
        deadline: datetime | None = None,
        starts_at: datetime | None = None,
        status: str = "published",
        title: str = "Event",
    ) -> int:
        now = datetime.now(UTC)
        deadline = deadline or now + timedelta(days=5)
        starts_at = starts_at or max(deadline, now) + timedelta(days=1)
        row = self.conn.execute(
            "INSERT INTO event (community_id, title, starts_at, registration_deadline, "
            "participant_limit, status) VALUES (%s, %s, %s, %s, %s, %s) RETURNING event_id",
            (community_id, title, starts_at, deadline, limit, status),
        ).fetchone()
        return row["event_id"]

    def registration(self, student_id: int, event_id: int, status: str = "confirmed") -> None:
        self.conn.execute(
            "INSERT INTO registration (student_id, event_id, status) VALUES (%s, %s, %s)",
            (student_id, event_id, status),
        )

    def headers(self, student_id: int) -> dict[str, str]:
        assert self.client is not None
        email = self.conn.execute(
            "SELECT email FROM student WHERE student_id = %s", (student_id,)
        ).fetchone()["email"]
        response = self.client.post(
            "/api/v1/auth/login", json={"email": email, "password": PASSWORD}
        )
        assert response.status_code == 200, response.text
        return {"Authorization": f"Bearer {response.json()['token']}"}

    def scalar(self, sql: str, *params: object) -> object:
        row = self.conn.execute(sql, params).fetchone()
        return next(iter(row.values()))


@pytest.fixture
def data(db: psycopg.Connection, client: TestClient) -> Data:
    return Data(db, client)
