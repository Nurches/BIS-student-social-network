"""Registration and login: BR-01 (university email) and NFR-02 (bcrypt, lockout)."""

import math
import re
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from psycopg import errors

from ..config import Settings
from ..db import Conn
from ..errors import ApiError
from ..security import (
    MAX_PASSWORD_BYTES,
    dummy_verify,
    hash_password,
    issue_token,
    verify_password,
)

MAX_FAILED_LOGINS = 5
FAILURE_WINDOW = timedelta(minutes=10)
LOCK_DURATION = timedelta(minutes=15)
MIN_PASSWORD_LENGTH = 8

# Mirrors chk_university_email in schema.sql.
_UNIVERSITY_EMAIL = re.compile(r"^[^@\s]+@kbtu\.kz$")


def normalize_email(email: str) -> str:
    return email.strip().lower()


def require_university_email(email: str) -> None:
    if not _UNIVERSITY_EMAIL.match(email):
        raise ApiError(422, "not_a_university_email")


def register(
    conn: Conn,
    settings: Settings,
    *,
    email: str,
    password: str,
    full_name: str,
    faculty: str | None,
    enrolled_year: int | None,
) -> dict:
    email = normalize_email(email)
    require_university_email(email)
    if len(password) < MIN_PASSWORD_LENGTH:
        raise ApiError(422, "password_too_short")
    if len(password.encode()) > MAX_PASSWORD_BYTES:
        raise ApiError(422, "password_too_long")

    password_hash = hash_password(password, settings.bcrypt_rounds)
    try:
        with conn.transaction():
            row = conn.execute(
                """
                INSERT INTO student (email, full_name, password_hash, faculty, enrolled_year)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING student_id, email, full_name
                """,
                (email, full_name, password_hash, faculty, enrolled_year),
            ).fetchone()
    except errors.UniqueViolation as exc:
        raise ApiError(409, "email_already_registered") from exc
    # TODO(confirm): no verification email is sent for the demo; the account is
    # active at once (roadmap §3, out of scope until after Week 15).
    assert row is not None
    return row


@dataclass(frozen=True)
class LoginOutcome:
    """Decided inside the transaction, raised after it commits: a failed
    attempt must be counted even though the answer is an error."""

    student: dict | None = None
    locked_for: timedelta | None = None

    @property
    def token_subject(self) -> int:
        assert self.student is not None
        return self.student["student_id"]


def login(conn: Conn, settings: Settings, *, email: str, password: str) -> dict:
    email = normalize_email(email)
    require_university_email(email)
    outcome = _check_credentials(conn, settings, email, password, datetime.now(UTC))

    if outcome.locked_for is not None:
        seconds = math.ceil(outcome.locked_for.total_seconds())
        raise ApiError(
            423,
            "account_locked",
            headers={"Retry-After": str(seconds)},
            retry_after_minutes=max(1, math.ceil(seconds / 60)),
        )
    if outcome.student is None:
        raise ApiError(401, "invalid_credentials")

    return {
        "token": issue_token(outcome.token_subject, settings),
        "student": outcome.student,
    }


def _check_credentials(
    conn: Conn, settings: Settings, email: str, password: str, now: datetime
) -> LoginOutcome:
    with conn.transaction():
        # The row lock serialises parallel attempts on one account, so five
        # simultaneous wrong passwords still count as five.
        student = conn.execute(
            """
            SELECT student_id, email, full_name, password_hash,
                   failed_logins, first_failed_login_at, locked_until
            FROM student WHERE email = %s FOR UPDATE
            """,
            (email,),
        ).fetchone()

        if student is None:
            dummy_verify(password, settings.bcrypt_rounds)
            return LoginOutcome()

        locked_until = student["locked_until"]
        if locked_until is not None and locked_until > now:
            # Even the correct password is refused, and the lock is not extended.
            return LoginOutcome(locked_for=locked_until - now)

        public = {k: student[k] for k in ("student_id", "email", "full_name")}
        if verify_password(password, student["password_hash"]):
            conn.execute(
                """
                UPDATE student
                SET failed_logins = 0, first_failed_login_at = NULL, locked_until = NULL
                WHERE student_id = %s
                """,
                (student["student_id"],),
            )
            return LoginOutcome(student=public)

        window_start = student["first_failed_login_at"]
        if window_start is None or now - window_start >= FAILURE_WINDOW:
            failures, window_start = 1, now
        else:
            failures = student["failed_logins"] + 1

        if failures >= MAX_FAILED_LOGINS:
            # The 5th failure still answers 401; the next attempt sees 423.
            conn.execute(
                """
                UPDATE student
                SET failed_logins = 0, first_failed_login_at = NULL, locked_until = %s
                WHERE student_id = %s
                """,
                (now + LOCK_DURATION, student["student_id"]),
            )
        else:
            conn.execute(
                """
                UPDATE student SET failed_logins = %s, first_failed_login_at = %s
                WHERE student_id = %s
                """,
                (failures, window_start, student["student_id"]),
            )
        return LoginOutcome()
