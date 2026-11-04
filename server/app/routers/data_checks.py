from fastapi import APIRouter, Depends, Request

from ..config import Settings, get_settings
from ..errors import ApiError
from ..schemas import DataChecksReport
from ..security import CurrentStudent, current_student, data_checks_rate_limiter
from ..services import data_checks

router = APIRouter(tags=["tools"])

RUN_INTERVAL_SECONDS = 10


@router.get(
    "/admin/data-checks",
    response_model=DataChecksReport,
    summary="Run the data checks of app/checks/data_checks.sql (tool, not the product)",
)
def run_data_checks(
    request: Request,
    me: CurrentStudent = Depends(current_student),
    settings: Settings = Depends(get_settings),
) -> dict:
    """Allow list `DATA_CHECK_EMAILS` (403 `not_allowed`); one run per 10 s per
    student (429). Read only: the run is a READ ONLY transaction, rolled back."""
    if me.email.lower() not in settings.data_check_allow_list:
        raise ApiError(403, "not_allowed")
    wait = data_checks_rate_limiter.hit(
        f"student:{me.student_id}", limit=1, window_seconds=RUN_INTERVAL_SECONDS
    )
    if wait is not None:
        raise ApiError(
            429, "too_many_requests", headers={"Retry-After": str(max(1, int(wait) + 1))}
        )

    state = request.app.state
    checks = (
        data_checks.load_checks(settings.data_checks_path, strict=False)
        if settings.data_checks_reload
        else state.data_checks
    )
    if state.readonly_pool is not None:
        pool, url = state.readonly_pool, settings.database_url_readonly
    else:
        pool, url = state.pool, settings.database_url
    with pool.connection() as conn:
        return data_checks.report(conn, checks, url)
