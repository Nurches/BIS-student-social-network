from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

from ..errors import error_responses

router = APIRouter(tags=["health"])


@router.get(
    "/health",
    summary="Server and database are reachable",
    responses={
        200: {"content": {"application/json": {"example": {"status": "ok"}}}},
        **error_responses("database_unavailable"),
    },
)
def health(request: Request) -> JSONResponse:
    """No authentication. Only `200` means "reachable" for the app (brief §9)."""
    try:
        with request.app.state.pool.connection(timeout=5) as conn:
            conn.execute("SELECT 1")
    except Exception:
        return JSONResponse(
            {"status": "unavailable", "error": "database_unavailable"}, status_code=503
        )
    return JSONResponse({"status": "ok"})
