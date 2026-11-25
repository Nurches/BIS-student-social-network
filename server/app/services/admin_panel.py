"""The admin panel at /admin: communities, events, participants, pushes, students.

Two kinds of admin, both read from the database on every request:

* a **moderator** of the Student Union (`student.is_moderator`) sees and manages
  everything, creates and confirms communities (BR-01) and manages students;
* a **community owner** of a *confirmed* community sees and manages only the
  communities they own and their events (v4: a pending request gives no access).

Anyone else gets 403 `not_an_admin`. Publishing itself stays the endpoint of
FR-01/FR-02 (`POST /communities/{id}/events`, services/events.py), so BR-01 is
checked in one place only.

Week 12 (schema v4): a moderator approves or rejects community requests
(approval pushes `community_approved` to the owner); cancelling or moving an
event pushes `event_cancelled` / `event_rescheduled` to every student who is
confirmed or waiting.

Week 13 (schema v5): posters (FR-08), check-in at the door (FR-06), "Finish
now", the feedback of an event (FR-07) and attendance analytics. Every one of
them follows the rule of editing an event: its community's owner or a moderator.
"""

from dataclasses import dataclass
from datetime import UTC, datetime

from psycopg import errors as pg_errors

from ..db import Conn
from ..errors import ApiError
from ..security import check_in_rate_limiter
from . import tickets
from .attendance import check_in_window
from .events import EVENT_END_SQL, POSTER_URL_SQL, create_publish_notifications
from .posters import Poster
from .push import LoggingPushSender, PushMessage, PushSender, SendResult

EVENTS_LIMIT = 300
ANALYTICS_LIMIT = 300
FEEDBACK_LIMIT = 500
CHECK_IN_ATTEMPTS_PER_MINUTE = 60  # per organiser: guessing codes is pointless
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
               EXISTS (SELECT 1 FROM community c
                       WHERE c.owner_id = s.student_id AND c.status = 'confirmed'
                         AND c.deleted_at IS NULL) AS owns
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
        "SELECT community_id, name, is_confirmed, status FROM community "
        "WHERE owner_id = %s ORDER BY name",
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
            (SELECT COUNT(*) FROM c WHERE c.status = 'pending') AS pending_requests,
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
            (SELECT COUNT(*) FROM notification n JOIN e USING (event_id))
            + (SELECT COUNT(*) FROM notification n JOIN c USING (community_id))
                AS notifications,
            (SELECT COUNT(*) FROM notification n JOIN e USING (event_id)
             WHERE n.sent_at IS NOT NULL)
            + (SELECT COUNT(*) FROM notification n JOIN c USING (community_id)
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
SELECT c.community_id, c.name, c.description, c.is_confirmed, c.status, c.reject_reason,
       c.reviewed_at, c.created_at,
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


def list_communities(conn: Conn, admin: Admin, status: str | None = None) -> list[dict]:
    return conn.execute(
        f"{_COMMUNITY_SELECT} WHERE {_IN_SCOPE} "
        "AND (%(status)s::text IS NULL OR c.status = %(status)s) ORDER BY c.name",
        {**_scope(admin), "status": status},
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
                    "INSERT INTO community (name, description, owner_id, status, reviewed_at) "
                    "VALUES (%s, %s, %s, %s, CASE WHEN %s THEN NOW() END) "
                    "RETURNING community_id",
                    (
                        name,
                        description or None,
                        owner_id,
                        "confirmed" if is_confirmed else "pending",
                        is_confirmed,
                    ),
                ).fetchone()
        except pg_errors.UniqueViolation as exc:
            raise ApiError(409, "community_name_taken") from exc
        assert row is not None
        created = _find_community(conn, row["community_id"])
        assert created is not None
        return created


def update_community(
    conn: Conn, admin: Admin, community_id: int, changes: dict
) -> tuple[dict, list[int]]:
    """Moderator only: rename, describe, hand over to another owner, confirm or
    withdraw the confirmation (an unconfirmed community cannot publish, BR-01).

    Confirming a community that was not confirmed is an approval: the owner
    gets the `community_approved` push, as with `approve_community`.
    Returns the community and the notifications to push."""
    _require_moderator(admin)
    with conn.transaction():
        before = _community(conn, community_id)
        columns: dict[str, object] = {}
        if "name" in changes:
            columns["name"] = changes["name"]
        if "description" in changes:
            columns["description"] = changes["description"] or None
        if "is_confirmed" in changes and changes["is_confirmed"] != before["is_confirmed"]:
            columns["status"] = "confirmed" if changes["is_confirmed"] else "pending"
            columns["reject_reason"] = None
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
        notification_ids: list[int] = []
        if columns.get("status") == "confirmed":
            conn.execute(
                "UPDATE community SET reviewed_at = NOW() WHERE community_id = %s",
                (community_id,),
            )
            notification_ids = _notify_approved(conn, community_id)
        return _community(conn, community_id), notification_ids


# ---------- community requests (Week 12) ----------


def _notify_approved(conn: Conn, community_id: int) -> list[int]:
    """One `community_approved` row for the owner; approving again (after a
    withdrawal) sends it again instead of adding a second row."""
    row = conn.execute(
        """
        INSERT INTO notification (student_id, community_id, kind)
        SELECT owner_id, community_id, 'community_approved'
        FROM community WHERE community_id = %s
        ON CONFLICT (student_id, community_id, kind) WHERE community_id IS NOT NULL
        DO UPDATE SET sent_at = NULL, is_read = FALSE, created_at = NOW()
        RETURNING notification_id
        """,
        (community_id,),
    ).fetchone()
    return [row["notification_id"]] if row else []


def _pending_request(conn: Conn, admin: Admin, community_id: int) -> dict:
    """The locked request row, if this moderator may review it."""
    _require_moderator(admin)
    row = conn.execute(
        "SELECT community_id, owner_id, status FROM community "
        "WHERE community_id = %s AND deleted_at IS NULL FOR UPDATE",
        (community_id,),
    ).fetchone()
    if row is None:
        raise ApiError(404, "community_not_found")
    if row["owner_id"] == admin.student_id:
        # Akbota's threat "self-approval": a moderator's own request needs another moderator.
        raise ApiError(403, "cannot_review_own_request")
    if row["status"] != "pending":
        raise ApiError(409, "community_not_pending")
    return row


def approve_community(conn: Conn, admin: Admin, community_id: int) -> tuple[dict, list[int]]:
    """pending -> confirmed: the owner may publish now and gets a push."""
    with conn.transaction():
        _pending_request(conn, admin, community_id)
        conn.execute(
            "UPDATE community SET status = 'confirmed', reviewed_at = NOW(), "
            "reject_reason = NULL WHERE community_id = %s",
            (community_id,),
        )
        notification_ids = _notify_approved(conn, community_id)
        return _community(conn, community_id), notification_ids


def reject_community(conn: Conn, admin: Admin, community_id: int, reason: str | None) -> dict:
    """pending -> rejected, with an optional reason the student sees in the
    app. No push (Week 12 plan). The name becomes free again."""
    with conn.transaction():
        _pending_request(conn, admin, community_id)
        conn.execute(
            "UPDATE community SET status = 'rejected', reviewed_at = NOW(), "
            "reject_reason = %s WHERE community_id = %s",
            (reason or None, community_id),
        )
        return _community(conn, community_id)


# ---------- events ----------

_EVENT_SELECT = f"""
SELECT e.event_id, e.community_id, c.name AS community_name, e.title, e.description,
       e.location, e.starts_at, e.registration_deadline, e.participant_limit, e.status,
       e.created_at, e.previous_starts_at, e.cancelled_at,
       {EVENT_END_SQL} AS ends_at,
       CASE
           WHEN e.status <> 'published' THEN e.status
           WHEN {EVENT_END_SQL} <= NOW() THEN 'finished'
           WHEN e.starts_at <= NOW() THEN 'live'
           WHEN e.registration_deadline <= NOW() THEN 'closed'
           ELSE 'open'
       END AS state,
       {POSTER_URL_SQL} AS poster_url,
       (SELECT COUNT(*) FROM registration r
        WHERE r.event_id = e.event_id AND r.status = 'confirmed'
          AND r.checked_in_at IS NOT NULL) AS attended_count,
       (SELECT COUNT(*) FROM event_feedback f WHERE f.event_id = e.event_id) AS feedback_count,
       (SELECT ROUND(AVG(f.rating), 2) FROM event_feedback f
        WHERE f.event_id = e.event_id) AS average_rating,
       (SELECT COUNT(*) FROM registration r
        WHERE r.event_id = e.event_id AND r.status = 'confirmed') AS confirmed_count,
       (SELECT COUNT(*) FROM registration r
        WHERE r.event_id = e.event_id AND r.status = 'waiting_list') AS waiting_count,
       (SELECT COUNT(*) FROM notification n WHERE n.event_id = e.event_id) AS notified_count,
       (SELECT COUNT(*) FROM notification n
        WHERE n.event_id = e.event_id AND n.sent_at IS NOT NULL) AS sent_count
FROM event e
JOIN community c ON c.community_id = e.community_id
"""  # noqa: S608 — constants only


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
        SELECT e.event_id, e.title, e.status, e.starts_at, e.registration_deadline,
               e.participant_limit, e.ends_at AS own_end, {EVENT_END_SQL} AS ends_at,
               c.owner_id, c.status AS community_status
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
    "ends_at",
)


def _notify_registered(conn: Conn, event_id: int, kind: str) -> list[int]:
    """One `kind` row for every student confirmed or waiting. A second move
    re-sends the same row (sent_at = NULL), so nobody gets two rows."""
    rows = conn.execute(
        """
        INSERT INTO notification (student_id, event_id, kind)
        SELECT r.student_id, r.event_id, %s
        FROM registration r
        JOIN student s ON s.student_id = r.student_id AND s.deleted_at IS NULL
        WHERE r.event_id = %s AND r.status IN ('confirmed', 'waiting_list')
        ON CONFLICT (student_id, event_id, kind)
        DO UPDATE SET sent_at = NULL, is_read = FALSE, created_at = NOW()
        RETURNING notification_id
        """,
        (kind, event_id),
    ).fetchall()
    return [r["notification_id"] for r in rows]


def update_event(
    conn: Conn, admin: Admin, event_id: int, changes: dict
) -> tuple[dict, list[int], int]:
    """Edits a published event. Returns it, the notifications to push and how
    many registered students were told about a new start time.

    FR-02 holds for a moved deadline: it must be in the future and not after
    the start. A limit below the confirmed count is refused (nobody loses a
    place); a larger limit moves students up from the waiting list in queue
    order, each with a `waiting_list_promoted` push, as a cancellation does.

    v4: a new `starts_at` is a reschedule. It must be in the future; the old
    start is kept in `previous_starts_at`, and every confirmed or waiting
    student gets the `event_rescheduled` push.
    """
    with conn.transaction():
        event = _managed_event(conn, admin, event_id, lock=True)
        if event["status"] == "cancelled":
            raise ApiError(409, "event_cancelled")
        if event["ends_at"] <= datetime.now(UTC) and {"starts_at", "ends_at"} & set(changes):
            # v5: after the end, check-ins and ratings belong to these times.
            raise ApiError(409, "event_already_finished")

        deadline = changes.get("registration_deadline", event["registration_deadline"])
        starts_at = changes.get("starts_at", event["starts_at"])
        limit = changes.get("participant_limit", event["participant_limit"])
        if deadline != event["registration_deadline"] and deadline <= datetime.now(UTC):
            raise ApiError(422, "deadline_in_the_past")
        moved = starts_at != event["starts_at"]
        if moved and starts_at <= datetime.now(UTC):
            raise ApiError(422, "start_in_the_past")
        if deadline > starts_at:
            raise ApiError(422, "deadline_after_event_start")
        # v5: an own end moves with the start (same length), unless a new one is sent.
        ends_at = changes.get("ends_at", event["own_end"])
        if moved and "ends_at" not in changes and event["own_end"] is not None:
            ends_at = event["own_end"] + (starts_at - event["starts_at"])
            changes = {**changes, "ends_at": ends_at}
        if ends_at is not None and ends_at <= starts_at:
            raise ApiError(422, "end_before_start")

        confirmed = conn.execute(
            "SELECT COUNT(*) AS n FROM registration WHERE event_id = %s AND status = 'confirmed'",
            (event_id,),
        ).fetchone()
        assert confirmed is not None
        if limit < confirmed["n"]:
            raise ApiError(409, "limit_below_confirmed")

        columns = {name: changes[name] for name in _EDITABLE_EVENT_FIELDS if name in changes}
        if not moved:
            columns.pop("starts_at", None)
        else:
            columns["previous_starts_at"] = event["starts_at"]
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
        rescheduled: list[int] = []
        if moved:
            rescheduled = _notify_registered(conn, event_id, "event_rescheduled")
        return _event(conn, event_id), notification_ids + rescheduled, len(rescheduled)


def cancel_event(conn: Conn, admin: Admin, event_id: int) -> tuple[dict, list[int]]:
    """Removes the event from the feed and the announcements. Registrations
    are kept as they were, for the record; v4: every confirmed or waiting
    student gets the `event_cancelled` push, and the event page and "My
    events" show it as cancelled. An event that has started cannot be
    cancelled (410 `event_started`)."""
    with conn.transaction():
        event = _managed_event(conn, admin, event_id, lock=True)
        if event["status"] == "cancelled":
            raise ApiError(409, "event_cancelled")
        if event["status"] == "published" and event["starts_at"] <= datetime.now(UTC):
            raise ApiError(410, "event_started")
        conn.execute(
            "UPDATE event SET status = 'cancelled', cancelled_at = NOW() WHERE event_id = %s",
            (event_id,),
        )
        notification_ids: list[int] = []
        if event["status"] == "published":
            notification_ids = _notify_registered(conn, event_id, "event_cancelled")
        return _event(conn, event_id), notification_ids


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
        ).fetchall()  # every kind: a reschedule push that did not arrive is sent again
    return len(new), sorted({r["notification_id"] for r in unsent})


def registrations(conn: Conn, admin: Admin, event_id: int) -> dict:
    _managed_event(conn, admin, event_id)
    rows = conn.execute(
        """
        SELECT r.registration_id, s.student_id, s.email, s.full_name, r.status,
               r.checked_in_at,
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


# ---------- posters (Week 13, FR-08) ----------


def save_poster(conn: Conn, admin: Admin, event_id: int, poster: Poster) -> dict:
    """Uploads or replaces the poster of an event the caller manages. The image
    was checked and re-encoded by services/posters.py before it gets here."""
    with conn.transaction():
        event = _managed_event(conn, admin, event_id, lock=True)
        if event["status"] == "cancelled":
            raise ApiError(409, "event_cancelled")
        if event["community_status"] != "confirmed":
            raise ApiError(409, "community_not_confirmed")
        row = conn.execute(
            """
            INSERT INTO event_poster (event_id, mime, size_bytes, width, height, data,
                                      uploaded_by, uploaded_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, clock_timestamp())
            ON CONFLICT (event_id) DO UPDATE
            SET mime = EXCLUDED.mime, size_bytes = EXCLUDED.size_bytes,
                width = EXCLUDED.width, height = EXCLUDED.height, data = EXCLUDED.data,
                uploaded_by = EXCLUDED.uploaded_by, uploaded_at = EXCLUDED.uploaded_at
            RETURNING event_id, mime, size_bytes, width, height, uploaded_at
            """,
            (
                event_id,
                poster.mime,
                len(poster.data),
                poster.width,
                poster.height,
                poster.data,
                admin.student_id,
            ),
        ).fetchone()
        assert row is not None
        return {**row, "poster_url": _poster_url(conn, event_id)}


def _poster_url(conn: Conn, event_id: int) -> str | None:
    row = conn.execute(
        f"SELECT {POSTER_URL_SQL} AS url FROM event e WHERE e.event_id = %s",  # noqa: S608 — constant
        (event_id,),
    ).fetchone()
    return row["url"] if row else None


def delete_poster(conn: Conn, admin: Admin, event_id: int) -> None:
    """The owner removes the poster of an own event; a moderator removes any
    (Akbota's threat: an inappropriate poster)."""
    _managed_event(conn, admin, event_id)
    row = conn.execute(
        "DELETE FROM event_poster WHERE event_id = %s RETURNING event_id", (event_id,)
    ).fetchone()
    if row is None:
        raise ApiError(404, "poster_not_found")


# ---------- check-in at the door (Week 13, FR-06) ----------


def _ticket_registration(conn: Conn, secret: str, event_id: int, ticket: str) -> dict:
    """The registration a scanned QR or a typed code points to (locked)."""
    if tickets.looks_like_payload(ticket):
        registration_id = tickets.registration_from_payload(secret, ticket)
        if registration_id is None:
            raise ApiError(422, "invalid_ticket")  # forged or damaged QR
    else:
        typed = tickets.normalize_code(ticket)
        if len(typed) != tickets.CODE_LENGTH:
            raise ApiError(422, "invalid_ticket")
        candidates = conn.execute(
            "SELECT registration_id FROM registration WHERE event_id = %s", (event_id,)
        ).fetchall()
        matches = [
            r["registration_id"]
            for r in candidates
            if tickets.code(secret, r["registration_id"]) == typed
        ]
        if not matches:
            raise ApiError(422, "invalid_ticket")
        registration_id = matches[0]
    row = conn.execute(
        """
        SELECT r.registration_id, r.event_id, r.status, r.checked_in_at,
               s.student_id, s.full_name, s.email
        FROM registration r JOIN student s ON s.student_id = r.student_id
        WHERE r.registration_id = %s
        FOR UPDATE OF r
        """,
        (registration_id,),
    ).fetchone()
    if row is None:
        raise ApiError(422, "invalid_ticket")
    if row["event_id"] != event_id:
        raise ApiError(409, "ticket_other_event")  # a real ticket, but for another event
    return row


def check_in(conn: Conn, admin: Admin, secret: str, event_id: int, ticket: str) -> dict:
    """Checks a student in once, from the QR payload or the 6-character code.

    Only a confirmed place gets in (not the waiting list), only on an event the
    caller manages, only while the door is open: from 3 hours before the start
    to 2 hours after the end."""
    wait = check_in_rate_limiter.hit(f"admin:{admin.student_id}", CHECK_IN_ATTEMPTS_PER_MINUTE)
    if wait is not None:
        raise ApiError(
            429, "too_many_requests", headers={"Retry-After": str(max(1, int(wait) + 1))}
        )
    with conn.transaction():
        event = _managed_event(conn, admin, event_id, lock=True)
        if event["status"] == "cancelled":
            raise ApiError(409, "event_cancelled")
        if event["status"] != "published":
            raise ApiError(404, "event_not_found")
        # The ticket first: a forged one is refused whatever the time.
        registration = _ticket_registration(conn, secret, event_id, ticket)
        opens, closes = check_in_window(event["starts_at"], event["ends_at"])
        now = datetime.now(UTC)
        if now < opens:
            raise ApiError(409, "check_in_not_open", opens_at=opens.isoformat())
        if now > closes:
            raise ApiError(410, "check_in_closed")
        if registration["status"] != "confirmed":
            raise ApiError(409, "ticket_not_confirmed")  # waiting list or cancelled
        if registration["checked_in_at"] is not None:
            # A screenshot of a ticket shown a second time.
            raise ApiError(
                409,
                "already_checked_in",
                checked_in_at=registration["checked_in_at"].isoformat(),
                student_name=registration["full_name"],
            )
        row = conn.execute(
            "UPDATE registration SET checked_in_at = clock_timestamp(), checked_in_by = %s "
            "WHERE registration_id = %s RETURNING checked_in_at",
            (admin.student_id, registration["registration_id"]),
        ).fetchone()
        assert row is not None
        counts = conn.execute(
            "SELECT COUNT(*) FILTER (WHERE checked_in_at IS NOT NULL) AS attended, "
            "COUNT(*) AS confirmed FROM registration WHERE event_id = %s AND status = 'confirmed'",
            (event_id,),
        ).fetchone()
        assert counts is not None
        return {
            "registration_id": registration["registration_id"],
            "student_id": registration["student_id"],
            "full_name": registration["full_name"],
            "email": registration["email"],
            "checked_in_at": row["checked_in_at"],
            "attended_count": counts["attended"],
            "confirmed_count": counts["confirmed"],
        }


def finish_event(conn: Conn, admin: Admin, event_id: int) -> dict:
    """ "Finish now": the event ends at once, so feedback opens (FR-07).
    Only after the start, and only once."""
    with conn.transaction():
        event = _managed_event(conn, admin, event_id, lock=True)
        if event["status"] == "cancelled":
            raise ApiError(409, "event_cancelled")
        if event["status"] != "published":
            raise ApiError(404, "event_not_found")
        now = datetime.now(UTC)
        if event["starts_at"] > now:
            raise ApiError(409, "event_not_started")
        if event["ends_at"] <= now:
            raise ApiError(409, "event_already_finished")
        conn.execute(
            "UPDATE event SET ends_at = GREATEST(NOW(), starts_at + INTERVAL '1 second') "
            "WHERE event_id = %s",
            (event_id,),
        )
        return _event(conn, event_id)


# ---------- feedback and analytics (Week 13, FR-07) ----------


def feedback(conn: Conn, admin: Admin, event_id: int) -> dict:
    """Ratings and comments of one event, newest first. Anonymous on purpose:
    the organiser sees what was said, not who said it."""
    _managed_event(conn, admin, event_id)
    rows = conn.execute(
        f"""
        SELECT rating, comment, created_at FROM event_feedback
        WHERE event_id = %s ORDER BY created_at DESC, feedback_id DESC
        LIMIT {FEEDBACK_LIMIT}
        """,  # noqa: S608 — a constant only
        (event_id,),
    ).fetchall()
    summary = conn.execute(
        """
        SELECT COUNT(*) AS count, ROUND(AVG(rating), 2) AS average,
               COUNT(*) FILTER (WHERE rating = 1) AS r1, COUNT(*) FILTER (WHERE rating = 2) AS r2,
               COUNT(*) FILTER (WHERE rating = 3) AS r3, COUNT(*) FILTER (WHERE rating = 4) AS r4,
               COUNT(*) FILTER (WHERE rating = 5) AS r5
        FROM event_feedback WHERE event_id = %s
        """,
        (event_id,),
    ).fetchone()
    assert summary is not None
    return {
        "event": _event(conn, event_id),
        "count": summary["count"],
        "average_rating": summary["average"],
        "distribution": [summary[f"r{i}"] for i in range(1, 6)],
        "items": rows,
    }


def _rate(part: int, whole: int) -> float | None:
    return round(100 * part / whole, 1) if whole else None


def analytics(conn: Conn, admin: Admin) -> dict:
    """Registered vs attended, no-show % and average rating, per event and
    per community, for every event that has started. No-show counts only
    events that ended: a student may still be on the way to a live one."""
    events = conn.execute(
        f"""
        SELECT e.event_id, e.title, e.community_id, c.name AS community_name, e.starts_at,
               {EVENT_END_SQL} AS ends_at,
               {EVENT_END_SQL} <= NOW() AS finished,
               (SELECT COUNT(*) FROM registration r
                WHERE r.event_id = e.event_id AND r.status = 'confirmed') AS registered,
               (SELECT COUNT(*) FROM registration r
                WHERE r.event_id = e.event_id AND r.status = 'confirmed'
                  AND r.checked_in_at IS NOT NULL) AS attended,
               (SELECT COUNT(*) FROM event_feedback f
                WHERE f.event_id = e.event_id) AS feedback_count,
               (SELECT COALESCE(SUM(f.rating), 0) FROM event_feedback f
                WHERE f.event_id = e.event_id) AS rating_sum
        FROM event e
        JOIN community c ON c.community_id = e.community_id
        WHERE {_IN_SCOPE}
          AND e.status = 'published' AND e.deleted_at IS NULL
          AND e.starts_at <= NOW()
        ORDER BY e.starts_at DESC, e.event_id DESC
        LIMIT {ANALYTICS_LIMIT}
        """,  # noqa: S608 — only fixed fragments are interpolated, values are bound
        _scope(admin),
    ).fetchall()

    def summary(rows: list[dict]) -> dict:
        ended = [r for r in rows if r["finished"]]
        registered = sum(r["registered"] for r in ended)
        attended = sum(r["attended"] for r in ended)
        count = sum(r["feedback_count"] for r in rows)
        return {
            "events": len(rows),
            "finished_events": len(ended),
            "registered": registered,
            "attended": attended,
            "no_show": registered - attended,
            "no_show_rate": _rate(registered - attended, registered),
            "attendance_rate": _rate(attended, registered),
            "feedback_count": count,
            "average_rating": (
                round(sum(r["rating_sum"] for r in rows) / count, 2) if count else None
            ),
        }

    items = []
    for r in events:
        no_show = r["registered"] - r["attended"] if r["finished"] else None
        items.append(
            {
                **{k: v for k, v in r.items() if k != "rating_sum"},
                "no_show": no_show,
                "no_show_rate": _rate(no_show, r["registered"]) if no_show is not None else None,
                "average_rating": (
                    round(r["rating_sum"] / r["feedback_count"], 2) if r["feedback_count"] else None
                ),
            }
        )
    by_community: dict[int, list[dict]] = {}
    names: dict[int, str] = {}
    for r in events:
        by_community.setdefault(r["community_id"], []).append(r)
        names[r["community_id"]] = r["community_name"]
    communities = sorted(
        (
            {"community_id": cid, "community_name": names[cid], **summary(rows)}
            for cid, rows in by_community.items()
        ),
        key=lambda c: c["community_name"],
    )
    return {"totals": summary(list(events)), "communities": communities, "events": items}


# ---------- notifications and pushes ----------


def notifications(conn: Conn, admin: Admin, event_id: int | None) -> dict:
    """The delivery log: newest first, `sent_at` empty until FCM accepts."""
    rows = conn.execute(
        f"""
        SELECT n.notification_id, n.kind, n.event_id, c.community_id,
               e.title AS event_title, c.name AS community_name,
               s.email AS student_email, s.full_name AS student_name,
               (SELECT COUNT(*) FROM device_token d
                WHERE d.student_id = n.student_id) AS devices,
               n.created_at, n.sent_at, n.is_read
        FROM notification n
        LEFT JOIN event e ON e.event_id = n.event_id
        JOIN community c  ON c.community_id = COALESCE(e.community_id, n.community_id)
        JOIN student s    ON s.student_id = n.student_id
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
