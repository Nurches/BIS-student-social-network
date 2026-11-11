"""MVP extension: communities and following, a community's events, my
registrations and the notification inbox (docs/api.md)."""

from datetime import UTC, datetime, timedelta

from fastapi.testclient import TestClient

from .conftest import Data


def _setup(data: Data) -> dict:
    owner = data.student()
    it = data.community(owner, name="IT Club")
    sport = data.community(owner, name="Sports Club")
    unconfirmed = data.community(owner, confirmed=False, name="Debate Society")
    student = data.student()
    data.subscribe(student, it)
    return {"owner": owner, "it": it, "sport": sport, "debate": unconfirmed, "me": student}


def test_communities_list_counts_and_follow_state(data: Data, client: TestClient) -> None:
    ids = _setup(data)
    other = data.student()
    data.subscribe(other, ids["sport"])
    data.event(ids["sport"], title="Futsal cup")
    data.event(ids["sport"], title="Old", deadline=datetime.now(UTC) - timedelta(hours=1))

    response = client.get("/api/v1/communities", headers=data.headers(ids["me"]))

    assert response.status_code == 200
    by_name = {c["name"]: c for c in response.json()}
    assert list(by_name) == ["Debate Society", "IT Club", "Sports Club"]  # by name
    assert by_name["IT Club"]["is_subscribed"] is True
    assert by_name["Sports Club"] | {"community_id": 0} == {
        "community_id": 0,
        "name": "Sports Club",
        "description": None,
        "is_confirmed": True,
        "subscriber_count": 1,
        "upcoming_events": 1,  # the closed one does not count
        "is_subscribed": False,
    }
    assert by_name["Debate Society"]["is_confirmed"] is False


def test_follow_adds_the_events_to_the_feed_and_unfollow_removes_them(
    data: Data, client: TestClient
) -> None:
    ids = _setup(data)
    data.event(ids["sport"], title="Futsal cup")
    headers = data.headers(ids["me"])
    url = f"/api/v1/communities/{ids['sport']}/subscription"

    def feed_titles() -> list[str]:
        return [e["title"] for e in client.get("/api/v1/feed", headers=headers).json()["items"]]

    assert feed_titles() == []
    assert client.put(url, headers=headers).status_code == 204
    assert client.put(url, headers=headers).status_code == 204  # idempotent
    assert feed_titles() == ["Futsal cup"]
    assert (
        data.scalar(
            "SELECT COUNT(*) FROM subscription WHERE student_id = %s AND community_id = %s",
            ids["me"],
            ids["sport"],
        )
        == 1
    )

    assert client.delete(url, headers=headers).status_code == 204
    assert client.delete(url, headers=headers).status_code == 204  # idempotent
    assert feed_titles() == []


def test_a_new_follower_gets_the_push_for_the_next_event(data: Data, client: TestClient) -> None:
    ids = _setup(data)
    client.put(f"/api/v1/communities/{ids['sport']}/subscription", headers=data.headers(ids["me"]))
    deadline = datetime.now(UTC) + timedelta(days=2)

    published = client.post(
        f"/api/v1/communities/{ids['sport']}/events",
        json={
            "title": "Volleyball night",
            "starts_at": (deadline + timedelta(days=1)).isoformat(),
            "registration_deadline": deadline.isoformat(),
            "participant_limit": 12,
        },
        headers=data.headers(ids["owner"]),
    )

    assert published.status_code == 201
    assert data.scalar("SELECT student_id FROM notification") == ids["me"]


def test_unknown_community_is_404_everywhere(data: Data, client: TestClient) -> None:
    headers = data.headers(data.student())
    for method, path in [
        ("PUT", "/api/v1/communities/999/subscription"),
        ("DELETE", "/api/v1/communities/999/subscription"),
        ("GET", "/api/v1/communities/999/events"),
    ]:
        response = client.request(method, path, headers=headers)
        assert response.status_code == 404, path
        assert response.json() == {"error": "community_not_found"}


def test_community_events_are_open_published_events_even_when_not_followed(
    data: Data, client: TestClient
) -> None:
    ids = _setup(data)
    now = datetime.now(UTC)
    later = data.event(ids["sport"], title="Later", deadline=now + timedelta(days=5))
    sooner = data.event(ids["sport"], title="Sooner", deadline=now + timedelta(days=1), limit=2)
    data.event(ids["sport"], title="Closed", deadline=now - timedelta(hours=1))
    data.event(ids["sport"], title="Draft", status="draft")
    data.registration(ids["me"], sooner)

    response = client.get(
        f"/api/v1/communities/{ids['sport']}/events", headers=data.headers(ids["me"])
    )

    items = response.json()["items"]
    assert [e["event_id"] for e in items] == [sooner, later]
    assert items[0]["my_status"] == "confirmed"
    assert items[0]["free_places"] == 1
    assert items[0]["community_name"] == "Sports Club"


def test_my_registrations_lists_confirmed_and_waiting_but_not_cancelled(
    data: Data, client: TestClient
) -> None:
    ids = _setup(data)
    now = datetime.now(UTC)
    confirmed = data.event(ids["it"], title="Confirmed")
    waiting = data.event(ids["sport"], title="Waiting", limit=1)
    cancelled = data.event(ids["it"], title="Cancelled")
    past = data.event(
        ids["it"], title="Past", deadline=now - timedelta(days=3), starts_at=now - timedelta(days=1)
    )
    data.registration(data.student(), waiting)
    data.registration(ids["me"], confirmed)
    data.registration(ids["me"], waiting, "waiting_list")
    data.registration(ids["me"], cancelled, "cancelled")
    data.registration(ids["me"], past)

    items = client.get("/api/v1/me/registrations", headers=data.headers(ids["me"])).json()["items"]

    by_title = {e["title"]: e for e in items}
    assert set(by_title) == {"Confirmed", "Waiting", "Past"}
    assert by_title["Waiting"]["my_status"] == "waiting_list"
    assert by_title["Waiting"]["waiting_position"] == 1
    assert by_title["Past"]["my_status"] == "confirmed"


def test_inbox_lists_my_notifications_newest_first_and_marks_them_read(
    data: Data, client: TestClient
) -> None:
    ids = _setup(data)
    first = data.event(ids["it"], title="First")
    second = data.event(ids["sport"], title="Second")
    draft = data.event(ids["it"], title="Draft", status="draft")
    for event_id, kind, hours in [
        (first, "event_published", 3),
        (second, "waiting_list_promoted", 1),
        (draft, "event_published", 0),  # not published: not shown (C09)
    ]:
        data.conn.execute(
            "INSERT INTO notification (student_id, event_id, kind, created_at) "
            "VALUES (%s, %s, %s, NOW() - %s * INTERVAL '1 hour')",
            (ids["me"], event_id, kind, hours),
        )
    data.conn.execute(  # someone else's notification
        "INSERT INTO notification (student_id, event_id) VALUES (%s, %s)", (ids["owner"], first)
    )
    headers = data.headers(ids["me"])

    inbox = client.get("/api/v1/me/notifications", headers=headers).json()

    assert inbox["unread_count"] == 2
    assert [(n["event_title"], n["kind"], n["is_read"]) for n in inbox["items"]] == [
        ("Second", "waiting_list_promoted", False),
        ("First", "event_published", False),
    ]
    assert inbox["items"][0]["community_name"] == "Sports Club"
    assert inbox["items"][0]["created_at"].endswith(("Z", "+00:00"))

    assert client.post("/api/v1/me/notifications/read", headers=headers).status_code == 204
    again = client.get("/api/v1/me/notifications", headers=headers).json()
    assert again["unread_count"] == 0
    assert all(n["is_read"] for n in again["items"])
    owner_unread = data.scalar(
        "SELECT COUNT(*) FROM notification WHERE student_id = %s AND NOT is_read", ids["owner"]
    )
    assert owner_unread == 1


def test_everything_needs_a_token(client: TestClient) -> None:
    for method, path in [
        ("GET", "/api/v1/communities"),
        ("PUT", "/api/v1/communities/1/subscription"),
        ("GET", "/api/v1/communities/1/events"),
        ("GET", "/api/v1/me/registrations"),
        ("GET", "/api/v1/me/notifications"),
        ("POST", "/api/v1/me/notifications/read"),
    ]:
        assert client.request(method, path).status_code == 401, path
