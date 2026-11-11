from fastapi import APIRouter, Depends, Response

from ..db import Pool, get_pool
from ..errors import error_responses
from ..schemas import EventListResponse, NotificationsResponse
from ..security import CurrentStudent, current_student
from ..services import social

router = APIRouter(prefix="/me", tags=["me"])

_AUTH = error_responses("unauthorized")


@router.get(
    "/registrations",
    response_model=EventListResponse,
    summary="Events I am registered for or waiting for",
    responses=_AUTH,
)
def my_registrations(
    me: CurrentStudent = Depends(current_student), pool: Pool = Depends(get_pool)
) -> dict:
    """Past events included; the app splits them into Upcoming and Past."""
    with pool.connection() as conn:
        return social.my_registrations(conn, me.student_id)


@router.get(
    "/notifications",
    response_model=NotificationsResponse,
    summary="My notifications, newest first (at most 50)",
    responses=_AUTH,
)
def my_notifications(
    me: CurrentStudent = Depends(current_student), pool: Pool = Depends(get_pool)
) -> dict:
    with pool.connection() as conn:
        return social.notifications(conn, me.student_id)


@router.post(
    "/notifications/read",
    status_code=204,
    summary="Mark all my notifications as read",
    responses=_AUTH,
)
def mark_read(
    me: CurrentStudent = Depends(current_student), pool: Pool = Depends(get_pool)
) -> Response:
    with pool.connection() as conn:
        social.mark_notifications_read(conn, me.student_id)
    return Response(status_code=204)
