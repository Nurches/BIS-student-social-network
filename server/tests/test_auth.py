"""POST /auth/register and /auth/login: BR-01 and NFR-02 (TC-06)."""

from datetime import UTC, datetime, timedelta

import jwt

from app.config import Settings

from .conftest import PASSWORD, Data

REGISTER = "/api/v1/auth/register"
LOGIN = "/api/v1/auth/login"


def login(data: Data, email: str, password: str = PASSWORD):
    return data.client.post(LOGIN, json={"email": email, "password": password})


def test_register_creates_an_account_with_a_bcrypt_hash(data: Data) -> None:
    response = data.client.post(
        REGISTER,
        json={"email": " Aru@KBTU.kz ", "password": "long-enough", "full_name": "Aru Sadykova"},
    )

    assert response.status_code == 201
    assert response.json() == {
        "student_id": response.json()["student_id"],
        "email": "aru@kbtu.kz",
        "full_name": "Aru Sadykova",
    }
    stored = data.scalar("SELECT password_hash FROM student WHERE email = 'aru@kbtu.kz'")
    assert str(stored).startswith("$2b$")
    assert "long-enough" not in str(stored)


def test_register_rejects_a_non_university_email_br01(data: Data) -> None:
    response = data.client.post(
        REGISTER, json={"email": "aru@gmail.com", "password": "long-enough", "full_name": "A"}
    )
    assert response.status_code == 422
    assert response.json() == {"error": "not_a_university_email"}


def test_register_rejects_a_duplicate_email(data: Data) -> None:
    data.student("aru@kbtu.kz")
    response = data.client.post(
        REGISTER, json={"email": "aru@kbtu.kz", "password": "long-enough", "full_name": "A"}
    )
    assert response.status_code == 409
    assert response.json() == {"error": "email_already_registered"}


def test_register_rejects_short_and_overlong_passwords(data: Data) -> None:
    body = {"email": "aru@kbtu.kz", "full_name": "A"}
    short = data.client.post(REGISTER, json={**body, "password": "short"})
    long = data.client.post(REGISTER, json={**body, "password": "x" * 73})
    assert short.json() == {"error": "password_too_short"}
    assert long.json() == {"error": "password_too_long"}


def test_login_returns_a_24_hour_token_and_the_student(data: Data, settings: Settings) -> None:
    student_id = data.student("aru@kbtu.kz")

    response = login(data, "ARU@kbtu.kz")

    assert response.status_code == 200
    body = response.json()
    assert body["student"] == {
        "student_id": student_id,
        "email": "aru@kbtu.kz",
        "full_name": body["student"]["full_name"],
    }
    claims = jwt.decode(body["token"], settings.jwt_secret, algorithms=["HS256"])
    assert claims["sub"] == str(student_id)
    assert claims["exp"] - claims["iat"] == 24 * 3600


def test_wrong_password_and_unknown_email_get_the_same_answer(data: Data) -> None:
    data.student("aru@kbtu.kz")
    assert login(data, "aru@kbtu.kz", "wrong").json() == {"error": "invalid_credentials"}
    assert login(data, "nobody@kbtu.kz").json() == {"error": "invalid_credentials"}
    assert login(data, "aru@kbtu.kz", "wrong").status_code == 401


def test_login_rejects_a_non_university_email(data: Data) -> None:
    response = login(data, "aru@gmail.com")
    assert response.status_code == 422
    assert response.json() == {"error": "not_a_university_email"}


def test_tc06_lockout_after_5_failed_attempts(data: Data) -> None:
    """TC-06: 5 wrong passwords, then the correct one is refused (6th attempt)."""
    data.student("aru@kbtu.kz")

    for _ in range(5):
        assert login(data, "aru@kbtu.kz", "wrong").status_code == 401

    sixth = login(data, "aru@kbtu.kz")  # the correct password
    assert sixth.status_code == 423
    assert sixth.json() == {"error": "account_locked", "retry_after_minutes": 15}
    assert 14 * 60 < int(sixth.headers["Retry-After"]) <= 15 * 60

    # More wrong attempts during the lock do not extend it.
    login(data, "aru@kbtu.kz", "wrong")
    assert data.scalar("SELECT locked_until <= NOW() + INTERVAL '15 minutes' FROM student") is True


def test_lock_expires_after_15_minutes(data: Data) -> None:
    data.student("aru@kbtu.kz")
    for _ in range(5):
        login(data, "aru@kbtu.kz", "wrong")

    data.conn.execute("UPDATE student SET locked_until = NOW() - INTERVAL '1 second'")

    assert login(data, "aru@kbtu.kz").status_code == 200


def test_retry_after_minutes_is_rounded_up_and_never_zero(data: Data) -> None:
    data.student("aru@kbtu.kz")
    data.conn.execute("UPDATE student SET locked_until = NOW() + INTERVAL '10 seconds'")

    response = login(data, "aru@kbtu.kz")

    assert response.json()["retry_after_minutes"] == 1


def test_failures_outside_the_10_minute_window_start_a_new_one(data: Data) -> None:
    data.student("aru@kbtu.kz")
    for _ in range(4):
        login(data, "aru@kbtu.kz", "wrong")
    data.conn.execute(
        "UPDATE student SET first_failed_login_at = NOW() - INTERVAL '10 minutes 1 second'"
    )

    for _ in range(4):
        assert login(data, "aru@kbtu.kz", "wrong").status_code == 401
    assert login(data, "aru@kbtu.kz").status_code == 200


def test_successful_login_resets_the_counter(data: Data) -> None:
    data.student("aru@kbtu.kz")
    for _ in range(4):
        login(data, "aru@kbtu.kz", "wrong")
    assert login(data, "aru@kbtu.kz").status_code == 200

    for _ in range(4):
        assert login(data, "aru@kbtu.kz", "wrong").status_code == 401
    assert login(data, "aru@kbtu.kz").status_code == 200


def test_login_is_rate_limited_per_ip(data: Data, settings: Settings) -> None:
    settings.login_rate_limit_per_minute = 3
    for _ in range(3):
        login(data, "nobody@kbtu.kz")

    response = login(data, "nobody@kbtu.kz")

    assert response.status_code == 429
    assert response.json() == {"error": "too_many_requests"}
    assert int(response.headers["Retry-After"]) >= 1


def test_protected_endpoints_require_a_valid_token(data: Data, settings: Settings) -> None:
    student_id = data.student()
    now = datetime.now(UTC)
    expired = jwt.encode(
        {"sub": str(student_id), "exp": int((now - timedelta(seconds=1)).timestamp())},
        settings.jwt_secret,
        algorithm="HS256",
    )
    forged = jwt.encode(
        {"sub": str(student_id), "exp": int((now + timedelta(hours=1)).timestamp())},
        "another-secret-that-is-at-least-32-characters",
        algorithm="HS256",
    )

    for headers in (
        {},
        {"Authorization": "Bearer nonsense"},
        {"Authorization": f"Bearer {expired}"},
        {"Authorization": f"Bearer {forged}"},
    ):
        response = data.client.get("/api/v1/feed", headers=headers)
        assert response.status_code == 401
        assert response.json() == {"error": "unauthorized"}


def test_production_bcrypt_cost_is_12() -> None:
    assert Settings.model_fields["bcrypt_rounds"].default == 12
