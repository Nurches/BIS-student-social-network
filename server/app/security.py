"""Password hashing, JWT and the authenticated-student dependency."""

import threading
import time
from collections import defaultdict, deque
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import bcrypt
import jwt
from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .config import Settings, get_settings
from .db import Pool, get_pool
from .errors import ApiError

# bcrypt only reads the first 72 bytes; longer passwords are refused instead of
# being silently truncated.
MAX_PASSWORD_BYTES = 72

_bearer = HTTPBearer(auto_error=False, description="JWT from POST /api/v1/auth/login")


def hash_password(password: str, rounds: int) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt(rounds)).decode()


def verify_password(password: str, password_hash: str) -> bool:
    encoded = password.encode()
    if len(encoded) > MAX_PASSWORD_BYTES:
        return False
    try:
        return bcrypt.checkpw(encoded, password_hash.encode())
    except ValueError:  # not a bcrypt hash, e.g. a placeholder in old seed data
        return False


class _DummyHash:
    """A real hash to check against when the email is unknown, so the answer
    takes as long as for a known email and does not reveal which accounts exist."""

    _value: str | None = None

    @classmethod
    def get(cls, rounds: int) -> str:
        if cls._value is None:
            cls._value = hash_password("not-a-real-password", rounds)
        return cls._value


def dummy_verify(password: str, rounds: int) -> None:
    verify_password(password, _DummyHash.get(rounds))


def issue_token(student_id: int, settings: Settings, now: datetime | None = None) -> str:
    now = now or datetime.now(UTC)
    claims = {
        "sub": str(student_id),
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(hours=settings.jwt_ttl_hours)).timestamp()),
    }
    return jwt.encode(claims, settings.jwt_secret, algorithm="HS256")


@dataclass(frozen=True)
class CurrentStudent:
    student_id: int
    email: str
    full_name: str


def current_student(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    pool: Pool = Depends(get_pool),
    settings: Settings = Depends(get_settings),
) -> CurrentStudent:
    """401 `unauthorized` for a missing, malformed, forged or expired token,
    and for a token whose student no longer exists."""
    if credentials is None:
        raise ApiError(401, "unauthorized")
    try:
        claims = jwt.decode(
            credentials.credentials,
            settings.jwt_secret,
            algorithms=["HS256"],
            options={"require": ["sub", "exp"]},
        )
        student_id = int(claims["sub"])
    except (jwt.PyJWTError, ValueError) as exc:
        raise ApiError(401, "unauthorized") from exc

    with pool.connection() as conn:
        row = conn.execute(
            "SELECT student_id, email, full_name FROM student WHERE student_id = %s",
            (student_id,),
        ).fetchone()
    if row is None:
        raise ApiError(401, "unauthorized")
    return CurrentStudent(**row)


class RateLimiter:
    """Sliding one-minute window per key, in memory.

    Enough for one server instance (the Render free tier runs exactly one);
    several instances would need a shared store such as Redis.
    """

    def __init__(self) -> None:
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def hit(self, key: str, limit: int, window_seconds: float = 60) -> float | None:
        """Records a hit; returns the seconds to wait when over the limit."""
        now = time.monotonic()
        with self._lock:
            hits = self._hits[key]
            while hits and now - hits[0] >= window_seconds:
                hits.popleft()
            if len(hits) >= limit:
                return window_seconds - (now - hits[0])
            hits.append(now)
            return None

    def reset(self) -> None:
        with self._lock:
            self._hits.clear()


login_rate_limiter = RateLimiter()


def client_ip(request: Request) -> str:
    # Render terminates TLS in a proxy; uvicorn runs with --proxy-headers, so
    # request.client is the real client address there.
    return request.client.host if request.client else "unknown"


def limit_login_rate(request: Request, settings: Settings = Depends(get_settings)) -> None:
    wait = login_rate_limiter.hit(client_ip(request), settings.login_rate_limit_per_minute)
    if wait is not None:
        raise ApiError(
            429, "too_many_requests", headers={"Retry-After": str(max(1, int(wait) + 1))}
        )
