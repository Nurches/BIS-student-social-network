"""Week 11 (Task 09 promises): soft delete keeps history, faculty is a table.

Migration: docs/migrations/003_soft_delete_and_faculty.sql.
"""

from datetime import UTC, datetime, timedelta
from pathlib import Path

import psycopg
import pytest
from fastapi.testclient import TestClient

from .conftest import PASSWORD, Data
from .test_schema_and_seed import _load, _structure

ROOT = Path(__file__).parents[2]
MIGRATION_003 = ROOT / "docs" / "migrations" / "003_soft_delete_and_faculty.sql"
SCHEMA_V2 = Path(__file__).with_name("fixtures") / "schema_v2.sql"
# v4 (Week 12) changed schema.sql again: 003 is compared with the v3 snapshot.
SCHEMA_V3 = Path(__file__).with_name("fixtures") / "schema_v3.sql"


# ---------- soft delete: a real DELETE cannot wipe history ----------


def test_deleting_an_event_with_registrations_is_refused(data: Data) -> None:
    owner = data.student()
    event = data.event(data.community(owner))
    data.registration(data.student(), event)

    with pytest.raises(psycopg.errors.IntegrityError) as refused:
        data.conn.execute("DELETE FROM event WHERE event_id = %s", (event,))

    assert refused.value.diag.constraint_name == "registration_event_id_fkey"
    assert data.scalar("SELECT COUNT(*) FROM registration WHERE event_id = %s", event) == 1


def test_deleting_a_student_with_notifications_is_refused(data: Data) -> None:
    owner = data.student()
    event = data.event(data.community(owner))
    student = data.student()
    data.conn.execute(
        "INSERT INTO notification (student_id, event_id) VALUES (%s, %s)", (student, event)
    )

    with pytest.raises(psycopg.errors.IntegrityError) as refused:
        data.conn.execute("DELETE FROM student WHERE student_id = %s", (student,))

    assert refused.value.diag.constraint_name == "notification_student_id_fkey"


def test_a_soft_deleted_event_leaves_the_feed_and_its_page(data: Data, client: TestClient) -> None:
    owner = data.student()
    community = data.community(owner)
    kept = data.event(community, title="Kept")
    gone = data.event(community, title="Deleted")
    student = data.student()
    data.subscribe(student, community)
    data.registration(student, gone)
    headers = data.headers(student)

    data.conn.execute("UPDATE event SET deleted_at = NOW() WHERE event_id = %s", (gone,))

    feed = client.get("/api/v1/feed", headers=headers).json()["items"]
    assert [e["event_id"] for e in feed] == [kept]
    detail = client.get(f"/api/v1/events/{gone}", headers=headers)
    assert detail.status_code == 404
    assert detail.json() == {"error": "event_not_found"}
    other = data.student()
    register = client.post(f"/api/v1/events/{gone}/registrations", headers=data.headers(other))
    assert register.status_code == 404
    # History is still there.
    assert data.scalar("SELECT COUNT(*) FROM registration WHERE event_id = %s", gone) == 1


def test_a_soft_deleted_community_hides_its_events_and_refuses_publishing(
    data: Data, client: TestClient
) -> None:
    owner = data.student()
    community = data.community(owner)
    event = data.event(community)
    student = data.student()
    data.subscribe(student, community)
    data.conn.execute(
        "UPDATE community SET deleted_at = NOW() WHERE community_id = %s", (community,)
    )

    assert client.get("/api/v1/feed", headers=data.headers(student)).json()["items"] == []
    assert client.get(f"/api/v1/events/{event}", headers=data.headers(student)).status_code == 404
    deadline = datetime.now(UTC) + timedelta(days=2)
    publish = client.post(
        f"/api/v1/communities/{community}/events",
        json={
            "title": "After deletion",
            "starts_at": (deadline + timedelta(days=1)).isoformat(),
            "registration_deadline": deadline.isoformat(),
            "participant_limit": 5,
        },
        headers=data.headers(owner),
    )
    assert publish.status_code == 404
    assert publish.json() == {"error": "community_not_found"}


def test_a_soft_deleted_student_cannot_log_in_or_use_a_token(
    data: Data, client: TestClient
) -> None:
    student = data.student("gone@kbtu.kz")
    headers = data.headers(student)
    data.conn.execute("UPDATE student SET deleted_at = NOW() WHERE student_id = %s", (student,))

    login = client.post("/api/v1/auth/login", json={"email": "gone@kbtu.kz", "password": PASSWORD})
    assert login.status_code == 401
    assert login.json() == {"error": "invalid_credentials"}
    assert client.get("/api/v1/feed", headers=headers).status_code == 401


def test_a_soft_deleted_subscriber_gets_no_notification(data: Data, client: TestClient) -> None:
    owner = data.student()
    community = data.community(owner)
    active, deleted = data.student(), data.student()
    data.subscribe(active, community)
    data.subscribe(deleted, community)
    data.conn.execute("UPDATE student SET deleted_at = NOW() WHERE student_id = %s", (deleted,))
    deadline = datetime.now(UTC) + timedelta(days=2)

    response = client.post(
        f"/api/v1/communities/{community}/events",
        json={
            "title": "Only for active students",
            "starts_at": (deadline + timedelta(days=1)).isoformat(),
            "registration_deadline": deadline.isoformat(),
            "participant_limit": 5,
        },
        headers=data.headers(owner),
    )

    assert response.status_code == 201
    notified = data.conn.execute("SELECT student_id FROM notification").fetchall()
    assert [r["student_id"] for r in notified] == [active]


# ---------- faculty table ----------


def _register(client: TestClient, email: str, faculty: str | None) -> object:
    body = {"email": email, "password": "long-enough-1", "full_name": "New Student"}
    if faculty is not None:
        body["faculty"] = faculty
    return client.post("/api/v1/auth/register", json=body)


def test_register_with_a_faculty_code_stores_the_reference(data: Data, client: TestClient) -> None:
    response = _register(client, "new@kbtu.kz", "site")  # TODO(confirm): case-insensitive

    assert response.status_code == 201
    code = data.scalar(
        "SELECT f.code FROM student s JOIN faculty f USING (faculty_id) WHERE s.email = %s",
        "new@kbtu.kz",
    )
    assert code == "SITE"
    assert _register(client, "nofaculty@kbtu.kz", None).status_code == 201


def test_register_with_an_unknown_faculty_is_422(data: Data, client: TestClient) -> None:
    response = _register(client, "new@kbtu.kz", "Physics")

    assert response.status_code == 422
    assert response.json() == {"error": "unknown_faculty"}
    assert data.scalar("SELECT COUNT(*) FROM student WHERE email = %s", "new@kbtu.kz") == 0


def test_faculty_codes_cover_every_code_the_seed_and_the_api_example_use(
    db: psycopg.Connection,
) -> None:
    import seed

    codes = {r["code"] for r in db.execute("SELECT code FROM faculty").fetchall()}
    assert {faculty for _, _, faculty, _ in seed.STUDENTS} | {"IT"} <= codes


# ---------- migration 003 ----------


def test_migration_003_on_a_v2_database_equals_a_fresh_v3_schema(db: psycopg.Connection) -> None:
    _load(db, "migrated", SCHEMA_V2.read_text(encoding="utf-8"))
    _load(db, "fresh", SCHEMA_V3.read_text(encoding="utf-8"))
    try:
        db.execute("SET search_path TO migrated")
        # v2 data with free-text faculties, one of them not in the new list.
        db.execute(
            "INSERT INTO student (email, full_name, password_hash, faculty) VALUES "
            "('a@kbtu.kz', 'A', 'x', 'SITE'), ('b@kbtu.kz', 'B', 'x', ' Physics '), "
            "('c@kbtu.kz', 'C', 'x', NULL), ('d@kbtu.kz', 'D', 'x', '')"
        )
        db.execute(MIGRATION_003.read_text(encoding="utf-8"))
        faculties = db.execute(
            "SELECT s.email, f.code FROM student s LEFT JOIN faculty f USING (faculty_id) "
            "ORDER BY s.email"
        ).fetchall()
        db.execute("SET search_path TO public")

        assert [(r["email"], r["code"]) for r in faculties] == [
            ("a@kbtu.kz", "SITE"),
            ("b@kbtu.kz", "Physics"),  # kept, not lost
            ("c@kbtu.kz", None),
            ("d@kbtu.kz", None),
        ]
        assert _structure(db, "migrated") == _structure(db, "fresh")
    finally:
        db.execute("SET search_path TO public")
        db.execute("DROP SCHEMA migrated CASCADE")
        db.execute("DROP SCHEMA fresh CASCADE")


def test_soft_deleted_rows_leave_the_new_lists_too(data: Data, client: TestClient) -> None:
    """MVP extension endpoints: communities, my registrations, inbox."""
    owner = data.student()
    kept = data.community(owner, name="Kept")
    gone = data.community(owner, name="Gone")
    student = data.student()
    event_kept = data.event(kept, title="Stays")
    event_gone = data.event(kept, title="Deleted event")
    data.registration(student, event_kept)
    data.registration(student, event_gone)
    for event_id in (event_kept, event_gone):
        data.conn.execute(
            "INSERT INTO notification (student_id, event_id) VALUES (%s, %s)", (student, event_id)
        )
    data.conn.execute("UPDATE community SET deleted_at = NOW() WHERE community_id = %s", (gone,))
    data.conn.execute("UPDATE event SET deleted_at = NOW() WHERE event_id = %s", (event_gone,))
    headers = data.headers(student)

    names = [c["name"] for c in client.get("/api/v1/communities", headers=headers).json()]
    assert names == ["Kept"]
    kept_row = client.get("/api/v1/communities", headers=headers).json()[0]
    assert kept_row["upcoming_events"] == 1
    assert client.get(f"/api/v1/communities/{gone}/events", headers=headers).status_code == 404
    assert (
        client.put(f"/api/v1/communities/{gone}/subscription", headers=headers).status_code == 404
    )
    mine = client.get("/api/v1/me/registrations", headers=headers).json()["items"]
    assert [e["title"] for e in mine] == ["Stays"]
    inbox = client.get("/api/v1/me/notifications", headers=headers).json()
    assert [n["event_title"] for n in inbox["items"]] == ["Stays"]
    assert inbox["unread_count"] == 1
