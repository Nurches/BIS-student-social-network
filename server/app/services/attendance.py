"""Week 13 (schema v5), the student's side of attendance: the ticket of a
confirmed registration (FR-06) and the rating after the event (FR-07).

The organiser's side — check-in at the door, "Finish now", the feedback list
and the analytics — is in services/admin_panel.py, next to the other rules of
who may manage an event.
"""

from datetime import UTC, datetime, timedelta

from psycopg import errors as pg_errors

from ..db import Conn
from ..errors import ApiError
from . import tickets
from .events import EVENT_END_SQL

# FR-06: the door opens 3 hours before the start and closes 2 hours after the end.
CHECK_IN_OPENS_BEFORE = timedelta(hours=3)
CHECK_IN_CLOSES_AFTER = timedelta(hours=2)


def check_in_window(starts_at: datetime, ends_at: datetime) -> tuple[datetime, datetime]:
    return starts_at - CHECK_IN_OPENS_BEFORE, ends_at + CHECK_IN_CLOSES_AFTER


def _event(conn: Conn, event_id: int) -> dict:
    """A published or cancelled event a student can see; 404 otherwise."""
    row = conn.execute(
        f"""
        SELECT e.event_id, e.status, e.starts_at, {EVENT_END_SQL} AS ends_at
        FROM event e
        JOIN community c ON c.community_id = e.community_id
        WHERE e.event_id = %s AND e.status IN ('published', 'cancelled')
          AND e.deleted_at IS NULL AND c.deleted_at IS NULL
        """,  # noqa: S608 — a fixed fragment only, values are bound
        (event_id,),
    ).fetchone()
    if row is None:
        raise ApiError(404, "event_not_found")
    return row


def ticket(conn: Conn, secret: str, student_id: int, event_id: int) -> dict:
    """The QR payload and the 6-character code of the caller's confirmed place.
    A waiting-list student has no ticket yet: the place is not theirs."""
    event = _event(conn, event_id)
    mine = conn.execute(
        "SELECT registration_id, status, checked_in_at FROM registration "
        "WHERE event_id = %s AND student_id = %s AND status <> 'cancelled'",
        (event_id, student_id),
    ).fetchone()
    if mine is None:
        raise ApiError(404, "not_registered")
    if event["status"] == "cancelled":
        raise ApiError(409, "event_cancelled")
    if mine["status"] != "confirmed":
        raise ApiError(409, "ticket_waiting_list")
    opens, closes = check_in_window(event["starts_at"], event["ends_at"])
    registration_id = mine["registration_id"]
    return {
        "event_id": event_id,
        "registration_id": registration_id,
        "code": tickets.code(secret, registration_id),
        "qr": tickets.qr_payload(secret, registration_id),
        "checked_in_at": mine["checked_in_at"],
        "check_in_opens_at": opens,
        "check_in_closes_at": closes,
    }


def send_feedback(
    conn: Conn, student_id: int, event_id: int, *, rating: int, comment: str | None
) -> dict:
    """FR-07: only a student who was checked in, only after the event ended,
    only once. The rating cannot be changed afterwards."""
    with conn.transaction():
        event = _event(conn, event_id)
        if event["status"] == "cancelled":
            raise ApiError(409, "event_cancelled")
        mine = conn.execute(
            "SELECT status, checked_in_at FROM registration "
            "WHERE event_id = %s AND student_id = %s",
            (event_id, student_id),
        ).fetchone()
        if mine is None or mine["checked_in_at"] is None or mine["status"] != "confirmed":
            raise ApiError(403, "not_checked_in")
        if event["ends_at"] > datetime.now(UTC):
            raise ApiError(409, "event_not_finished")
        try:
            with conn.transaction():
                row = conn.execute(
                    "INSERT INTO event_feedback (event_id, student_id, rating, comment) "
                    "VALUES (%s, %s, %s, %s) RETURNING rating, comment, created_at",
                    (event_id, student_id, rating, comment or None),
                ).fetchone()
        except pg_errors.UniqueViolation as exc:
            raise ApiError(409, "feedback_already_sent") from exc
        assert row is not None
        return {"event_id": event_id, **row}
