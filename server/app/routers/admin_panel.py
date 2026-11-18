"""Admin panel API behind the /admin page (services/admin_panel.py).

Moderators manage everything; community owners manage their own communities'
events. Publishing is `POST /communities/{id}/events` (routers/admin.py).
"""

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Request, Response

from ..db import Pool, get_pool
from ..errors import error_responses
from ..schemas import (
    AdminCommunityOut,
    AdminEventListResponse,
    AdminMeOut,
    AdminNotificationsResponse,
    AdminOverviewOut,
    AdminRegistrationsResponse,
    AdminStudentsResponse,
    CommunityCreateRequest,
    CommunityRejectRequest,
    CommunityReviewOut,
    CommunityStatus,
    CommunityUpdateRequest,
    EventCancelOut,
    EventUpdateOut,
    EventUpdateRequest,
    ModeratorRoleRequest,
    NotifyOut,
    PushTestOut,
)
from ..security import CurrentStudent, current_student
from ..services import admin_panel
from ..services.admin_panel import Admin
from . import schedule_push

router = APIRouter(prefix="/admin", tags=["admin panel"])

_ADMIN = ("unauthorized", "not_an_admin")
_EVENT = (*_ADMIN, "event_not_found", "not_your_community", "validation_failed")


def current_admin(
    me: CurrentStudent = Depends(current_student), pool: Pool = Depends(get_pool)
) -> Admin:
    """401 without a valid token, 403 `not_an_admin` for a plain student."""
    with pool.connection() as conn:
        return admin_panel.access(conn, me.student_id)


# ---------- who am I, overview ----------


@router.get(
    "/me",
    response_model=AdminMeOut,
    summary="Who is signed in to the admin panel, and the communities they own",
    responses=error_responses(*_ADMIN),
)
def admin_me(admin: Admin = Depends(current_admin), pool: Pool = Depends(get_pool)) -> dict:
    with pool.connection() as conn:
        return admin_panel.me(conn, admin)


@router.get(
    "/overview",
    response_model=AdminOverviewOut,
    summary="Counts for the dashboard (moderator: everything; owner: own communities)",
    responses=error_responses(*_ADMIN),
)
def overview(admin: Admin = Depends(current_admin), pool: Pool = Depends(get_pool)) -> dict:
    with pool.connection() as conn:
        return admin_panel.overview(conn, admin)


# ---------- communities ----------


@router.get(
    "/communities",
    response_model=list[AdminCommunityOut],
    summary="Communities with owner and counts (moderator: all; owner: own)",
    responses=error_responses(*_ADMIN, "validation_failed"),
)
def communities(
    status: CommunityStatus | None = Query(default=None, description="Only this status"),
    admin: Admin = Depends(current_admin),
    pool: Pool = Depends(get_pool),
) -> list[dict]:
    """`?status=pending` lists the requests waiting for a moderator (v4)."""
    with pool.connection() as conn:
        return admin_panel.list_communities(conn, admin, status)


@router.post(
    "/communities",
    status_code=201,
    response_model=AdminCommunityOut,
    summary="Create a community (moderator only)",
    responses=error_responses(
        *_ADMIN,
        "moderator_only",
        "student_not_found",
        "community_name_taken",
        "payload_too_large",
        "validation_failed",
    ),
)
def create_community(
    body: CommunityCreateRequest,
    admin: Admin = Depends(current_admin),
    pool: Pool = Depends(get_pool),
) -> dict:
    """`owner_email` is the account that will publish its events (BR-01);
    `is_confirmed: false` creates it awaiting the Student Union."""
    with pool.connection() as conn:
        return admin_panel.create_community(conn, admin, **body.model_dump())


@router.patch(
    "/communities/{community_id}",
    response_model=AdminCommunityOut,
    summary="Rename, change owner, confirm or unconfirm a community (moderator only)",
    responses=error_responses(
        *_ADMIN,
        "moderator_only",
        "community_not_found",
        "student_not_found",
        "community_name_taken",
        "payload_too_large",
        "validation_failed",
    ),
)
def update_community(
    community_id: int,
    body: CommunityUpdateRequest,
    request: Request,
    background: BackgroundTasks,
    admin: Admin = Depends(current_admin),
    pool: Pool = Depends(get_pool),
) -> dict:
    """Confirming a community that was not confirmed pushes `community_approved`
    to its owner, as `POST /admin/communities/{id}/approve` does."""
    with pool.connection() as conn:
        community, notification_ids = admin_panel.update_community(
            conn, admin, community_id, body.model_dump(exclude_unset=True)
        )
    schedule_push(request, background, notification_ids)
    return community


_REVIEW = (
    *_ADMIN,
    "moderator_only",
    "cannot_review_own_request",
    "community_not_found",
    "community_not_pending",
    "validation_failed",
)


@router.post(
    "/communities/{community_id}/approve",
    response_model=CommunityReviewOut,
    summary="Approve a community request (moderator only); the owner gets a push",
    responses=error_responses(*_REVIEW),
)
def approve_community(
    community_id: int,
    request: Request,
    background: BackgroundTasks,
    admin: Admin = Depends(current_admin),
    pool: Pool = Depends(get_pool),
) -> dict:
    """Week 12: pending -> confirmed. The owner may publish from now on (BR-01)."""
    with pool.connection() as conn:
        community, notification_ids = admin_panel.approve_community(conn, admin, community_id)
    schedule_push(request, background, notification_ids)
    return {"community": community, "notified": len(notification_ids)}


@router.post(
    "/communities/{community_id}/reject",
    response_model=CommunityReviewOut,
    summary="Reject a community request with an optional reason (moderator only)",
    responses=error_responses(*_REVIEW, "payload_too_large"),
)
def reject_community(
    community_id: int,
    body: CommunityRejectRequest,
    admin: Admin = Depends(current_admin),
    pool: Pool = Depends(get_pool),
) -> dict:
    """Week 12: pending -> rejected. The student sees the reason in the app."""
    with pool.connection() as conn:
        community = admin_panel.reject_community(conn, admin, community_id, body.reason)
    return {"community": community, "notified": 0}


# ---------- events ----------


@router.get(
    "/events",
    response_model=AdminEventListResponse,
    summary="Events of my communities, every status, with counts",
    responses=error_responses(*_ADMIN, "validation_failed"),
)
def events(
    community_id: int | None = Query(default=None, description="Only this community"),
    admin: Admin = Depends(current_admin),
    pool: Pool = Depends(get_pool),
) -> dict:
    with pool.connection() as conn:
        return admin_panel.list_events(conn, admin, community_id)


@router.patch(
    "/events/{event_id}",
    response_model=EventUpdateOut,
    summary="Edit an event; a larger limit moves students up from the waiting list",
    responses=error_responses(
        *_EVENT,
        "event_cancelled",
        "limit_below_confirmed",
        "deadline_in_the_past",
        "deadline_after_event_start",
        "start_in_the_past",
        "timestamp_without_offset",
        "payload_too_large",
    ),
)
def update_event(
    event_id: int,
    body: EventUpdateRequest,
    request: Request,
    background: BackgroundTasks,
    admin: Admin = Depends(current_admin),
    pool: Pool = Depends(get_pool),
) -> dict:
    """FR-02 for a moved deadline. Each promoted student gets the
    `waiting_list_promoted` push, as after a cancellation. v4: a new
    `starts_at` pushes `event_rescheduled` to every confirmed or waiting student."""
    with pool.connection() as conn:
        event, notification_ids, rescheduled = admin_panel.update_event(
            conn, admin, event_id, body.model_dump(exclude_unset=True)
        )
    schedule_push(request, background, notification_ids)
    return {
        "event": event,
        "promoted": len(notification_ids) - rescheduled,
        "rescheduled_notified": rescheduled,
    }


@router.post(
    "/events/{event_id}/cancel",
    response_model=EventCancelOut,
    summary="Cancel an event: every registered student gets a push",
    responses=error_responses(*_EVENT, "event_cancelled", "event_started"),
)
def cancel_event(
    event_id: int,
    request: Request,
    background: BackgroundTasks,
    admin: Admin = Depends(current_admin),
    pool: Pool = Depends(get_pool),
) -> dict:
    """v4: confirmed and waiting students get `event_cancelled`; the event
    leaves the feed but its page shows "Cancelled"."""
    with pool.connection() as conn:
        event, notification_ids = admin_panel.cancel_event(conn, admin, event_id)
    schedule_push(request, background, notification_ids)
    return {"event": event, "notified": len(notification_ids)}


@router.post(
    "/events/{event_id}/notify",
    response_model=NotifyOut,
    summary="Notify new subscribers and resend pushes FCM has not accepted yet",
    responses=error_responses(*_EVENT, "event_cancelled"),
)
def notify_again(
    event_id: int,
    request: Request,
    background: BackgroundTasks,
    admin: Admin = Depends(current_admin),
    pool: Pool = Depends(get_pool),
) -> dict:
    with pool.connection() as conn:
        new, queued = admin_panel.notify_again(conn, admin, event_id)
    schedule_push(request, background, queued)
    return {"new_recipients": new, "queued": len(queued)}


@router.get(
    "/events/{event_id}/registrations",
    response_model=AdminRegistrationsResponse,
    summary="Participants: confirmed, waiting list in queue order, cancelled",
    responses=error_responses(*_EVENT),
)
def registrations(
    event_id: int, admin: Admin = Depends(current_admin), pool: Pool = Depends(get_pool)
) -> dict:
    with pool.connection() as conn:
        return admin_panel.registrations(conn, admin, event_id)


# ---------- notifications and pushes ----------


@router.get(
    "/notifications",
    response_model=AdminNotificationsResponse,
    summary="Push delivery log of my communities, newest first (at most 200)",
    responses=error_responses(*_ADMIN, "validation_failed"),
)
def notifications(
    event_id: int | None = Query(default=None, description="Only this event"),
    admin: Admin = Depends(current_admin),
    pool: Pool = Depends(get_pool),
) -> dict:
    with pool.connection() as conn:
        return admin_panel.notifications(conn, admin, event_id)


@router.post(
    "/push-test",
    response_model=PushTestOut,
    summary="Send a test push to every phone signed in to my own account",
    responses=error_responses(*_ADMIN),
)
def push_test(
    request: Request, admin: Admin = Depends(current_admin), pool: Pool = Depends(get_pool)
) -> dict:
    """Synchronous: the answer says how many phones FCM accepted."""
    with pool.connection() as conn:
        return admin_panel.push_test(conn, request.app.state.push_sender, admin)


# ---------- students (moderator only) ----------


@router.get(
    "/students",
    response_model=AdminStudentsResponse,
    summary="Students with their counts (moderator only, at most 300)",
    responses=error_responses(*_ADMIN, "moderator_only", "validation_failed"),
)
def students(
    q: str | None = Query(default=None, max_length=120, description="Part of email or name"),
    admin: Admin = Depends(current_admin),
    pool: Pool = Depends(get_pool),
) -> dict:
    with pool.connection() as conn:
        return admin_panel.students(conn, admin, q)


@router.put(
    "/students/{student_id}/moderator",
    status_code=204,
    summary="Grant or remove the moderator role (moderator only)",
    responses=error_responses(
        *_ADMIN,
        "moderator_only",
        "student_not_found",
        "cannot_change_own_role",
        "payload_too_large",
        "validation_failed",
    ),
)
def set_moderator(
    student_id: int,
    body: ModeratorRoleRequest,
    admin: Admin = Depends(current_admin),
    pool: Pool = Depends(get_pool),
) -> Response:
    with pool.connection() as conn:
        admin_panel.set_moderator(conn, admin, student_id, body.is_moderator)
    return Response(status_code=204)


@router.post(
    "/students/{student_id}/unlock",
    status_code=204,
    summary="Lift the lockout after 5 wrong passwords (moderator only)",
    responses=error_responses(*_ADMIN, "moderator_only", "student_not_found", "validation_failed"),
)
def unlock(
    student_id: int, admin: Admin = Depends(current_admin), pool: Pool = Depends(get_pool)
) -> Response:
    with pool.connection() as conn:
        admin_panel.unlock(conn, admin, student_id)
    return Response(status_code=204)
