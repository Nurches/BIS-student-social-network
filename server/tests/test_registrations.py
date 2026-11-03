"""POST and DELETE /events/{id}/registrations (FR-03, TC-02, TC-03)."""

from datetime import UTC, datetime, timedelta

from .conftest import Data, FakePushSender


def register(data: Data, event_id: int, headers: dict[str, str]):
    return data.client.post(f"/api/v1/events/{event_id}/registrations", headers=headers)


def cancel(data: Data, event_id: int, headers: dict[str, str]):
    return data.client.delete(f"/api/v1/events/{event_id}/registrations", headers=headers)


def status_of(data: Data, student_id: int, event_id: int) -> object:
    return data.scalar(
        "SELECT status FROM registration WHERE student_id = %s AND event_id = %s",
        student_id,
        event_id,
    )


def test_tc02_registration_is_confirmed_while_places_are_free(data: Data) -> None:
    me = data.student()
    event = data.event(data.community(data.student()), limit=2)

    response = register(data, event, data.headers(me))

    assert response.status_code == 201
    assert response.json()["status"] == "confirmed"
    assert isinstance(response.json()["registration_id"], int)
    assert status_of(data, me, event) == "confirmed"


def test_tc03_full_event_puts_the_student_on_the_waiting_list(data: Data) -> None:
    event = data.event(data.community(data.student()), limit=1)
    data.registration(data.student(), event)
    data.registration(data.student(), event, "waiting_list")
    me = data.student()

    response = register(data, event, data.headers(me))

    assert response.status_code == 200
    assert response.json() == {"status": "waiting_list", "position": 2}


def test_registration_after_the_deadline_is_refused(data: Data) -> None:
    event = data.event(
        data.community(data.student()), deadline=datetime.now(UTC) - timedelta(seconds=1)
    )

    response = register(data, event, data.headers(data.student()))

    assert response.status_code == 410
    assert response.json() == {"error": "deadline_passed"}


def test_second_registration_is_a_conflict(data: Data) -> None:
    event = data.event(data.community(data.student()))
    headers = data.headers(data.student())
    register(data, event, headers)

    response = register(data, event, headers)

    assert response.status_code == 409
    assert response.json() == {"error": "already_registered"}


def test_unknown_or_draft_event_is_not_found(data: Data) -> None:
    draft = data.event(data.community(data.student()), status="draft")
    headers = data.headers(data.student())

    assert register(data, draft, headers).json() == {"error": "event_not_found"}
    assert register(data, 999_999, headers).status_code == 404


def test_register_cancel_register_again_reuses_the_row(data: Data) -> None:
    """The v1 bug: a second INSERT hit uq_registration."""
    me = data.student()
    event = data.event(data.community(data.student()))
    headers = data.headers(me)

    assert register(data, event, headers).status_code == 201
    assert cancel(data, event, headers).json() == {"status": "cancelled"}
    again = register(data, event, headers)

    assert again.status_code == 201
    rows = data.scalar("SELECT COUNT(*) FROM registration WHERE student_id = %s", me)
    assert rows == 1
    assert status_of(data, me, event) == "confirmed"


def test_rejoining_the_waiting_list_goes_to_the_end_of_the_queue(data: Data) -> None:
    event = data.event(data.community(data.student()), limit=1)
    data.registration(data.student(), event)
    me, other = data.student(), data.student()
    my_headers = data.headers(me)
    register(data, event, my_headers)  # position 1
    register(data, event, data.headers(other))  # position 2

    cancel(data, event, my_headers)
    response = register(data, event, my_headers)

    assert response.json() == {"status": "waiting_list", "position": 2}


def test_cancel_promotes_the_first_waiting_student_and_notifies_them(
    data: Data, push: FakePushSender
) -> None:
    event = data.event(data.community(data.student()), limit=1, title="CV clinic")
    me = data.student()
    first, second = data.student(), data.student()
    data.registration(me, event)
    data.registration(first, event, "waiting_list")
    data.registration(second, event, "waiting_list")
    data.conn.execute(
        "INSERT INTO device_token (student_id, token) VALUES (%s, 'first-phone')", (first,)
    )

    response = cancel(data, event, data.headers(me))

    assert response.json() == {"status": "cancelled"}  # does not reveal who was promoted
    assert status_of(data, me, event) == "cancelled"
    assert status_of(data, first, event) == "confirmed"
    assert status_of(data, second, event) == "waiting_list"
    assert (
        data.scalar(
            "SELECT COUNT(*) FROM notification WHERE student_id = %s AND event_id = %s "
            "AND kind = 'waiting_list_promoted' AND sent_at IS NOT NULL",
            first,
            event,
        )
        == 1
    )
    assert [m.data for m in push.sent] == [
        {"type": "waiting_list_promoted", "event_id": str(event)}
    ]
    assert push.sent[0].token == "first-phone"


def test_leaving_the_waiting_list_promotes_nobody(data: Data, push: FakePushSender) -> None:
    event = data.event(data.community(data.student()), limit=1)
    data.registration(data.student(), event)
    me, other = data.student(), data.student()
    data.registration(me, event, "waiting_list")
    data.registration(other, event, "waiting_list")

    cancel(data, event, data.headers(me))

    assert status_of(data, other, event) == "waiting_list"
    assert push.sent == []


def test_cancel_without_a_registration_is_not_found(data: Data) -> None:
    event = data.event(data.community(data.student()))

    response = cancel(data, event, data.headers(data.student()))

    assert response.status_code == 404
    assert response.json() == {"error": "not_registered"}


def test_cancel_after_the_event_started_is_refused(data: Data) -> None:
    now = datetime.now(UTC)
    event = data.event(
        data.community(data.student()),
        deadline=now - timedelta(hours=2),
        starts_at=now - timedelta(hours=1),
    )
    me = data.student()
    data.registration(me, event)

    response = cancel(data, event, data.headers(me))

    assert response.status_code == 410
    assert response.json() == {"error": "event_started"}


def test_direct_api_calls_cannot_overbook(data: Data) -> None:
    """Brief §10: bypassing the UI still enforces the limit."""
    event = data.event(data.community(data.student()), limit=3)
    answers = [
        register(data, event, data.headers(data.student())).json()["status"] for _ in range(6)
    ]

    assert answers.count("confirmed") == 3
    assert answers.count("waiting_list") == 3
    assert (
        data.scalar(
            "SELECT COUNT(*) FROM registration WHERE event_id = %s AND status = 'confirmed'", event
        )
        == 3
    )
