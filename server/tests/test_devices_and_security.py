"""Device tokens, /health, and the security checklist of roadmap M6."""

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app

from .conftest import Data, FakePushSender

TOKEN = "/api/v1/me/device-token"


def test_health_checks_the_database(client: TestClient) -> None:
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_health_answers_503_when_the_database_is_down(settings: Settings) -> None:
    settings.database_url = "postgresql://nobody@127.0.0.1:1/none?connect_timeout=1"
    with TestClient(create_app(settings, FakePushSender())) as client:
        response = client.get("/api/v1/health")
    assert response.status_code == 503
    assert response.json() == {"status": "unavailable", "error": "database_unavailable"}


def test_device_token_is_stored_and_moves_to_the_last_account(data: Data) -> None:
    a, b = data.student(), data.student()

    first = data.client.put(TOKEN, json={"token": "phone-1"}, headers=data.headers(a))
    second = data.client.put(
        TOKEN, json={"token": "phone-1", "platform": "android"}, headers=data.headers(b)
    )

    assert first.status_code == second.status_code == 204
    assert data.scalar("SELECT COUNT(*) FROM device_token") == 1
    assert data.scalar("SELECT student_id FROM device_token WHERE token = 'phone-1'") == b


def test_device_token_is_deleted_on_logout_and_delete_is_idempotent(data: Data) -> None:
    me = data.student()
    headers = data.headers(me)
    data.client.put(TOKEN, json={"token": "phone-1"}, headers=headers)

    first = data.client.request("DELETE", TOKEN, json={"token": "phone-1"}, headers=headers)
    again = data.client.request("DELETE", TOKEN, json={"token": "phone-1"}, headers=headers)

    assert first.status_code == again.status_code == 204
    assert data.scalar("SELECT COUNT(*) FROM device_token") == 0


def test_a_student_cannot_delete_someone_elses_token(data: Data) -> None:
    owner, other = data.student(), data.student()
    data.client.put(TOKEN, json={"token": "phone-1"}, headers=data.headers(owner))

    data.client.request("DELETE", TOKEN, json={"token": "phone-1"}, headers=data.headers(other))

    assert data.scalar("SELECT COUNT(*) FROM device_token") == 1


def test_device_token_validation(data: Data) -> None:
    headers = data.headers(data.student())
    empty = data.client.put(TOKEN, json={"token": ""}, headers=headers)
    platform = data.client.put(TOKEN, json={"token": "t", "platform": "nokia"}, headers=headers)
    assert empty.json()["error"] == platform.json()["error"] == "validation_failed"


def test_oversized_body_is_rejected_before_parsing(client: TestClient) -> None:
    response = client.post(
        "/api/v1/auth/login",
        content=b'{"email": "' + b"a" * 70_000 + b'"}',
        headers={"Content-Type": "application/json"},
    )
    assert response.status_code == 413
    assert response.json() == {"error": "payload_too_large"}


def test_unknown_route_uses_the_error_format(client: TestClient) -> None:
    response = client.get("/api/v1/nothing-here")
    assert response.status_code == 404
    assert response.json() == {"error": "not_found"}


def test_unexpected_errors_hide_the_stack_trace(
    data: Data, monkeypatch: pytest.MonkeyPatch
) -> None:
    from app.services import events

    def explode(*_: object, **__: object) -> None:
        raise RuntimeError("secret detail: password=hunter2")

    monkeypatch.setattr(events, "feed", explode)
    headers = data.headers(data.student())
    client = TestClient(data.client.app, raise_server_exceptions=False)

    response = client.get("/api/v1/feed", headers=headers)

    assert response.status_code == 500
    assert response.json() == {"error": "internal_error"}
    assert "hunter2" not in response.text


def test_cors_is_closed_unless_origins_are_configured(client: TestClient) -> None:
    response = client.options(
        "/api/v1/health",
        headers={"Origin": "https://evil.example", "Access-Control-Request-Method": "GET"},
    )
    assert "access-control-allow-origin" not in response.headers


def test_server_refuses_to_start_with_a_short_jwt_secret() -> None:
    with pytest.raises(ValueError, match="jwt_secret"):
        Settings(database_url="postgresql://x", jwt_secret="short", _env_file=None)  # type: ignore[call-arg]


def test_passwords_are_never_logged(data: Data, caplog: pytest.LogCaptureFixture) -> None:
    data.student("aru@kbtu.kz")
    with caplog.at_level("DEBUG"):
        data.client.post(
            "/api/v1/auth/login", json={"email": "aru@kbtu.kz", "password": "wrong-pass-123"}
        )
    assert "wrong-pass-123" not in caplog.text


def test_swagger_and_admin_page_are_served(client: TestClient) -> None:
    assert client.get("/docs").status_code == 200
    admin = client.get("/admin")
    assert admin.status_code == 200
    assert "Qatys Admin" in admin.text


def test_server_schema_has_no_test_data() -> None:
    schema = (Path(__file__).parents[1] / "app" / "schema.sql").read_text()
    assert "INSERT INTO" not in schema
