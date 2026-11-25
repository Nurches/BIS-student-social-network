"""Week 12 (schema v4): community requests by any student, pushes when an
event is cancelled or moved, and the announcement cards of the home screen.

Migration: docs/migrations/004_community_requests_and_event_changes.sql.
Test cases of Madina's run (docs/test_cases_and_rtm.xlsx) are named in the
test names: request pending, approve -> push -> publish, reject / limit /
taken name, cancel -> push, reschedule -> push.
"""

from datetime import UTC, datetime, timedelta
from pathlib import Path

import psycopg
from fastapi.testclient import TestClient

from .conftest import Data, FakePushSender
from .test_schema_and_seed import _load, _structure

A = "/api/v1/admin"
ROOT = Path(__file__).parents[2]
MIGRATION_004 = ROOT / "docs" / "migrations" / "004_community_requests_and_event_changes.sql"
SCHEMA_V3 = Path(__file__).with_name("fixtures") / "schema_v3.sql"
# Week 13 moved the live schema to v5: migration 004 must give exactly v4.
SCHEMA_V4 = Path(__file__).with_name("fixtures") / "schema_v4.sql"


def moderator(data: Data, email: str = "union@kbtu.kz") -> int:
    student = data.student(email)
    data.conn.execute("UPDATE student SET is_moderator = TRUE WHERE student_id = %s", (student,))
    return student


def phone(data: Data, student_id: int, token: str) -> None:
    data.conn.execute(
        "INSERT INTO device_token (student_id, token, platform) VALUES (%s, %s, 'ios')",
        (student_id, token),
    )


def request(client: TestClient, headers: dict, name: str, description: str | None = None):
    return client.post(
        "/api/v1/communities", json={"name": name, "description": description}, headers=headers
    )


# ---------- community requests ----------


def test_a_student_request_is_pending_and_gives_no_rights_yet(
    client: TestClient, data: Data
) -> None:
    student = data.student()
    headers = data.headers(student)

    created = request(client, headers, "  Chess Club ", "Blitz on Fridays")

    assert created.status_code == 201
    body = created.json()
    assert (body["name"], body["status"], body["reject_reason"]) == ("Chess Club", "pending", None)
    community = body["community_id"]

    mine = client.get("/api/v1/me/community-requests", headers=headers).json()
    assert [r["name"] for r in mine["items"]] == ["Chess Club"]
    assert mine["pending_limit"] == 3

    # The owner sees it in Explore as pending; another student does not see it.
    own_list = client.get("/api/v1/communities", headers=headers).json()
    assert [(c["name"], c["status"], c["is_mine"]) for c in own_list] == [
        ("Chess Club", "pending", True)
    ]
    other = data.headers(data.student())
    assert client.get("/api/v1/communities", headers=other).json() == []
    follow = client.put(f"/api/v1/communities/{community}/subscription", headers=other)
    assert follow.json() == {"error": "community_not_found"}

    # BR-01: no publishing and no admin panel while pending.
    publish = client.post(
        f"/api/v1/communities/{community}/events",
        json={
            "title": "Blitz",
            "starts_at": "2030-01-02T10:00:00+05:00",
            "registration_deadline": "2030-01-01T10:00:00+05:00",
            "participant_limit": 10,
        },
        headers=headers,
    )
    assert publish.json() == {"error": "not_a_confirmed_admin"}
    assert client.get(f"{A}/me", headers=headers).json() == {"error": "not_an_admin"}


def test_three_pending_requests_at_most_and_names_are_unique_ignoring_case(
    client: TestClient, data: Data
) -> None:
    data.community(data.student(), name="IT Club")
    headers = data.headers(data.student())

    taken = request(client, headers, "it club")
    assert (taken.status_code, taken.json()) == (409, {"error": "community_name_taken"})

    for name in ("One", "Two", "Three"):
        assert request(client, headers, name).status_code == 201
    fourth = request(client, headers, "Four")
    assert (fourth.status_code, fourth.json()) == (409, {"error": "too_many_pending_requests"})

    short = request(client, headers, "ab")
    assert short.status_code == 422


def test_moderator_approves_owner_gets_a_push_and_can_publish(
    client: TestClient, data: Data, push: FakePushSender
) -> None:
    mod = moderator(data)
    student = data.student()
    phone(data, student, "tok-student")
    headers = data.headers(student)
    community = request(client, headers, "Chess Club").json()["community_id"]

    pending = client.get(f"{A}/communities?status=pending", headers=data.headers(mod)).json()
    assert [c["name"] for c in pending] == ["Chess Club"]
    assert client.get(f"{A}/overview", headers=data.headers(mod)).json()["pending_requests"] == 1

    approved = client.post(f"{A}/communities/{community}/approve", headers=data.headers(mod))

    assert approved.status_code == 200
    assert approved.json()["community"]["status"] == "confirmed"
    assert approved.json()["community"]["reviewed_at"] is not None
    assert approved.json()["notified"] == 1
    assert [(m.token, m.title, m.data) for m in push.sent] == [
        (
            "tok-student",
            "Community approved",
            {"type": "community_approved", "community_id": str(community)},
        )
    ]
    inbox = client.get("/api/v1/me/notifications", headers=headers).json()
    assert [(n["kind"], n["event_id"], n["community_name"]) for n in inbox["items"]] == [
        ("community_approved", None, "Chess Club")
    ]
    assert inbox["unread_count"] == 1

    # Now the owner may publish and use the admin panel.
    publish = client.post(
        f"/api/v1/communities/{community}/events",
        json={
            "title": "Blitz",
            "starts_at": "2030-01-02T10:00:00+05:00",
            "registration_deadline": "2030-01-01T10:00:00+05:00",
            "participant_limit": 10,
        },
        headers=headers,
    )
    assert publish.status_code == 201
    assert client.get(f"{A}/me", headers=headers).status_code == 200

    again = client.post(f"{A}/communities/{community}/approve", headers=data.headers(mod))
    assert again.json() == {"error": "community_not_pending"}


def test_only_another_moderator_reviews_a_request(client: TestClient, data: Data) -> None:
    mod = moderator(data)
    owner = data.student()
    data.community(owner)  # a confirmed community: owner has the admin panel
    request_id = request(client, data.headers(data.student()), "Chess Club").json()["community_id"]
    own_request = request(client, data.headers(mod), "Union Choir").json()["community_id"]

    by_owner = client.post(f"{A}/communities/{request_id}/approve", headers=data.headers(owner))
    assert by_owner.json() == {"error": "moderator_only"}
    by_student = client.post(
        f"{A}/communities/{request_id}/approve", headers=data.headers(data.student())
    )
    assert by_student.json() == {"error": "not_an_admin"}
    self_review = client.post(f"{A}/communities/{own_request}/approve", headers=data.headers(mod))
    assert self_review.json() == {"error": "cannot_review_own_request"}
    ghost = client.post(f"{A}/communities/999/approve", headers=data.headers(mod))
    assert ghost.json() == {"error": "community_not_found"}


def test_rejected_request_shows_the_reason_and_frees_the_name(
    client: TestClient, data: Data, push: FakePushSender
) -> None:
    mod = moderator(data)
    student = data.student()
    phone(data, student, "tok-student")
    headers = data.headers(student)
    community = request(client, headers, "Chess Club").json()["community_id"]

    rejected = client.post(
        f"{A}/communities/{community}/reject",
        json={"reason": "  Already exists as part of the Games Club "},
        headers=data.headers(mod),
    )

    assert rejected.status_code == 200
    assert rejected.json()["community"]["status"] == "rejected"
    assert rejected.json()["notified"] == 0
    assert push.sent == []
    mine = client.get("/api/v1/me/community-requests", headers=headers).json()["items"]
    assert (mine[0]["status"], mine[0]["reject_reason"]) == (
        "rejected",
        "Already exists as part of the Games Club",
    )
    # A rejected request is not listed in Explore and does not count to the limit.
    assert client.get("/api/v1/communities", headers=headers).json() == []
    assert request(client, headers, "Chess Club").status_code == 201

    twice = client.post(f"{A}/communities/{community}/reject", json={}, headers=data.headers(mod))
    assert twice.json() == {"error": "community_not_pending"}


def test_confirming_through_patch_is_an_approval_too(
    client: TestClient, data: Data, push: FakePushSender
) -> None:
    mod = moderator(data)
    owner = data.student()
    phone(data, owner, "tok-owner")
    community = data.community(owner, confirmed=False)

    response = client.patch(
        f"{A}/communities/{community}", json={"is_confirmed": True}, headers=data.headers(mod)
    )

    assert response.json()["status"] == "confirmed"
    assert [m.data["type"] for m in push.sent] == ["community_approved"]
    # Renaming a confirmed community sends nothing.
    client.patch(f"{A}/communities/{community}", json={"name": "New"}, headers=data.headers(mod))
    assert len(push.sent) == 1


# ---------- event cancelled ----------


def test_cancel_pushes_to_every_registered_student_and_the_page_says_cancelled(
    client: TestClient, data: Data, push: FakePushSender
) -> None:
    owner = data.student()
    community = data.community(owner)
    event = data.event(community, limit=1, title="Hackathon")
    confirmed, waiting, left, follower = (data.student() for _ in range(4))
    data.registration(confirmed, event)
    data.registration(waiting, event, "waiting_list")
    data.registration(left, event, "cancelled")
    data.subscribe(follower, community)
    for student, token in ((confirmed, "t1"), (waiting, "t2"), (left, "t3"), (follower, "t4")):
        phone(data, student, token)

    response = client.post(f"{A}/events/{event}/cancel", headers=data.headers(owner))

    assert response.status_code == 200
    assert response.json()["notified"] == 2
    assert response.json()["event"]["cancelled_at"] is not None
    assert sorted(m.token for m in push.sent) == ["t1", "t2"]
    assert {m.title for m in push.sent} == {"Event cancelled"}
    assert {m.data["type"] for m in push.sent} == {"event_cancelled"}

    headers = data.headers(confirmed)
    page = client.get(f"/api/v1/events/{event}", headers=headers).json()
    assert (page["status"], page["my_status"]) == ("cancelled", "confirmed")
    mine = client.get("/api/v1/me/registrations", headers=headers).json()["items"]
    assert [(e["title"], e["status"]) for e in mine] == [("Hackathon", "cancelled")]
    inbox = client.get("/api/v1/me/notifications", headers=headers).json()["items"]
    assert [n["kind"] for n in inbox] == ["event_cancelled"]

    register = client.post(f"/api/v1/events/{event}/registrations", headers=data.headers(left))
    assert (register.status_code, register.json()) == (409, {"error": "event_cancelled"})
    leave = client.delete(f"/api/v1/events/{event}/registrations", headers=headers)
    assert leave.json() == {"error": "event_cancelled"}


def test_an_event_that_started_cannot_be_cancelled(client: TestClient, data: Data) -> None:
    owner = data.student()
    now = datetime.now(UTC)
    event = data.event(
        data.community(owner),
        deadline=now - timedelta(days=2),
        starts_at=now - timedelta(hours=1),
    )
    response = client.post(f"{A}/events/{event}/cancel", headers=data.headers(owner))
    assert (response.status_code, response.json()) == (410, {"error": "event_started"})


# ---------- event rescheduled ----------


def test_reschedule_pushes_the_new_time_and_keeps_the_old_one(
    client: TestClient, data: Data, push: FakePushSender
) -> None:
    owner = data.student()
    starts = datetime(2031, 3, 10, 10, 0, tzinfo=UTC)
    event = data.event(data.community(owner), deadline=starts - timedelta(days=1), starts_at=starts)
    student = data.student()
    data.registration(student, event)
    phone(data, student, "tok")
    headers = data.headers(owner)

    title_only = client.patch(f"{A}/events/{event}", json={"title": "Renamed"}, headers=headers)
    assert title_only.json()["rescheduled_notified"] == 0
    assert push.sent == []

    moved = client.patch(
        f"{A}/events/{event}", json={"starts_at": "2031-03-12T15:00:00+00:00"}, headers=headers
    )

    assert moved.status_code == 200
    assert moved.json()["rescheduled_notified"] == 1
    assert moved.json()["promoted"] == 0
    assert moved.json()["event"]["previous_starts_at"] == "2031-03-10T10:00:00Z"
    # Display zone of the server (Asia/Almaty by default, UTC+5).
    assert [(m.title, m.body) for m in push.sent] == [
        ("Event moved", "Renamed: now 12 Mar, 20:00 (was 10 Mar, 15:00).")
    ]
    page = client.get(f"/api/v1/events/{event}", headers=data.headers(student)).json()
    assert page["previous_starts_at"] == "2031-03-10T10:00:00Z"
    assert page["status"] == "published"

    # Moving again re-sends the same notification row, never a second row.
    client.patch(
        f"{A}/events/{event}", json={"starts_at": "2031-03-13T15:00:00+00:00"}, headers=headers
    )
    assert len(push.sent) == 2
    rows = data.scalar(
        "SELECT COUNT(*) FROM notification WHERE event_id = %s AND kind = 'event_rescheduled'",
        event,
    )
    assert rows == 1

    past = client.patch(
        f"{A}/events/{event}", json={"starts_at": "2020-01-01T10:00:00+00:00"}, headers=headers
    )
    assert past.json() == {"error": "start_in_the_past"}


# ---------- announcements ----------


def test_announcements_show_open_events_of_every_confirmed_community(
    client: TestClient, data: Data
) -> None:
    owner = data.student()
    followed, other = data.community(owner), data.community(owner)
    pending = data.community(owner, confirmed=False)
    now = datetime.now(UTC)
    data.event(followed, title="Followed", deadline=now + timedelta(days=2))
    data.event(other, title="Not followed", deadline=now + timedelta(days=1))
    data.event(other, title="Closed", deadline=now - timedelta(hours=1))
    data.event(other, title="Cancelled", status="cancelled")
    data.event(pending, title="Of a request")
    student = data.student()
    data.subscribe(student, followed)

    response = client.get("/api/v1/events/announcements", headers=data.headers(student))

    assert response.status_code == 200
    assert [e["title"] for e in response.json()["items"]] == ["Not followed", "Followed"]
    assert client.get("/api/v1/events/announcements").status_code == 401


# ---------- migration 004 ----------


def test_migration_004_on_a_v3_database_equals_a_fresh_schema(db: psycopg.Connection) -> None:
    _load(db, "migrated", SCHEMA_V3.read_text(encoding="utf-8"))
    _load(db, "fresh", SCHEMA_V4.read_text(encoding="utf-8"))
    try:
        db.execute("SET search_path TO migrated")
        db.execute(
            "INSERT INTO student (email, full_name, password_hash) VALUES ('a@kbtu.kz', 'A', 'x')"
        )
        db.execute(
            "INSERT INTO community (name, owner_id, is_confirmed) VALUES "
            "('IT Club', 1, TRUE), ('Debate Society', 1, FALSE)"
        )
        db.execute(MIGRATION_004.read_text(encoding="utf-8"))
        rows = db.execute(
            "SELECT name, status, is_confirmed FROM community ORDER BY name"
        ).fetchall()
        db.execute("SET search_path TO public")

        assert [(r["name"], r["status"], r["is_confirmed"]) for r in rows] == [
            ("Debate Society", "pending", False),
            ("IT Club", "confirmed", True),
        ]
        assert _structure(db, "migrated") == _structure(db, "fresh")
    finally:
        db.execute("SET search_path TO public")
        db.execute("DROP SCHEMA migrated CASCADE")
        db.execute("DROP SCHEMA fresh CASCADE")
