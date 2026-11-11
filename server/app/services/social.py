"""Communities, subscriptions and the student's own lists (MVP extension, Week 11).

Kept apart from services/events.py on purpose: the queries reuse its Event
SELECT, so every list shows the same server-computed `free_places`, `my_status`
and `waiting_position` as the feed (docs/api.md, "Event object").
"""

from ..db import Conn
from ..errors import ApiError
from .events import _EVENT_SELECT, _PAGE_COLUMNS  # one definition of the Event object

COMMUNITY_EVENTS_LIMIT = 50
NOTIFICATIONS_LIMIT = 50


def _require_community(conn: Conn, community_id: int) -> None:
    exists = conn.execute(
        "SELECT 1 FROM community WHERE community_id = %s", (community_id,)
    ).fetchone()
    if exists is None:
        raise ApiError(404, "community_not_found")


def list_communities(conn: Conn, student_id: int) -> list[dict]:
    """Every community, with the counts a student needs to decide to follow it."""
    return conn.execute(
        """
        SELECT c.community_id, c.name, c.description, c.is_confirmed,
               (SELECT COUNT(*) FROM subscription s
                WHERE s.community_id = c.community_id) AS subscriber_count,
               (SELECT COUNT(*) FROM event e
                WHERE e.community_id = c.community_id AND e.status = 'published'
                  AND e.registration_deadline > NOW()) AS upcoming_events,
               EXISTS (SELECT 1 FROM subscription s
                       WHERE s.community_id = c.community_id
                         AND s.student_id = %s) AS is_subscribed
        FROM community c
        ORDER BY c.name
        """,
        (student_id,),
    ).fetchall()


def subscribe(conn: Conn, student_id: int, community_id: int) -> None:
    """Idempotent: following twice is not an error."""
    _require_community(conn, community_id)
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
            WHERE e.status = 'published'
        )
        {_EVENT_SELECT}
        """,  # noqa: S608 — only fixed fragments are interpolated, values are bound
        {"student_id": student_id},
    ).fetchall()
    return {"items": rows}


def notifications(conn: Conn, student_id: int) -> dict:
    """The in-app inbox: the same rows the pushes were sent for (FR-01)."""
    rows = conn.execute(
        f"""
        SELECT n.notification_id, n.kind, n.event_id, e.title AS event_title,
               c.name AS community_name, n.created_at, n.is_read
        FROM notification n
        JOIN event e     ON e.event_id = n.event_id
        JOIN community c ON c.community_id = e.community_id
        WHERE n.student_id = %s AND e.status = 'published'
        ORDER BY n.created_at DESC, n.notification_id DESC
        LIMIT {NOTIFICATIONS_LIMIT}
        """,  # noqa: S608 — only a constant is interpolated
        (student_id,),
    ).fetchall()
    unread = conn.execute(
        "SELECT COUNT(*) AS n FROM notification n JOIN event e USING (event_id) "
        "WHERE n.student_id = %s AND n.is_read = FALSE AND e.status = 'published'",
        (student_id,),
    ).fetchone()
    return {"items": rows, "unread_count": unread["n"] if unread else 0}


def mark_notifications_read(conn: Conn, student_id: int) -> None:
    conn.execute(
        "UPDATE notification SET is_read = TRUE WHERE student_id = %s AND is_read = FALSE",
        (student_id,),
    )
