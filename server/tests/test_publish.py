"""POST /communities/{id}/events and push delivery (FR-01, FR-02, BR-01)."""

from datetime import UTC, datetime, timedelta

from app.db import create_pool
from app.services import events
from app.services import push as push_service
from app.services.push import SendResult

from .conftest import Data, FakePushSender


def body(**overrides: object) -> dict:
    now = datetime.now(UTC)
    return {
        "title": "Career Day",
        "description": "Meet 12 companies",
        "location": "Main hall",
        "registration_deadline": (now + timedelta(days=1)).isoformat(),
        "starts_at": (now + timedelta(days=2)).isoformat(),
        "participant_limit": 2,
        **overrides,
    }


def publish(data: Data, community_id: int, headers: dict[str, str], **overrides: object):
    return data.client.post(
        f"/api/v1/communities/{community_id}/events", json=body(**overrides), headers=headers
    )


def test_publish_notifies_every_subscriber_once(data: Data, push: FakePushSender) -> None:
    admin = data.student()
    club = data.community(admin, name="Career Center")
    subscribers = [data.student() for _ in range(3)]
    for s in subscribers:
        data.subscribe(s, club)
    data.student()  # not subscribed
    data.conn.execute(
        "INSERT INTO device_token (student_id, token) VALUES (%s, 'phone-a'), (%s, 'phone-b')",
        (subscribers[0], subscribers[1]),
    )

    response = publish(data, club, data.headers(admin))

    assert response.status_code == 201
    event_id = response.json()["event_id"]
    assert response.json() == {"event_id": event_id, "status": "published"}
    assert (
        data.scalar(
            "SELECT COUNT(*) FROM notification WHERE event_id = %s AND kind = 'event_published'",
            event_id,
        )
        == 3
    )
    assert sorted(m.token for m in push.sent) == ["phone-a", "phone-b"]
    message = push.sent[0]
    assert message.title == "Career Day"
    assert message.body.startswith("Career Center · register by ")
    assert message.data == {"type": "event_published", "event_id": str(event_id)}
    # Delivered rows get sent_at; the student without a phone keeps NULL.
    assert (
        data.scalar(
            "SELECT COUNT(*) FROM notification WHERE event_id = %s AND sent_at IS NOT NULL",
            event_id,
        )
        == 2
    )


def test_running_the_fan_out_twice_creates_no_duplicates(data: Data) -> None:
    """Duplicate notifications (promised for Week 10): a retry is harmless."""
    admin = data.student()
    club = data.community(admin)
    for _ in range(3):
        data.subscribe(data.student(), club)
    event = data.event(club)

    first = events.create_publish_notifications(data.conn, event)
    second = events.create_publish_notifications(data.conn, event)

    assert len(first) == 3
    assert second == []
    assert data.scalar("SELECT COUNT(*) FROM notification WHERE event_id = %s", event) == 3


def test_fr02_deadline_in_the_past_is_rejected(data: Data) -> None:
    admin = data.student()
    club = data.community(admin)
    past = (datetime.now(UTC) - timedelta(minutes=1)).isoformat()

    response = publish(data, club, data.headers(admin), registration_deadline=past)

    assert response.status_code == 422
    assert response.json() == {"error": "deadline_in_the_past"}
    assert data.scalar("SELECT COUNT(*) FROM event") == 0


def test_deadline_after_the_start_is_rejected(data: Data) -> None:
    admin = data.student()
    club = data.community(admin)
    now = datetime.now(UTC)

    response = publish(
        data,
        club,
        data.headers(admin),
        registration_deadline=(now + timedelta(days=3)).isoformat(),
        starts_at=(now + timedelta(days=2)).isoformat(),
    )

    assert response.json() == {"error": "deadline_after_event_start"}


def test_br01_only_the_confirmed_owner_may_publish(data: Data) -> None:
    owner = data.student()
    club = data.community(owner)
    unconfirmed = data.community(owner, confirmed=False)
    student = data.student()

    by_student = publish(data, club, data.headers(student))
    unconfirmed_owner = publish(data, unconfirmed, data.headers(owner))

    for response in (by_student, unconfirmed_owner):
        assert response.status_code == 403
        assert response.json() == {"error": "not_a_confirmed_admin"}


def test_unknown_community_is_not_found(data: Data) -> None:
    response = publish(data, 999_999, data.headers(data.student()))
    assert response.status_code == 404
    assert response.json() == {"error": "community_not_found"}


def test_timestamp_without_offset_is_rejected(data: Data) -> None:
    admin = data.student()
    club = data.community(admin)

    response = publish(data, club, data.headers(admin), starts_at="2026-12-01T10:00:00")

    assert response.status_code == 422
    assert response.json() == {"error": "timestamp_without_offset"}


def test_dead_tokens_are_deleted_and_failures_leave_sent_at_empty(
    data: Data, push: FakePushSender, settings
) -> None:
    admin = data.student()
    club = data.community(admin)
    a, b = data.student(), data.student()
    data.subscribe(a, club)
    data.subscribe(b, club)
    data.conn.execute(
        "INSERT INTO device_token (student_id, token) VALUES (%s, 'dead'), (%s, 'flaky')", (a, b)
    )
    push.results = {"dead": SendResult.INVALID_TOKEN, "flaky": SendResult.FAILED}

    response = publish(data, club, data.headers(admin))
    event_id = response.json()["event_id"]

    assert data.scalar("SELECT COUNT(*) FROM device_token WHERE token = 'dead'") == 0
    assert data.scalar("SELECT COUNT(*) FROM device_token WHERE token = 'flaky'") == 1
    assert (
        data.scalar(
            "SELECT COUNT(*) FROM notification WHERE event_id = %s AND sent_at IS NULL", event_id
        )
        == 2
    )

    # A later retry delivers only what is still unsent.
    retry = FakePushSender()
    ids = [
        r["notification_id"]
        for r in data.conn.execute(
            "SELECT notification_id FROM notification WHERE event_id = %s", (event_id,)
        ).fetchall()
    ]
    with create_pool(settings.database_url) as pool:
        push_service.deliver(pool, retry, ids, settings)
    assert [m.token for m in retry.sent] == ["flaky"]
