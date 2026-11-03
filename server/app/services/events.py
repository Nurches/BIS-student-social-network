"""Feed, event detail, registration (FR-03) and publishing (FR-01, FR-02, BR-01)."""

import base64
import binascii
from datetime import UTC, datetime

from ..db import Conn
from ..errors import ApiError

# Server-computed fields of the Event object, for the rows of a CTE named
# `page` (one SQL statement for the whole page, no query per event — NFR-01).
# `mine` is the caller's own active registration.
_EVENT_SELECT = """
SELECT p.event_id, p.community_id, p.community_name, p.title, p.description, p.location,
       p.starts_at, p.registration_deadline, p.participant_limit,
       GREATEST(p.participant_limit - (
           SELECT COUNT(*) FROM registration r
           WHERE r.event_id = p.event_id AND r.status = 'confirmed'
       ), 0) AS free_places,
       mine.status AS my_status,
       CASE WHEN mine.status = 'waiting_list' THEN (
           SELECT COUNT(*) FROM registration w
           WHERE w.event_id = p.event_id AND w.status = 'waiting_list'
             AND (w.updated_at, w.registration_id) <= (mine.updated_at, mine.registration_id)
       ) END AS waiting_position
FROM page p
LEFT JOIN registration mine
       ON mine.event_id = p.event_id
      AND mine.student_id = %(student_id)s
      AND mine.status <> 'cancelled'
ORDER BY p.registration_deadline, p.event_id
"""

_PAGE_COLUMNS = """
e.event_id, e.community_id, c.name AS community_name, e.title, e.description, e.location,
e.starts_at, e.registration_deadline, e.participant_limit
"""


# ---------- feed ----------


def encode_cursor(deadline: datetime, event_id: int) -> str:
    raw = f"{deadline.astimezone(UTC).isoformat()}|{event_id}".encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def decode_cursor(cursor: str) -> tuple[datetime, int]:
    try:
        raw = base64.urlsafe_b64decode(cursor + "=" * (-len(cursor) % 4)).decode()
        deadline_text, event_id_text = raw.rsplit("|", 1)
        deadline = datetime.fromisoformat(deadline_text)
        event_id = int(event_id_text)
    except (binascii.Error, UnicodeDecodeError, ValueError) as exc:
        raise ApiError(422, "invalid_cursor") from exc
    if deadline.tzinfo is None:
        raise ApiError(422, "invalid_cursor")
    return deadline, event_id


def feed(conn: Conn, student_id: int, *, limit: int, cursor: str | None) -> dict:
    after = decode_cursor(cursor) if cursor else None
    params = {
        "student_id": student_id,
        "fetch": limit + 1,  # one extra row says whether a next page exists
        "after_deadline": after[0] if after else None,
        "after_id": after[1] if after else None,
    }
    rows = conn.execute(
        f"""
        WITH page AS (
            SELECT {_PAGE_COLUMNS}
            FROM event e
            JOIN community c    ON c.community_id = e.community_id
            JOIN subscription s ON s.community_id = e.community_id
                               AND s.student_id = %(student_id)s
            WHERE e.status = 'published'
              AND e.registration_deadline > NOW()
              AND (%(after_deadline)s::timestamptz IS NULL
                   OR (e.registration_deadline, e.event_id)
                      > (%(after_deadline)s::timestamptz, %(after_id)s::integer))
            ORDER BY e.registration_deadline, e.event_id
            LIMIT %(fetch)s
        )
        {_EVENT_SELECT}
        """,  # noqa: S608 — only fixed fragments are interpolated, values are bound
        params,
    ).fetchall()

    items, more = rows[:limit], len(rows) > limit
    last = items[-1] if items else None
    next_cursor = (
        encode_cursor(last["registration_deadline"], last["event_id"]) if more and last else None
    )
    return {"items": items, "next_cursor": next_cursor}


def event_detail(conn: Conn, student_id: int, event_id: int) -> dict:
    """Any published event, also from an unfollowed community or past its
    deadline (the app renders it as closed, FR-02)."""
    row = conn.execute(
        f"""
        WITH page AS (
            SELECT {_PAGE_COLUMNS}
            FROM event e
            JOIN community c ON c.community_id = e.community_id
            WHERE e.event_id = %(event_id)s AND e.status = 'published'
        )
        {_EVENT_SELECT}
        """,  # noqa: S608 — only fixed fragments are interpolated, values are bound
        {"student_id": student_id, "event_id": event_id},
    ).fetchone()
    if row is None:
        raise ApiError(404, "event_not_found")
    return row


# ---------- registration (FR-03) ----------


def _lock_published_event(conn: Conn, event_id: int) -> dict:
    # FOR UPDATE: two students taking the last place wait for each other here,
    # so the second one reads the count after the first one has committed.
    event = conn.execute(
        """
        SELECT event_id, participant_limit, registration_deadline, starts_at, status
        FROM event WHERE event_id = %s FOR UPDATE
        """,
        (event_id,),
    ).fetchone()
    if event is None or event["status"] != "published":
        raise ApiError(404, "event_not_found")
    return event


def _confirmed_count(conn: Conn, event_id: int) -> int:
    row = conn.execute(
        "SELECT COUNT(*) AS n FROM registration WHERE event_id = %s AND status = 'confirmed'",
        (event_id,),
    ).fetchone()
    assert row is not None
    return row["n"]


def _waiting_position(conn: Conn, registration_id: int) -> int:
    row = conn.execute(
        """
        SELECT COUNT(*) AS n
        FROM registration w
        JOIN registration mine ON mine.registration_id = %s
        WHERE w.event_id = mine.event_id AND w.status = 'waiting_list'
          AND (w.updated_at, w.registration_id) <= (mine.updated_at, mine.registration_id)
        """,
        (registration_id,),
    ).fetchone()
    assert row is not None
    return row["n"]


def register(conn: Conn, student_id: int, event_id: int) -> dict:
    """`{"status": "confirmed", "registration_id"}` or
    `{"status": "waiting_list", "position"}` — the SQL of docs/api.md.

    Queue times use clock_timestamp(), not NOW(): NOW() is the start of the
    transaction, so a student who waited for the lock would be stamped
    earlier than the one who got the place first, and both would read the
    same waiting-list position.
    """
    with conn.transaction():
        event = _lock_published_event(conn, event_id)
        if event["registration_deadline"] <= datetime.now(UTC):
            raise ApiError(410, "deadline_passed")

        mine = conn.execute(
            "SELECT registration_id, status FROM registration "
            "WHERE event_id = %s AND student_id = %s",
            (event_id, student_id),
        ).fetchone()
        if mine is not None and mine["status"] in ("confirmed", "waiting_list"):
            raise ApiError(409, "already_registered")

        full = _confirmed_count(conn, event_id) >= event["participant_limit"]
        new_status = "waiting_list" if full else "confirmed"

        if mine is None:
            row = conn.execute(
                "INSERT INTO registration (student_id, event_id, status, created_at, updated_at) "
                "VALUES (%s, %s, %s, clock_timestamp(), clock_timestamp()) "
                "RETURNING registration_id",
                (student_id, event_id, new_status),
            ).fetchone()
        else:
            # Registered before and cancelled: reuse the row, never a second one.
            row = conn.execute(
                "UPDATE registration SET status = %s, updated_at = clock_timestamp() "
                "WHERE registration_id = %s RETURNING registration_id",
                (new_status, mine["registration_id"]),
            ).fetchone()
        assert row is not None
        registration_id = row["registration_id"]

        if new_status == "confirmed":
            return {"status": "confirmed", "registration_id": registration_id}
        return {"status": "waiting_list", "position": _waiting_position(conn, registration_id)}


def cancel(conn: Conn, student_id: int, event_id: int) -> int | None:
    """Cancels the caller's registration. Returns the id of the notification
    for the student promoted from the waiting list, if anyone was promoted."""
    with conn.transaction():
        event = _lock_published_event(conn, event_id)
        mine = conn.execute(
            "SELECT registration_id, status FROM registration "
            "WHERE event_id = %s AND student_id = %s AND status <> 'cancelled'",
            (event_id, student_id),
        ).fetchone()
        if mine is None:
            raise ApiError(404, "not_registered")
        if event["starts_at"] <= datetime.now(UTC):
            # TODO(confirm): default chosen in M0, not yet confirmed by the team.
            raise ApiError(410, "event_started")

        conn.execute(
            "UPDATE registration SET status = 'cancelled', updated_at = clock_timestamp() "
            "WHERE registration_id = %s",
            (mine["registration_id"],),
        )
        if mine["status"] != "confirmed":
            return None
        if _confirmed_count(conn, event_id) >= event["participant_limit"]:
            return None

        promoted = conn.execute(
            """
            UPDATE registration SET status = 'confirmed', updated_at = clock_timestamp()
            WHERE registration_id = (
                SELECT registration_id FROM registration
                WHERE event_id = %s AND status = 'waiting_list'
                ORDER BY updated_at, registration_id
                LIMIT 1
                FOR UPDATE
            )
            RETURNING student_id
            """,
            (event_id,),
        ).fetchone()
        if promoted is None:
            return None

        notification = conn.execute(
            """
            INSERT INTO notification (student_id, event_id, kind)
            VALUES (%s, %s, 'waiting_list_promoted')
            ON CONFLICT (student_id, event_id, kind)
            DO UPDATE SET sent_at = NULL, is_read = FALSE, created_at = NOW()
            RETURNING notification_id
            """,
            (promoted["student_id"], event_id),
        ).fetchone()
        assert notification is not None
        return notification["notification_id"]


# ---------- publishing (FR-01, FR-02, BR-01) ----------


def publish(
    conn: Conn,
    student_id: int,
    community_id: int,
    *,
    title: str,
    description: str | None,
    location: str | None,
    starts_at: datetime,
    registration_deadline: datetime,
    participant_limit: int,
) -> tuple[int, list[int]]:
    """Returns the new event id and the ids of the notifications to push."""
    with conn.transaction():
        community = conn.execute(
            "SELECT owner_id, is_confirmed FROM community WHERE community_id = %s",
            (community_id,),
        ).fetchone()
        if community is None:
            raise ApiError(404, "community_not_found")
        if community["owner_id"] != student_id or not community["is_confirmed"]:
            raise ApiError(403, "not_a_confirmed_admin")
        if registration_deadline <= datetime.now(UTC):
            raise ApiError(422, "deadline_in_the_past")
        if registration_deadline > starts_at:
            raise ApiError(422, "deadline_after_event_start")

        row = conn.execute(
            """
            INSERT INTO event (community_id, title, description, location, starts_at,
                               registration_deadline, participant_limit, status)
            VALUES (%s, %s, %s, %s, %s, %s, %s, 'published')
            RETURNING event_id
            """,
            (
                community_id,
                title,
                description,
                location,
                starts_at,
                registration_deadline,
                participant_limit,
            ),
        ).fetchone()
        assert row is not None
        event_id = row["event_id"]
        return event_id, create_publish_notifications(conn, event_id)


def create_publish_notifications(conn: Conn, event_id: int) -> list[int]:
    """One `event_published` row per subscriber. Safe to run again for the
    same event: existing rows are skipped, so nobody is notified twice."""
    rows = conn.execute(
        """
        INSERT INTO notification (student_id, event_id, kind)
        SELECT s.student_id, e.event_id, 'event_published'
        FROM event e
        JOIN subscription s ON s.community_id = e.community_id
        WHERE e.event_id = %s
        ON CONFLICT (student_id, event_id, kind) DO NOTHING
        RETURNING notification_id
        """,
        (event_id,),
    ).fetchall()
    return [r["notification_id"] for r in rows]
