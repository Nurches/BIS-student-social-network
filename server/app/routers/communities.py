from fastapi import APIRouter, Depends, Response

from ..db import Pool, get_pool
from ..errors import error_responses
from ..schemas import CommunityOut, EventListResponse
from ..security import CurrentStudent, current_student
from ..services import social

router = APIRouter(prefix="/communities", tags=["communities"])

_ONE_COMMUNITY = error_responses("unauthorized", "community_not_found", "validation_failed")


@router.get(
    "",
    response_model=list[CommunityOut],
    summary="All communities, with follow state and counts",
    responses=error_responses("unauthorized"),
)
def list_communities(
    me: CurrentStudent = Depends(current_student), pool: Pool = Depends(get_pool)
) -> list[dict]:
    with pool.connection() as conn:
        return social.list_communities(conn, me.student_id)


@router.put(
    "/{community_id}/subscription",
    status_code=204,
    summary="Follow a community (idempotent)",
    responses=_ONE_COMMUNITY,
)
def follow(
    community_id: int,
    me: CurrentStudent = Depends(current_student),
    pool: Pool = Depends(get_pool),
) -> Response:
    """Its events appear in the feed, and the student gets a push for new ones."""
    with pool.connection() as conn:
        social.subscribe(conn, me.student_id, community_id)
    return Response(status_code=204)


@router.delete(
    "/{community_id}/subscription",
    status_code=204,
    summary="Unfollow a community (idempotent)",
    responses=_ONE_COMMUNITY,
)
def unfollow(
    community_id: int,
    me: CurrentStudent = Depends(current_student),
    pool: Pool = Depends(get_pool),
) -> Response:
    """Registrations stay as they are; only the feed and future pushes change."""
    with pool.connection() as conn:
        social.unsubscribe(conn, me.student_id, community_id)
    return Response(status_code=204)


@router.get(
    "/{community_id}/events",
    response_model=EventListResponse,
    summary="Open events of one community",
    responses=_ONE_COMMUNITY,
)
def community_events(
    community_id: int,
    me: CurrentStudent = Depends(current_student),
    pool: Pool = Depends(get_pool),
) -> dict:
    """Published, deadline not passed, ordered by deadline; at most 50."""
    with pool.connection() as conn:
        return social.community_events(conn, me.student_id, community_id)
