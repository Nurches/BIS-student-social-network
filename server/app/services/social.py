"""Communities, subscriptions and the student's own lists (MVP extension, Week 11).

Kept apart from services/events.py on purpose: the queries reuse its Event
SELECT, so every list shows the same server-computed `free_places`, `my_status`
and `waiting_position` as the feed (docs/api.md, "Event object").
"""

from psycopg import errors as pg_errors

from ..db import Conn
from ..errors import ApiError
from .events import _EVENT_SELECT, _PAGE_COLUMNS  # one definition of the Event object

COMMUNITY_EVENTS_LIMIT = 50
NOTIFICATIONS_LIMIT = 50
PENDING_REQUESTS_LIMIT = 3  # Week 12: against request spam (Akbota's threat list)


def _require_community(conn: Conn, community_id: int, *, confirmed: bool = False) -> None:
    exists = conn.execute(
        "SELECT 1 FROM community WHERE community_id = %s AND deleted_at IS NULL "
        "AND (NOT %s OR status = 'confirmed')",
        (community_id, confirmed),
    ).fetchone()
    if exists is None:
        raise ApiError(404, "community_not_found")


def list_communities(conn: Conn, student_id: int) -> list[dict]:
    """Confirmed communities, with the counts a student needs to decide to
    follow them, plus the caller's own pending request (v4). Another
    student's pending or rejected request is not shown."""
    return conn.execute(
        """
        SELECT c.community_id, c.name, c.description, c.is_confirmed, c.status,
               c.owner_id = %(me)s AS is_mine,
               (SELECT COUNT(*) FROM subscription s
                JOIN student st ON st.student_id = s.student_id
                               AND st.deleted_at IS NULL
                WHERE s.community_id = c.community_id) AS subscriber_count,
               (SELECT COUNT(*) FROM event e
                WHERE e.community_id = c.community_id AND e.status = 'published'
                  AND e.deleted_at IS NULL
                  AND e.registration_deadline > NOW()) AS upcoming_events,
               EXISTS (SELECT 1 FROM subscription s
                       WHERE s.community_id = c.community_id
                         AND s.student_id = %(me)s) AS is_subscribed
        FROM community c
        WHERE c.deleted_at IS NULL
          AND (c.status = 'confirmed' OR (c.status = 'pending' AND c.owner_id = %(me)s))
        ORDER BY c.name
        """,
        {"me": student_id},
    ).fetchall()


def subscribe(conn: Conn, student_id: int, community_id: int) -> None:
    """Idempotent: following twice is not an error. Only a confirmed
    community can be followed (a request has no events yet)."""
    _require_community(conn, community_id, confirmed=True)
    conn.execute(
        "INSERT INTO subscription (student_id, community_id) VALUES (%s, %s) "
        "ON CONFLICT (student_id, community_id) DO NOTHING",
        (student_id, community_id),
    )


def unsubscribe(conn: Conn, student_id: int, community_id: int) -> None:
    """Idempotent: unfollowing a community one does not follow is not an error."""
    _require_community(conn, community_id)
    conn.execute(
        "DELETE FROM subscription WHERE student_id = %s AND community_id = %s",
        (student_id, community_id),
    )


def community_events(conn: Conn, student_id: int, community_id: int) -> dict:
    """Open events of one community, also for a student who does not follow it."""
    _require_community(conn, community_id)
    rows = conn.execute(
        f"""
        WITH page AS (
            SELECT {_PAGE_COLUMNS}
            FROM event e
            JOIN community c ON c.community_id = e.community_id
            WHERE e.community_id = %(community_id)s
              AND e.status = 'published'
              AND e.deleted_at IS NULL
              AND e.registration_deadline > NOW()
            ORDER BY e.registration_deadline, e.event_id
            LIMIT {COMMUNITY_EVENTS_LIMIT}
        )
        {_EVENT_SELECT}
        """,  # noqa: S608 — only fixed fragments are interpolated, values are bound
        {"student_id": student_id, "community_id": community_id},
    ).fetchall()
    return {"items": rows}


def my_registrations(conn: Conn, student_id: int) -> dict:
    """Events the student is confirmed for or waiting for, past ones included,
    so the app can show "Upcoming" and "Past"."""
    rows = conn.execute(
        f"""
        WITH page AS (
            SELECT {_PAGE_COLUMNS}
            FROM event e
            JOIN community c    ON c.community_id = e.community_id
            JOIN registration r ON r.event_id = e.event_id
                               AND r.student_id = %(student_id)s
                               AND r.status IN ('confirmed', 'waiting_list')
            WHERE e.status IN ('published', 'cancelled')
              AND e.deleted_at IS NULL AND c.deleted_at IS NULL
        )
        {_EVENT_SELECT}
        """,  # noqa: S608 — only fixed fragments are interpolated, values are bound
        {"student_id": student_id},
    ).fetchall()
    return {"items": rows}


# The inbox shows a notification of a published event, an `event_cancelled`
# one of a cancelled event, and a `community_approved` one (no event).
_INBOX_FROM = """
FROM notification n
LEFT JOIN event e ON e.event_id = n.event_id
JOIN community c  ON c.community_id = COALESCE(e.community_id, n.community_id)
WHERE n.student_id = %s
  AND c.deleted_at IS NULL
  AND (n.event_id IS NULL
       OR (e.deleted_at IS NULL
           AND (e.status = 'published'
                OR (e.status = 'cancelled' AND n.kind = 'event_cancelled'))))
"""


def notifications(conn: Conn, student_id: int) -> dict:
    """The in-app inbox: the same rows the pushes were sent for (FR-01)."""
    rows = conn.execute(
        f"""
        SELECT n.notification_id, n.kind, n.event_id, c.community_id,
               e.title AS event_title, c.name AS community_name,
               e.starts_at, e.previous_starts_at, n.created_at, n.is_read
        {_INBOX_FROM}
        ORDER BY n.created_at DESC, n.notification_id DESC
        LIMIT {NOTIFICATIONS_LIMIT}
        """,
        (student_id,),
    ).fetchall()
    unread = conn.execute(
        f"SELECT COUNT(*) AS n {_INBOX_FROM} AND n.is_read = FALSE",
        (student_id,),
    ).fetchone()
    return {"items": rows, "unread_count": unread["n"] if unread else 0}


def mark_notifications_read(conn: Conn, student_id: int) -> None:
    conn.execute(
        "UPDATE notification SET is_read = TRUE WHERE student_id = %s AND is_read = FALSE",
        (student_id,),
    )


# ---------- community requests (Week 12) ----------

_REQUEST_COLUMNS = """
community_id, name, description, status, reject_reason, created_at, reviewed_at
"""


_INSERT_REQUEST = f"""
INSERT INTO community (name, description, owner_id, status)
VALUES (%s, %s, %s, 'pending') RETURNING {_REQUEST_COLUMNS}
"""  # noqa: S608 — constants only


def request_community(conn: Conn, student_id: int, *, name: str, description: str | None) -> dict:
    """Any student asks the Student Union for a community; it starts
    `pending` with the student as owner. A moderator approves it in /admin.

    At most 3 pending requests per student. The student row is locked first,
    so two requests sent at once cannot both pass the count.
    """
    with conn.transaction():
        conn.execute("SELECT 1 FROM student WHERE student_id = %s FOR UPDATE", (student_id,))
        pending = conn.execute(
            "SELECT COUNT(*) AS n FROM community "
            "WHERE owner_id = %s AND status = 'pending' AND deleted_at IS NULL",
            (student_id,),
        ).fetchone()
        assert pending is not None
        if pending["n"] >= PENDING_REQUESTS_LIMIT:
            raise ApiError(409, "too_many_pending_requests")
        try:
            with conn.transaction():
                row = conn.execute(
                    _INSERT_REQUEST, (name, description or None, student_id)
                ).fetchone()
        except pg_errors.UniqueViolation as exc:
            raise ApiError(409, "community_name_taken") from exc
        assert row is not None
        return row


def my_community_requests(conn: Conn, student_id: int) -> dict:
    """Every community the student asked for (or owns), newest first."""
    rows = conn.execute(
        f"SELECT {_REQUEST_COLUMNS} FROM community "  # noqa: S608 — a constant
        "WHERE owner_id = %s AND deleted_at IS NULL "
        "ORDER BY created_at DESC, community_id DESC",
        (student_id,),
    ).fetchall()
    return {"items": rows, "pending_limit": PENDING_REQUESTS_LIMIT}
