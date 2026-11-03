from fastapi import APIRouter, Depends, Query

from ..db import Pool, get_pool
from ..schemas import FeedResponse
from ..security import CurrentStudent, current_student
from ..services import events

router = APIRouter(tags=["events"])


@router.get("/feed", response_model=FeedResponse, summary="Events from followed communities")
def feed(
    limit: int = Query(20, ge=1, le=50),
    cursor: str | None = Query(None, max_length=200),
    me: CurrentStudent = Depends(current_student),
    pool: Pool = Depends(get_pool),
) -> dict:
    """Published, deadline not passed, ordered by `(registration_deadline,
    event_id)`. Pass `next_cursor` unchanged to get the next page."""
    with pool.connection() as conn:
        return events.feed(conn, me.student_id, limit=limit, cursor=cursor)
