from fastapi import APIRouter, BackgroundTasks, Depends, Request, Response

from ..db import Pool, get_pool
from ..schemas import (
    CancelOut,
    EventOut,
    RegistrationConfirmedOut,
    RegistrationWaitingOut,
)
from ..security import CurrentStudent, current_student
from ..services import events
from . import schedule_push

router = APIRouter(prefix="/events", tags=["events"])


@router.get("/{event_id}", response_model=EventOut, summary="One event with fresh free places")
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
    responses={200: {"model": RegistrationWaitingOut, "description": "Full: waiting list"}},
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
    "/{event_id}/registrations", response_model=CancelOut, summary="Cancel own registration"
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
