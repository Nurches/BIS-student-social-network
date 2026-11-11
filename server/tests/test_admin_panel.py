"""Admin panel API (/api/v1/admin/...) and the /admin page."""

from datetime import UTC, datetime, timedelta

import psycopg
from fastapi.testclient import TestClient

from app.services.push import SendResult

from .conftest import Data, FakePushSender

A = "/api/v1/admin"


def moderator(data: Data, email: str = "union@kbtu.kz") -> int:
    student = data.student(email)
    data.conn.execute("UPDATE student SET is_moderator = TRUE WHERE student_id = %s", (student,))
    return student


def device(data: Data, student_id: int, token: str) -> None:
    data.conn.execute(
        "INSERT INTO device_token (student_id, token, platform) VALUES (%s, %s, 'ios')",
        (student_id, token),
    )


# ---------- access ----------


def test_plain_student_is_not_an_admin(client: TestClient, data: Data) -> None:
    student = data.student()
    response = client.get(f"{A}/me", headers=data.headers(student))
    assert response.status_code == 403
    assert response.json() == {"error": "not_an_admin"}
    assert client.get(f"{A}/overview").status_code == 401


def test_owner_sees_only_own_communities_and_events(client: TestClient, data: Data) -> None:
    owner, other = data.student(), data.student()
    mine = data.community(owner, name="Mine")
    theirs = data.community(other, name="Theirs")
    data.event(mine, title="My event")
    data.event(theirs, title="Their event")
    headers = data.headers(owner)

    me = client.get(f"{A}/me", headers=headers).json()
    assert me["is_moderator"] is False
    assert [c["name"] for c in me["communities"]] == ["Mine"]
    assert [c["name"] for c in client.get(f"{A}/communities", headers=headers).json()] == ["Mine"]
    titles = [e["title"] for e in client.get(f"{A}/events", headers=headers).json()["items"]]
    assert titles == ["My event"]


def test_owner_cannot_touch_another_communitys_event(client: TestClient, data: Data) -> None:
    owner, other = data.student(), data.student()
    data.community(owner)
    event = data.event(data.community(other))
    headers = data.headers(owner)

    for response in (
        client.patch(f"{A}/events/{event}", json={"title": "X"}, headers=headers),
        client.post(f"{A}/events/{event}/cancel", headers=headers),
        client.get(f"{A}/events/{event}/registrations", headers=headers),
        client.post(f"{A}/events/{event}/notify", headers=headers),
    ):
        assert response.status_code == 403
        assert response.json() == {"error": "not_your_community"}


def test_moderator_sees_everything(client: TestClient, data: Data) -> None:
    mod = moderator(data)
    a, b = data.student(), data.student()
    data.event(data.community(a))
    data.event(data.community(b, confirmed=False))
    headers = data.headers(mod)

    assert len(client.get(f"{A}/communities", headers=headers).json()) == 2
    assert len(client.get(f"{A}/events", headers=headers).json()["items"]) == 2
    overview = client.get(f"{A}/overview", headers=headers).json()
    assert overview["communities"] == 2
    assert overview["unconfirmed_communities"] == 1
    assert overview["students"] == 3


def test_owner_overview_hides_global_counts(client: TestClient, data: Data) -> None:
    owner, fan = data.student(), data.student()
    community = data.community(owner)
    data.subscribe(fan, community)
    event = data.event(community, limit=1)
    data.registration(fan, event)

    overview = client.get(f"{A}/overview", headers=data.headers(owner)).json()
    assert overview["students"] is None
    assert overview["devices"] is None
    assert overview["subscribers"] == 1
    assert overview["open_events"] == 1
    assert overview["confirmed_registrations"] == 1


# ---------- communities ----------


def test_moderator_creates_a_community_its_owner_can_publish_in(
    client: TestClient, data: Data, push: FakePushSender
) -> None:
    mod = moderator(data)
    owner = data.student("robotics@kbtu.kz")

    created = client.post(
        f"{A}/communities",
        json={"name": "Robotics Club", "description": "Drones", "owner_email": "ROBOTICS@kbtu.kz"},
        headers=data.headers(mod),
    )
    assert created.status_code == 201, created.text
    body = created.json()
    assert body["owner"]["student_id"] == owner
    assert body["is_confirmed"] is True
    assert body["subscriber_count"] == 0

    deadline = datetime.now(UTC) + timedelta(days=2)
    published = client.post(
        f"/api/v1/communities/{body['community_id']}/events",
        json={
            "title": "Drone race",
            "starts_at": (deadline + timedelta(days=1)).isoformat(),
            "registration_deadline": deadline.isoformat(),
            "participant_limit": 5,
        },
        headers=data.headers(owner),
    )
    assert published.status_code == 201


def test_create_community_errors(client: TestClient, data: Data) -> None:
    mod = moderator(data)
    owner = data.student("owner@kbtu.kz")
    data.community(owner, name="Chess")
    headers = data.headers(mod)

    taken = client.post(
        f"{A}/communities", json={"name": "Chess", "owner_email": "owner@kbtu.kz"}, headers=headers
    )
    assert taken.status_code == 409
    assert taken.json() == {"error": "community_name_taken"}

    nobody = client.post(
        f"{A}/communities", json={"name": "Go", "owner_email": "ghost@kbtu.kz"}, headers=headers
    )
    assert nobody.status_code == 404
    assert nobody.json() == {"error": "student_not_found"}

    by_owner = client.post(
        f"{A}/communities", json={"name": "Go", "owner_email": "owner@kbtu.kz"},
        headers=data.headers(owner),
    )  # fmt: skip
    assert by_owner.status_code == 403
    assert by_owner.json() == {"error": "moderator_only"}


def test_unconfirming_a_community_stops_publishing(client: TestClient, data: Data) -> None:
    mod = moderator(data)
    owner = data.student()
    community = data.community(owner)
    headers = data.headers(mod)

    response = client.patch(
        f"{A}/communities/{community}",
        json={"is_confirmed": False, "description": None, "name": "Renamed"},
        headers=headers,
    )
    assert response.status_code == 200
    assert response.json()["is_confirmed"] is False
    assert response.json()["name"] == "Renamed"
    assert response.json()["description"] is None

    deadline = datetime.now(UTC) + timedelta(days=2)
    refused = client.post(
        f"/api/v1/communities/{community}/events",
        json={
            "title": "X",
            "starts_at": (deadline + timedelta(days=1)).isoformat(),
            "registration_deadline": deadline.isoformat(),
            "participant_limit": 5,
        },
        headers=data.headers(owner),
    )
    assert refused.status_code == 403  # BR-01


def test_update_community_errors(client: TestClient, data: Data) -> None:
    mod = moderator(data)
    owner = data.student()
    first = data.community(owner, name="First")
    data.community(owner, name="Second")
    headers = data.headers(mod)

    assert client.patch(f"{A}/communities/999", json={}, headers=headers).status_code == 404
    taken = client.patch(f"{A}/communities/{first}", json={"name": "Second"}, headers=headers)
    assert taken.json() == {"error": "community_name_taken"}
    null_name = client.patch(f"{A}/communities/{first}", json={"name": None}, headers=headers)
    assert null_name.status_code == 422
    assert null_name.json()["error"] == "validation_failed"
    handed = client.patch(
        f"{A}/communities/{first}", json={"owner_email": "union@kbtu.kz"}, headers=headers
    )
    assert handed.json()["owner"]["student_id"] == mod


# ---------- events ----------


def test_event_list_counts_and_states(client: TestClient, data: Data) -> None:
    owner = data.student()
    community = data.community(owner)
    now = datetime.now(UTC)
    open_event = data.event(community, limit=1, title="Open")
    data.event(community, deadline=now - timedelta(hours=1), title="Closed")
    data.event(community, status="cancelled", title="Cancelled")
    first, second = data.student(), data.student()
    data.registration(first, open_event)
    data.registration(second, open_event, "waiting_list")

    items = client.get(f"{A}/events", headers=data.headers(owner)).json()["items"]
    by_title = {e["title"]: e for e in items}
    assert by_title["Open"]["state"] == "open"
    assert by_title["Open"]["confirmed_count"] == 1
    assert by_title["Open"]["waiting_count"] == 1
    assert by_title["Closed"]["state"] == "closed"
    assert by_title["Cancelled"]["state"] == "cancelled"

    only = client.get(
        f"{A}/events", params={"community_id": 999}, headers=data.headers(owner)
    ).json()
    assert only["items"] == []


def test_edit_event_fields(client: TestClient, data: Data) -> None:
    owner = data.student()
    event = data.event(data.community(owner))
    starts = datetime.now(UTC) + timedelta(days=10)

    response = client.patch(
        f"{A}/events/{event}",
        json={"title": "New title", "location": None, "starts_at": starts.isoformat()},
        headers=data.headers(owner),
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["event"]["title"] == "New title"
    assert body["event"]["location"] is None
    assert datetime.fromisoformat(body["event"]["starts_at"]) == starts
    assert body["promoted"] == 0


def test_edit_event_rules(client: TestClient, data: Data) -> None:
    owner = data.student()
    event = data.event(data.community(owner), limit=2)
    data.registration(data.student(), event)
    data.registration(data.student(), event)
    headers = data.headers(owner)
    now = datetime.now(UTC)

    def patch(body: dict) -> dict:
        response = client.patch(f"{A}/events/{event}", json=body, headers=headers)
        return {"status": response.status_code, **response.json()}

    assert patch({"participant_limit": 1}) == {"status": 409, "error": "limit_below_confirmed"}
    assert patch({"registration_deadline": (now - timedelta(hours=1)).isoformat()}) == {
        "status": 422,
        "error": "deadline_in_the_past",
    }
    assert patch({"registration_deadline": (now + timedelta(days=30)).isoformat()}) == {
        "status": 422,
        "error": "deadline_after_event_start",
    }
    assert patch({"starts_at": "2030-01-01T10:00:00"}) == {
        "status": 422,
        "error": "timestamp_without_offset",
    }
    assert patch({"title": None})["error"] == "validation_failed"


def test_larger_limit_promotes_the_waiting_list_in_order_with_pushes(
    client: TestClient, data: Data, push: FakePushSender
) -> None:
    owner = data.student()
    event = data.event(data.community(owner), limit=1)
    confirmed, first, second, third = (data.student() for _ in range(4))
    data.registration(confirmed, event)
    for student in (first, second, third):
        data.registration(student, event, "waiting_list")
    device(data, first, "tok-first")
    device(data, second, "tok-second")

    response = client.patch(
        f"{A}/events/{event}", json={"participant_limit": 3}, headers=data.headers(owner)
    )

    assert response.json()["promoted"] == 2
    assert response.json()["event"]["confirmed_count"] == 3
    assert response.json()["event"]["waiting_count"] == 1
    statuses = {
        r["student_id"]: r["status"]
        for r in data.conn.execute(
            "SELECT student_id, status FROM registration WHERE event_id = %s", (event,)
        ).fetchall()
    }
    assert statuses[third] == "waiting_list"
    assert statuses[first] == statuses[second] == "confirmed"
    assert sorted(m.token for m in push.sent) == ["tok-first", "tok-second"]
    assert {m.title for m in push.sent} == {"You got a place"}


def test_cancel_hides_the_event_from_students(client: TestClient, data: Data) -> None:
    owner, fan = data.student(), data.student()
    community = data.community(owner)
    data.subscribe(fan, community)
    event = data.event(community)
    headers = data.headers(owner)

    cancelled = client.post(f"{A}/events/{event}/cancel", headers=headers)
    assert cancelled.status_code == 200
    assert cancelled.json()["state"] == "cancelled"

    fan_headers = data.headers(fan)
    assert client.get("/api/v1/feed", headers=fan_headers).json()["items"] == []
    assert client.get(f"/api/v1/events/{event}", headers=fan_headers).status_code == 404

    again = client.post(f"{A}/events/{event}/cancel", headers=headers)
    assert again.json() == {"error": "event_cancelled"}
    edit = client.patch(f"{A}/events/{event}", json={"title": "X"}, headers=headers)
    assert edit.json() == {"error": "event_cancelled"}
    assert client.post(f"{A}/events/999/cancel", headers=headers).status_code == 404


def test_registrations_list_in_queue_order(client: TestClient, data: Data) -> None:
    owner = data.student()
    event = data.event(data.community(owner), limit=1)
    a, b, c, d = (data.student() for _ in range(4))
    data.registration(a, event)
    data.registration(b, event, "waiting_list")
    data.registration(c, event, "waiting_list")
    data.registration(d, event, "cancelled")

    body = client.get(f"{A}/events/{event}/registrations", headers=data.headers(owner)).json()

    assert body["event"]["event_id"] == event
    rows = [(r["student_id"], r["status"], r["position"]) for r in body["items"]]
    assert rows == [
        (a, "confirmed", None),
        (b, "waiting_list", 1),
        (c, "waiting_list", 2),
        (d, "cancelled", None),
    ]


# ---------- notifications and pushes ----------


def test_notify_again_reaches_new_subscribers_and_unsent_only(
    client: TestClient, data: Data, push: FakePushSender, db: psycopg.Connection
) -> None:
    owner, early, late = data.student(), data.student(), data.student()
    community = data.community(owner)
    event = data.event(community)
    data.subscribe(early, community)
    data.subscribe(late, community)
    device(data, early, "tok-early")
    device(data, late, "tok-late")
    # `early` was notified at publication and FCM accepted it; `late` followed afterwards.
    db.execute(
        "INSERT INTO notification (student_id, event_id, sent_at) VALUES (%s, %s, NOW())",
        (early, event),
    )

    response = client.post(f"{A}/events/{event}/notify", headers=data.headers(owner))

    assert response.json() == {"new_recipients": 1, "queued": 1}
    assert [m.token for m in push.sent] == ["tok-late"]
    log = client.get(
        f"{A}/notifications", params={"event_id": event}, headers=data.headers(owner)
    ).json()["items"]
    assert {(n["student_email"], n["sent_at"] is not None) for n in log} == {
        (data.scalar("SELECT email FROM student WHERE student_id = %s", early), True),
        (data.scalar("SELECT email FROM student WHERE student_id = %s", late), True),
    }


def test_notification_log_is_scoped(client: TestClient, data: Data, db: psycopg.Connection) -> None:
    owner, other, fan = data.student(), data.student(), data.student()
    mine = data.event(data.community(owner), title="Mine")
    theirs = data.event(data.community(other), title="Theirs")
    for event in (mine, theirs):
        db.execute("INSERT INTO notification (student_id, event_id) VALUES (%s, %s)", (fan, event))

    items = client.get(f"{A}/notifications", headers=data.headers(owner)).json()["items"]
    assert [n["event_title"] for n in items] == ["Mine"]
    assert items[0]["sent_at"] is None
    assert items[0]["devices"] == 0


def test_push_test_reaches_my_phones_and_drops_dead_tokens(
    client: TestClient, data: Data, push: FakePushSender
) -> None:
    owner = data.student()
    data.community(owner)
    device(data, owner, "tok-alive")
    device(data, owner, "tok-dead")
    push.results["tok-dead"] = SendResult.INVALID_TOKEN

    response = client.post(f"{A}/push-test", headers=data.headers(owner))

    assert response.json() == {
        "fcm_configured": True,
        "devices": 2,
        "sent": 1,
        "failed": 0,
        "removed": 1,
    }
    assert {m.data["type"] for m in push.sent} == {"test"}
    assert data.scalar("SELECT COUNT(*) FROM device_token") == 1


def test_push_test_without_phones(client: TestClient, data: Data, push: FakePushSender) -> None:
    owner = data.student()
    data.community(owner)
    body = client.post(f"{A}/push-test", headers=data.headers(owner)).json()
    assert body["devices"] == 0
    assert push.sent == []


# ---------- students ----------


def test_students_are_moderator_only_and_searchable(client: TestClient, data: Data) -> None:
    mod = moderator(data)
    owner = data.student("aru@kbtu.kz")
    data.community(owner)

    refused = client.get(f"{A}/students", headers=data.headers(owner))
    assert refused.json() == {"error": "moderator_only"}

    found = client.get(f"{A}/students", params={"q": "ARU"}, headers=data.headers(mod))
    items = found.json()["items"]
    assert [s["email"] for s in items] == ["aru@kbtu.kz"]
    assert items[0]["owned_communities"] == 1
    assert items[0]["is_locked"] is False


def test_unlock_lifts_the_lockout(client: TestClient, data: Data) -> None:
    mod = moderator(data)
    data.student("locked@kbtu.kz")
    headers = data.headers(mod)
    for _ in range(5):
        client.post(
            "/api/v1/auth/login", json={"email": "locked@kbtu.kz", "password": "wrong-password"}
        )
    locked = data.scalar("SELECT student_id FROM student WHERE email = 'locked@kbtu.kz'")
    listed = client.get(f"{A}/students", params={"q": "locked"}, headers=headers).json()
    assert listed["items"][0]["is_locked"] is True

    assert client.post(f"{A}/students/{locked}/unlock", headers=headers).status_code == 204
    assert client.post(f"{A}/students/999/unlock", headers=headers).status_code == 404
    login = client.post(
        "/api/v1/auth/login", json={"email": "locked@kbtu.kz", "password": "correct-horse-1"}
    )
    assert login.status_code == 200


def test_moderator_role(client: TestClient, data: Data) -> None:
    mod = moderator(data)
    student = data.student()
    headers = data.headers(mod)

    granted = client.put(
        f"{A}/students/{student}/moderator", json={"is_moderator": True}, headers=headers
    )
    assert granted.status_code == 204
    assert client.get(f"{A}/me", headers=data.headers(student)).json()["is_moderator"] is True

    own = client.put(f"{A}/students/{mod}/moderator", json={"is_moderator": False}, headers=headers)
    assert own.json() == {"error": "cannot_change_own_role"}
    ghost = client.put(f"{A}/students/999/moderator", json={"is_moderator": True}, headers=headers)
    assert ghost.json() == {"error": "student_not_found"}


# ---------- page ----------


def test_admin_page_is_served(client: TestClient) -> None:
    page = client.get("/admin")
    assert page.status_code == 200
    assert page.headers["content-type"].startswith("text/html")
    assert "<title>Qatys Admin</title>" in page.text
    assert '"/admin/me"' in page.text  # the page signs in through the admin API
