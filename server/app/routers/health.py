from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

router = APIRouter(tags=["health"])


@router.get("/health", summary="Server and database are reachable")
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
