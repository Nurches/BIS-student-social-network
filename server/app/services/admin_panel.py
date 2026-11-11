"""The admin panel at /admin: communities, events, participants, pushes, students.

Two kinds of admin, both read from the database on every request:

* a **moderator** of the Student Union (`student.is_moderator`) sees and manages
  everything, creates and confirms communities (BR-01) and manages students;
* a **community owner** sees and manages only the communities they own and
  their events.

Anyone else gets 403 `not_an_admin`. Publishing itself stays the endpoint of
FR-01/FR-02 (`POST /communities/{id}/events`, services/events.py), so BR-01 is
checked in one place only.

The schema is not changed: there is no notification kind for a cancelled
event, so cancelling hides the event from students without a push.
TODO(confirm): an `event_cancelled` push needs a new `notification.kind`.
"""

from dataclasses import dataclass
from datetime import UTC, datetime

from psycopg import errors as pg_errors

from ..db import Conn
from ..errors import ApiError
from .events import create_publish_notifications
from .push import LoggingPushSender, PushMessage, PushSender, SendResult

EVENTS_LIMIT = 300
NOTIFICATIONS_LIMIT = 200
STUDENTS_LIMIT = 300

TEST_PUSH_TITLE = "Qatys test push"
TEST_PUSH_BODY = "Pushes reach this phone. Sent from the admin panel."


@dataclass(frozen=True)
class Admin:
    student_id: int
    email: str
    full_name: str
    is_moderator: bool


def access(conn: Conn, student_id: int) -> Admin:
    """403 `not_an_admin` unless a moderator or the owner of a community."""
    row = conn.execute(
        """
        SELECT s.student_id, s.email, s.full_name, s.is_moderator,
               EXISTS (SELECT 1 FROM community c WHERE c.owner_id = s.student_id) AS owns
        FROM student s WHERE s.student_id = %s
        """,
        (student_id,),
    ).fetchone()
    if row is None or not (row["is_moderator"] or row["owns"]):
        raise ApiError(403, "not_an_admin")
    return Admin(row["student_id"], row["email"], row["full_name"], row["is_moderator"])


def _require_moderator(admin: Admin) -> None:
    if not admin.is_moderator:
        raise ApiError(403, "moderator_only")


def _scope(admin: Admin) -> dict:
    """Parameters of the `_IN_SCOPE` condition on a community aliased `c`."""
    return {"is_moderator": admin.is_moderator, "me": admin.student_id}


_IN_SCOPE = "(%(is_moderator)s OR c.owner_id = %(me)s)"


# ---------- who am I, overview ----------


def me(conn: Conn, admin: Admin) -> dict:
    communities = conn.execute(
        "SELECT community_id, name, is_confirmed FROM community WHERE owner_id = %s ORDER BY name",
        (admin.student_id,),
    ).fetchall()
    return {
        "student_id": admin.student_id,
        "email": admin.email,
        "full_name": admin.full_name,
        "is_moderator": admin.is_moderator,
        "communities": communities,
    }


def overview(conn: Conn, admin: Admin) -> dict:
    row = conn.execute(
        f"""
        WITH c AS (SELECT * FROM community c WHERE {_IN_SCOPE}),
             e AS (SELECT e.* FROM event e JOIN c USING (community_id))
        SELECT
            (SELECT COUNT(*) FROM c) AS communities,
            (SELECT COUNT(*) FROM c WHERE NOT c.is_confirmed) AS unconfirmed_communities,
            (SELECT COUNT(DISTINCT s.student_id) FROM subscription s
             JOIN c USING (community_id)) AS subscribers,
            (SELECT COUNT(*) FROM e WHERE e.status = 'published'
                AND e.registration_deadline > NOW()) AS open_events,
            (SELECT COUNT(*) FROM e WHERE e.status = 'published') AS published_events,
            (SELECT COUNT(*) FROM e WHERE e.status = 'cancelled') AS cancelled_events,
            (SELECT COUNT(*) FROM registration r JOIN e USING (event_id)
             WHERE r.status = 'confirmed' AND e.status = 'published') AS confirmed_registrations,
            (SELECT COUNT(*) FROM registration r JOIN e USING (event_id)
             WHERE r.status = 'waiting_list' AND e.status = 'published') AS waiting_registrations,
            (SELECT COUNT(*) FROM notification n JOIN e USING (event_id)) AS notifications,
            (SELECT COUNT(*) FROM notification n JOIN e USING (event_id)
             WHERE n.sent_at IS NOT NULL) AS notifications_sent
        """,  # noqa: S608 — only a fixed fragment is interpolated, values are bound
        _scope(admin),
    ).fetchone()
    assert row is not None
    result = dict(row)
    result["notifications_unsent"] = result["notifications"] - result["notifications_sent"]
    result["students"] = result["devices"] = None
    if admin.is_moderator:
        totals = conn.execute(
            "SELECT (SELECT COUNT(*) FROM student) AS students, "
            "(SELECT COUNT(*) FROM device_token) AS devices"
        ).fetchone()
        assert totals is not None
        result.update(totals)
    return result


# ---------- communities ----------

_COMMUNITY_SELECT = """
SELECT c.community_id, c.name, c.description, c.is_confirmed, c.created_at,
       json_build_object('student_id', o.student_id, 'email', o.email,
                         'full_name', o.full_name) AS owner,
       (SELECT COUNT(*) FROM subscription s
        WHERE s.community_id = c.community_id) AS subscriber_count,
       (SELECT COUNT(*) FROM event e
        WHERE e.community_id = c.community_id AND e.status = 'published') AS published_events,
       (SELECT COUNT(*) FROM event e
        WHERE e.community_id = c.community_id AND e.status = 'published'
          AND e.registration_deadline > NOW()) AS open_events
FROM community c
JOIN student o ON o.student_id = c.owner_id
"""


def list_communities(conn: Conn, admin: Admin) -> list[dict]:
    return conn.execute(
        f"{_COMMUNITY_SELECT} WHERE {_IN_SCOPE} ORDER BY c.name",
        _scope(admin),
    ).fetchall()


def _find_community(conn: Conn, community_id: int) -> dict | None:
    return conn.execute(
        f"{_COMMUNITY_SELECT} WHERE c.community_id = %s", (community_id,)
    ).fetchone()


def _community(conn: Conn, community_id: int) -> dict:
    row = _find_community(conn, community_id)
    if row is None:
        raise ApiError(404, "community_not_found")
    return row


def _student_id_by_email(conn: Conn, email: str) -> int:
    row = conn.execute(
        "SELECT student_id FROM student WHERE email = %s", (email.strip().lower(),)
    ).fetchone()
    if row is None:
        raise ApiError(404, "student_not_found")
    return row["student_id"]


def create_community(
    conn: Conn,
    admin: Admin,
    *,
    name: str,
    description: str | None,
    owner_email: str,
    is_confirmed: bool,
) -> dict:
    """Moderator only. The owner is the one account that may publish (BR-01)."""
    _require_moderator(admin)
    with conn.transaction():
        owner_id = _student_id_by_email(conn, owner_email)
        try:
            with conn.transaction():
                row = conn.execute(
                    "INSERT INTO community (name, description, owner_id, is_confirmed) "
                    "VALUES (%s, %s, %s, %s) RETURNING community_id",
                    (name, description or None, owner_id, is_confirmed),
                ).fetchone()
        except pg_errors.UniqueViolation as exc:
            raise ApiError(409, "community_name_taken") from exc
        assert row is not None
        created = _find_community(conn, row["community_id"])
        assert created is not None
        return created


def update_community(conn: Conn, admin: Admin, community_id: int, changes: dict) -> dict:
    """Moderator only: rename, describe, hand over to another owner, confirm or
    withdraw the confirmation (an unconfirmed community cannot publish, BR-01)."""
    _require_moderator(admin)
    with conn.transaction():
        _community(conn, community_id)
        columns: dict[str, object] = {}
        if "name" in changes:
            columns["name"] = changes["name"]
        if "description" in changes:
            columns["description"] = changes["description"] or None
        if "is_confirmed" in changes:
            columns["is_confirmed"] = changes["is_confirmed"]
        if "owner_email" in changes:
            columns["owner_id"] = _student_id_by_email(conn, changes["owner_email"])
        if columns:
            assignments = ", ".join(f"{column} = %s" for column in columns)
            try:
                with conn.transaction():
                    conn.execute(
                        f"UPDATE community SET {assignments} WHERE community_id = %s",  # noqa: S608 — fixed column names only
                        (*columns.values(), community_id),
                    )
            except pg_errors.UniqueViolation as exc:
                raise ApiError(409, "community_name_taken") from exc
        return _community(conn, community_id)


# ---------- events ----------

_EVENT_SELECT = """
SELECT e.event_id, e.community_id, c.name AS community_name, e.title, e.description,
       e.location, e.starts_at, e.registration_deadline, e.participant_limit, e.status,
       e.created_at,
       CASE
           WHEN e.status <> 'published' THEN e.status
           WHEN e.starts_at <= NOW() THEN 'finished'
           WHEN e.registration_deadline <= NOW() THEN 'closed'
           ELSE 'open'
       END AS state,
       (SELECT COUNT(*) FROM registration r
        WHERE r.event_id = e.event_id AND r.status = 'confirmed') AS confirmed_count,
       (SELECT COUNT(*) FROM registration r
        WHERE r.event_id = e.event_id AND r.status = 'waiting_list') AS waiting_count,
       (SELECT COUNT(*) FROM notification n WHERE n.event_id = e.event_id) AS notified_count,
       (SELECT COUNT(*) FROM notification n
        WHERE n.event_id = e.event_id AND n.sent_at IS NOT NULL) AS sent_count
FROM event e
JOIN community c ON c.community_id = e.community_id
"""


def list_events(conn: Conn, admin: Admin, community_id: int | None) -> dict:
    """Every status, past ones included: newest deadline first."""
    rows = conn.execute(
        f"""
        {_EVENT_SELECT}
        WHERE {_IN_SCOPE}
          AND (%(community_id)s::integer IS NULL OR e.community_id = %(community_id)s)
        ORDER BY e.registration_deadline DESC, e.event_id DESC
        LIMIT {EVENTS_LIMIT}
        """,
        {**_scope(admin), "community_id": community_id},
    ).fetchall()
    return {"items": rows}


def _event(conn: Conn, event_id: int) -> dict:
    row = conn.execute(f"{_EVENT_SELECT} WHERE e.event_id = %s", (event_id,)).fetchone()
    if row is None:
        raise ApiError(404, "event_not_found")
    return row


def _managed_event(conn: Conn, admin: Admin, event_id: int, *, lock: bool = False) -> dict:
    """The event row (locked for a change) if the caller may manage it."""
    row = conn.execute(
        f"""
        SELECT e.event_id, e.status, e.starts_at, e.registration_deadline,
               e.participant_limit, c.owner_id
        FROM event e JOIN community c ON c.community_id = e.community_id
        WHERE e.event_id = %s {"FOR UPDATE OF e" if lock else ""}
        """,  # noqa: S608 — a fixed fragment only
        (event_id,),
    ).fetchone()
    if row is None:
        raise ApiError(404, "event_not_found")
    if not admin.is_moderator and row["owner_id"] != admin.student_id:
        raise ApiError(403, "not_your_community")
    return row


_EDITABLE_EVENT_FIELDS = (
    "title",
    "description",
    "location",
    "starts_at",
    "registration_deadline",
    "participant_limit",
)


def update_event(conn: Conn, admin: Admin, event_id: int, changes: dict) -> tuple[dict, list[int]]:
    """Edits a published event. Returns it and the notifications to push.

    FR-02 holds for a moved deadline: it must be in the future and not after
    the start. A limit below the confirmed count is refused (nobody loses a
    place); a larger limit moves students up from the waiting list in queue
    order, each with a `waiting_list_promoted` push, as a cancellation does.
    """
    with conn.transaction():
        event = _managed_event(conn, admin, event_id, lock=True)
        if event["status"] == "cancelled":
            raise ApiError(409, "event_cancelled")

        deadline = changes.get("registration_deadline", event["registration_deadline"])
        starts_at = changes.get("starts_at", event["starts_at"])
        limit = changes.get("participant_limit", event["participant_limit"])
        if deadline != event["registration_deadline"] and deadline <= datetime.now(UTC):
            raise ApiError(422, "deadline_in_the_past")
        if deadline > starts_at:
            raise ApiError(422, "deadline_after_event_start")

        confirmed = conn.execute(
            "SELECT COUNT(*) AS n FROM registration WHERE event_id = %s AND status = 'confirmed'",
            (event_id,),
        ).fetchone()
        assert confirmed is not None
        if limit < confirmed["n"]:
            raise ApiError(409, "limit_below_confirmed")

        columns = {name: changes[name] for name in _EDITABLE_EVENT_FIELDS if name in changes}
        if columns:
            assignments = ", ".join(f"{column} = %s" for column in columns)
            conn.execute(
                f"UPDATE event SET {assignments} WHERE event_id = %s",  # noqa: S608 — fixed column names only
                (*columns.values(), event_id),
            )

        notification_ids: list[int] = []
        free = limit - confirmed["n"]
        if free > 0:
            promoted = conn.execute(
                """
                UPDATE registration SET status = 'confirmed', updated_at = clock_timestamp()
                WHERE registration_id IN (
                    SELECT registration_id FROM registration
                    WHERE event_id = %s AND status = 'waiting_list'
                    ORDER BY updated_at, registration_id
                    LIMIT %s
                    FOR UPDATE
                )
                RETURNING student_id
                """,
                (event_id, free),
            ).fetchall()
            for student in promoted:
                row = conn.execute(
                    """
                    INSERT INTO notification (student_id, event_id, kind)
                    VALUES (%s, %s, 'waiting_list_promoted')
                    ON CONFLICT (student_id, event_id, kind)
                    DO UPDATE SET sent_at = NULL, is_read = FALSE, created_at = NOW()
                    RETURNING notification_id
                    """,
                    (student["student_id"], event_id),
                ).fetchone()
                assert row is not None
                notification_ids.append(row["notification_id"])
        return _event(conn, event_id), notification_ids


def cancel_event(conn: Conn, admin: Admin, event_id: int) -> dict:
    """Hides the event from the feed, the event page, "My events" and the
    inbox. Registrations are kept as they were, for the record."""
    with conn.transaction():
        event = _managed_event(conn, admin, event_id, lock=True)
        if event["status"] == "cancelled":
            raise ApiError(409, "event_cancelled")
        conn.execute("UPDATE event SET status = 'cancelled' WHERE event_id = %s", (event_id,))
        return _event(conn, event_id)


def notify_again(conn: Conn, admin: Admin, event_id: int) -> tuple[int, list[int]]:
    """Notifies subscribers who followed after publication, and sends again
    every notification of the event FCM has not accepted yet (for example a
    student who had no phone signed in). Nobody gets a second push for a
    notification already delivered."""
    with conn.transaction():
        event = _managed_event(conn, admin, event_id)
        if event["status"] == "cancelled":
            raise ApiError(409, "event_cancelled")
        new = create_publish_notifications(conn, event_id)
        unsent = conn.execute(
            "SELECT notification_id FROM notification WHERE event_id = %s AND sent_at IS NULL",
            (event_id,),
        ).fetchall()
    return len(new), sorted({r["notification_id"] for r in unsent})


def registrations(conn: Conn, admin: Admin, event_id: int) -> dict:
    _managed_event(conn, admin, event_id)
    rows = conn.execute(
        """
        SELECT r.registration_id, s.student_id, s.email, s.full_name, r.status,
               CASE WHEN r.status = 'waiting_list' THEN
                   ROW_NUMBER() OVER (PARTITION BY r.status
                                      ORDER BY r.updated_at, r.registration_id)
               END AS position,
               r.created_at, r.updated_at
        FROM registration r
        JOIN student s ON s.student_id = r.student_id
        WHERE r.event_id = %s
        ORDER BY CASE r.status WHEN 'confirmed' THEN 0 WHEN 'waiting_list' THEN 1 ELSE 2 END,
                 r.updated_at, r.registration_id
        """,
        (event_id,),
    ).fetchall()
    return {"event": _event(conn, event_id), "items": rows}


# ---------- notifications and pushes ----------


def notifications(conn: Conn, admin: Admin, event_id: int | None) -> dict:
    """The delivery log: newest first, `sent_at` empty until FCM accepts."""
    rows = conn.execute(
        f"""
        SELECT n.notification_id, n.kind, n.event_id, e.title AS event_title,
               c.name AS community_name, s.email AS student_email,
               s.full_name AS student_name,
               (SELECT COUNT(*) FROM device_token d
                WHERE d.student_id = n.student_id) AS devices,
               n.created_at, n.sent_at, n.is_read
        FROM notification n
        JOIN event e     ON e.event_id = n.event_id
        JOIN community c ON c.community_id = e.community_id
        JOIN student s   ON s.student_id = n.student_id
        WHERE {_IN_SCOPE}
          AND (%(event_id)s::integer IS NULL OR n.event_id = %(event_id)s)
        ORDER BY n.created_at DESC, n.notification_id DESC
        LIMIT {NOTIFICATIONS_LIMIT}
        """,  # noqa: S608 — only fixed fragments are interpolated, values are bound
        {**_scope(admin), "event_id": event_id},
    ).fetchall()
    return {"items": rows}


def push_test(conn: Conn, sender: PushSender, admin: Admin) -> dict:
    """Sends one test push to every phone signed in to the caller's account,
    right now, without a notification row. Dead tokens are deleted."""
    tokens = conn.execute(
        "SELECT token FROM device_token WHERE student_id = %s ORDER BY updated_at DESC",
        (admin.student_id,),
    ).fetchall()
    sent = failed = removed = 0
    for row in tokens:
        result = sender.send(
            PushMessage(row["token"], TEST_PUSH_TITLE, TEST_PUSH_BODY, {"type": "test"})
        )
        if result is SendResult.SENT:
            sent += 1
        elif result is SendResult.INVALID_TOKEN:
            removed += 1
            conn.execute("DELETE FROM device_token WHERE token = %s", (row["token"],))
        else:
            failed += 1
    return {
        "fcm_configured": not isinstance(sender, LoggingPushSender),
        "devices": len(tokens),
        "sent": sent,
        "failed": failed,
        "removed": removed,
    }


# ---------- students (moderator only) ----------


def students(conn: Conn, admin: Admin, query: str | None) -> dict:
    _require_moderator(admin)
    pattern = f"%{query.strip()}%" if query and query.strip() else None
    rows = conn.execute(
        f"""
        SELECT s.student_id, s.email, s.full_name, s.enrolled_year, s.is_moderator,
               COALESCE(s.locked_until > NOW(), FALSE) AS is_locked, s.created_at,
               (SELECT COUNT(*) FROM subscription x
                WHERE x.student_id = s.student_id) AS subscriptions,
               (SELECT COUNT(*) FROM registration r JOIN event e USING (event_id)
                WHERE r.student_id = s.student_id AND e.status = 'published'
                  AND r.status IN ('confirmed', 'waiting_list')) AS active_registrations,
               (SELECT COUNT(*) FROM device_token d
                WHERE d.student_id = s.student_id) AS devices,
               (SELECT COUNT(*) FROM community c
                WHERE c.owner_id = s.student_id) AS owned_communities
        FROM student s
        WHERE %(pattern)s::text IS NULL
           OR s.email ILIKE %(pattern)s OR s.full_name ILIKE %(pattern)s
        ORDER BY s.full_name, s.student_id
        LIMIT {STUDENTS_LIMIT}
        """,  # noqa: S608 — only a constant is interpolated, values are bound
        {"pattern": pattern},
    ).fetchall()
    return {"items": rows}


def set_moderator(conn: Conn, admin: Admin, student_id: int, value: bool) -> None:
    _require_moderator(admin)
    if student_id == admin.student_id and not value:
        raise ApiError(409, "cannot_change_own_role")
    row = conn.execute(
        "UPDATE student SET is_moderator = %s WHERE student_id = %s RETURNING student_id",
        (value, student_id),
    ).fetchone()
    if row is None:
        raise ApiError(404, "student_not_found")


def unlock(conn: Conn, admin: Admin, student_id: int) -> None:
    """Lifts the NFR-02 lockout (5 wrong passwords) before its 15 minutes end."""
    _require_moderator(admin)
    row = conn.execute(
        """
        UPDATE student
        SET failed_logins = 0, first_failed_login_at = NULL, locked_until = NULL
        WHERE student_id = %s
        RETURNING student_id
        """,
        (student_id,),
    ).fetchone()
    if row is None:
        raise ApiError(404, "student_not_found")
