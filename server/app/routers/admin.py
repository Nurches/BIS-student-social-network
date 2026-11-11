from fastapi import APIRouter, BackgroundTasks, Depends, Request

from ..db import Pool, get_pool
from ..errors import error_responses
from ..schemas import PublishEventRequest, PublishEventResponse
from ..security import CurrentStudent, current_student
from ..services import events
from . import schedule_push

router = APIRouter(tags=["admin"])


@router.post(
    "/communities/{community_id}/events",
    status_code=201,
    response_model=PublishEventResponse,
    summary="Publish an event (confirmed community admin only)",
    responses=error_responses(
        "unauthorized",
        "not_a_confirmed_admin",
        "community_not_found",
        "payload_too_large",
        "deadline_in_the_past",
        "deadline_after_event_start",
        "timestamp_without_offset",
        "validation_failed",
    ),
)
def publish(
    community_id: int,
    body: PublishEventRequest,
    request: Request,
    background: BackgroundTasks,
    me: CurrentStudent = Depends(current_student),
    pool: Pool = Depends(get_pool),
) -> dict:
    """FR-02: a deadline in the past is rejected. BR-01: only the owner of a
    community confirmed by the Student Union may publish. Every subscriber
    gets one notification and a push (FR-01)."""
    with pool.connection() as conn:
        event_id, notification_ids = events.publish(
            conn, me.student_id, community_id, **body.model_dump()
        )
    schedule_push(request, background, notification_ids)
    return {"event_id": event_id, "status": "published"}
