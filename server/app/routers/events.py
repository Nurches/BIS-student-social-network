from fastapi import APIRouter, BackgroundTasks, Depends, Request, Response

from ..db import Pool, get_pool
from ..errors import error_responses
from ..schemas import (
    CancelOut,
    EventListResponse,
    EventOut,
    FeedbackOut,
    FeedbackRequest,
    RegistrationConfirmedOut,
    RegistrationWaitingOut,
    TicketOut,
)
from ..security import CurrentStudent, current_student
from ..services import attendance, events, posters
from . import schedule_push

router = APIRouter(prefix="/events", tags=["events"])


@router.get(
    "/announcements",
    response_model=EventListResponse,
    summary="Announcement cards: open events of every confirmed community (at most 10)",
    responses=error_responses("unauthorized"),
)
def announcements(
    me: CurrentStudent = Depends(current_student), pool: Pool = Depends(get_pool)
) -> dict:
    """Week 12, the home screen carousel. Followed or not; soonest deadline first."""
    with pool.connection() as conn:
        return events.announcements(conn, me.student_id)


@router.get(
    "/{event_id}",
    response_model=EventOut,
    summary="One event with fresh free places (v4: also a cancelled one)",
    responses=error_responses("unauthorized", "event_not_found", "validation_failed"),
)
def event_detail(
    event_id: int,
    me: CurrentStudent = Depends(current_student),
    pool: Pool = Depends(get_pool),
) -> dict:
    with pool.connection() as conn:
        return events.event_detail(conn, me.student_id, event_id)


@router.post(
    "/{event_id}/registrations",
    status_code=201,
    response_model=RegistrationConfirmedOut | RegistrationWaitingOut,
    responses={
        200: {"model": RegistrationWaitingOut, "description": "Full: waiting list"},
        **error_responses(
            "unauthorized",
            "event_not_found",
            "already_registered",
            "event_cancelled",
            "deadline_passed",
            "validation_failed",
        ),
    },
    summary="Register (FR-03)",
)
def register(
    event_id: int,
    response: Response,
    me: CurrentStudent = Depends(current_student),
    pool: Pool = Depends(get_pool),
) -> dict:
    """201 confirmed, or 200 waiting list when the event is full."""
    with pool.connection() as conn:
        result = events.register(conn, me.student_id, event_id)
    if result["status"] == "waiting_list":
        response.status_code = 200
    return result


@router.delete(
    "/{event_id}/registrations",
    response_model=CancelOut,
    summary="Cancel own registration",
    responses=error_responses(
        "unauthorized",
        "event_not_found",
        "not_registered",
        "already_checked_in",
        "event_cancelled",
        "event_started",
        "validation_failed",
    ),
)
def cancel(
    event_id: int,
    request: Request,
    background: BackgroundTasks,
    me: CurrentStudent = Depends(current_student),
    pool: Pool = Depends(get_pool),
) -> dict:
    """Promotes the first waiting-list student, who gets a push."""
    with pool.connection() as conn:
        promoted_notification = events.cancel(conn, me.student_id, event_id)
    if promoted_notification is not None:
        schedule_push(request, background, [promoted_notification])
    return {"status": "cancelled"}


# ---------- Week 13 (schema v5): ticket, feedback, poster ----------


@router.get(
    "/{event_id}/ticket",
    response_model=TicketOut,
    summary="My ticket: QR text and 6-character code of a confirmed place (FR-06)",
    responses=error_responses(
        "unauthorized",
        "event_not_found",
        "not_registered",
        "event_cancelled",
        "ticket_waiting_list",
        "validation_failed",
    ),
)
def ticket(
    event_id: int,
    request: Request,
    me: CurrentStudent = Depends(current_student),
    pool: Pool = Depends(get_pool),
) -> dict:
    """The organiser scans the QR (or types the code) in /admin at the door.
    Signed by the server: a ticket cannot be made up or moved to another event."""
    with pool.connection() as conn:
        return attendance.ticket(
            conn, request.app.state.settings.jwt_secret, me.student_id, event_id
        )


@router.post(
    "/{event_id}/feedback",
    status_code=201,
    response_model=FeedbackOut,
    summary="Rate an event I attended, once, after it ended (FR-07)",
    responses=error_responses(
        "unauthorized",
        "not_checked_in",
        "event_not_found",
        "event_cancelled",
        "event_not_finished",
        "feedback_already_sent",
        "payload_too_large",
        "validation_failed",
    ),
)
def feedback(
    event_id: int,
    body: FeedbackRequest,
    me: CurrentStudent = Depends(current_student),
    pool: Pool = Depends(get_pool),
) -> dict:
    """Only a student checked in at the door; `rating` 1-5, `comment` optional."""
    with pool.connection() as conn:
        return attendance.send_feedback(
            conn, me.student_id, event_id, rating=body.rating, comment=body.comment
        )


@router.get(
    "/{event_id}/poster",
    response_class=Response,
    summary="The poster image of an event (no token needed)",
    responses={
        200: {
            "description": "JPEG, PNG or WebP, re-encoded by the server",
            "content": {"image/jpeg": {}, "image/png": {}, "image/webp": {}},
        },
        **error_responses("poster_not_found", "validation_failed"),
    },
)
def poster(event_id: int, pool: Pool = Depends(get_pool)) -> Response:
    """`poster_url` of the Event object points here, with `?v=` changing on
    every replacement, so the image may be cached for a day."""
    with pool.connection() as conn:
        row = posters.load(conn, event_id)
    return Response(
        content=bytes(row["data"]),
        media_type=row["mime"],
        headers={
            "Cache-Control": "public, max-age=86400",
            "X-Content-Type-Options": "nosniff",
            "Content-Disposition": f'inline; filename="event-{event_id}-poster"',
        },
    )
