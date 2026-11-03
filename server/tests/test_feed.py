"""GET /feed and GET /events/{id} (NFR-01, FR-02, FR-03)."""

from datetime import UTC, datetime, timedelta

from .conftest import Data

FEED = "/api/v1/feed"


def test_pagination_returns_every_event_exactly_once(data: Data) -> None:
    """M2 acceptance: 45 events, several sharing a deadline, pages of 10."""
    me = data.student()
    admin = data.student()
    club = data.community(admin)
    data.subscribe(me, club)
    base = datetime.now(UTC) + timedelta(days=1)
    expected = {
        # Groups of three share one deadline: the cursor must break ties by event_id.
        data.event(club, deadline=base + timedelta(hours=i // 3))
        for i in range(45)
    }
    headers = data.headers(me)

    seen: list[int] = []
    cursor = None
    pages = 0
    while True:
        params = {"limit": 10, **({"cursor": cursor} if cursor else {})}
        body = data.client.get(FEED, params=params, headers=headers).json()
        seen += [item["event_id"] for item in body["items"]]
        pages += 1
        cursor = body["next_cursor"]
        if cursor is None:
            break

    assert pages == 5
    assert len(seen) == len(set(seen)) == 45
    assert set(seen) == expected


def test_new_event_published_between_pages_is_neither_skipped_nor_repeated(data: Data) -> None:
    me = data.student()
    club = data.community(data.student())
    data.subscribe(me, club)
    base = datetime.now(UTC) + timedelta(days=1)
    for i in range(4):
        data.event(club, deadline=base + timedelta(hours=i))
    headers = data.headers(me)

    first = data.client.get(FEED, params={"limit": 2}, headers=headers).json()
    # An earlier deadline than the cursor: with OFFSET this would shift every row.
    data.event(club, deadline=base - timedelta(minutes=30))
    second = data.client.get(
        FEED, params={"limit": 2, "cursor": first["next_cursor"]}, headers=headers
    ).json()

    first_ids = [e["event_id"] for e in first["items"]]
    second_ids = [e["event_id"] for e in second["items"]]
    assert not set(first_ids) & set(second_ids)
    assert len(second_ids) == 2


def test_feed_shows_only_published_open_events_of_followed_communities(data: Data) -> None:
    me = data.student()
    admin = data.student()
    followed = data.community(admin)
    other = data.community(admin)
    data.subscribe(me, followed)
    now = datetime.now(UTC)
    visible = data.event(followed, title="Visible")
    data.event(followed, status="draft")
    data.event(followed, status="cancelled")
    data.event(followed, deadline=now - timedelta(minutes=1))
    data.event(other, title="Not followed")

    body = data.client.get(FEED, headers=data.headers(me)).json()

    assert [e["event_id"] for e in body["items"]] == [visible]
    assert body["next_cursor"] is None


def test_feed_is_ordered_by_deadline(data: Data) -> None:
    me = data.student()
    club = data.community(data.student())
    data.subscribe(me, club)
    now = datetime.now(UTC)
    late = data.event(club, deadline=now + timedelta(days=9))
    soon = data.event(club, deadline=now + timedelta(days=1))

    body = data.client.get(FEED, headers=data.headers(me)).json()

    assert [e["event_id"] for e in body["items"]] == [soon, late]


def test_event_object_matches_the_contract(data: Data) -> None:
    me = data.student()
    admin = data.student()
    club = data.community(admin, name="IT Club")
    data.subscribe(me, club)
    event = data.event(club, limit=2, title="CV clinic")
    data.registration(data.student(), event, "confirmed")
    data.registration(data.student(), event, "confirmed")
    data.registration(data.student(), event, "waiting_list")
    data.registration(me, event, "waiting_list")

    item = data.client.get(FEED, headers=data.headers(me)).json()["items"][0]

    assert set(item) == {
        "event_id",
        "community_id",
        "community_name",
        "title",
        "description",
        "location",
        "starts_at",
        "registration_deadline",
        "participant_limit",
        "free_places",
        "my_status",
        "waiting_position",
    }
    assert item["community_name"] == "IT Club"
    assert item["free_places"] == 0
    assert item["my_status"] == "waiting_list"
    assert item["waiting_position"] == 2
    # ISO 8601 with an offset, so every phone shows the right local time.
    parsed = datetime.fromisoformat(item["registration_deadline"])
    assert parsed.tzinfo is not None


def test_cancelled_registration_is_reported_as_null(data: Data) -> None:
    me = data.student()
    club = data.community(data.student())
    data.subscribe(me, club)
    event = data.event(club)
    data.registration(me, event, "cancelled")

    item = data.client.get(FEED, headers=data.headers(me)).json()["items"][0]

    assert item["my_status"] is None
    assert item["waiting_position"] is None
    assert item["free_places"] == 30


def test_invalid_cursor_and_limit_are_rejected(data: Data) -> None:
    headers = data.headers(data.student())

    bad_cursor = data.client.get(FEED, params={"cursor": "not-a-cursor"}, headers=headers)
    naive = data.client.get(
        FEED, params={"cursor": "MjAyNi0xMS0yMFQxMDowMDowMHwx"}, headers=headers
    )  # "2026-11-20T10:00:00|1": no offset
    too_big = data.client.get(FEED, params={"limit": 51}, headers=headers)

    assert bad_cursor.json() == {"error": "invalid_cursor"}
    assert naive.json() == {"error": "invalid_cursor"}
    assert too_big.status_code == 422
    assert too_big.json()["error"] == "validation_failed"


def test_event_detail_returns_any_published_event(data: Data) -> None:
    """Also unfollowed and past-deadline ones: the app renders them as closed."""
    me = data.student()
    club = data.community(data.student())
    closed = data.event(club, deadline=datetime.now(UTC) - timedelta(days=1))
    headers = data.headers(me)

    response = data.client.get(f"/api/v1/events/{closed}", headers=headers)

    assert response.status_code == 200
    assert response.json()["event_id"] == closed


def test_event_detail_hides_drafts_and_unknown_ids(data: Data) -> None:
    club = data.community(data.student())
    draft = data.event(club, status="draft")
    headers = data.headers(data.student())

    for event_id in (draft, 999_999):
        response = data.client.get(f"/api/v1/events/{event_id}", headers=headers)
        assert response.status_code == 404
        assert response.json() == {"error": "event_not_found"}
