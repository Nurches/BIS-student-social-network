"""The error format of docs/api.md: `{ "error": "<code>" }` plus optional fields."""

import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

log = logging.getLogger("qatys")


class ApiError(Exception):
    def __init__(
        self,
        status: int,
        code: str,
        *,
        headers: dict[str, str] | None = None,
        **extra: object,
    ) -> None:
        super().__init__(code)
        self.status = status
        self.code = code
        self.headers = headers
        self.extra = extra


_HTTP_CODES = {
    404: "not_found",
    405: "method_not_allowed",
    413: "payload_too_large",
    429: "too_many_requests",
}


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def api_error(_: Request, exc: ApiError) -> JSONResponse:
        return JSONResponse(
            {"error": exc.code, **exc.extra}, status_code=exc.status, headers=exc.headers
        )

    @app.exception_handler(RequestValidationError)
    async def validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
        errors = exc.errors()
        # docs/api.md: a timestamp without an offset has its own error code.
        if any(e.get("type") == "timezone_aware" for e in errors):
            return JSONResponse({"error": "timestamp_without_offset"}, status_code=422)
        detail = [
            {"loc": list(e.get("loc", ())), "msg": e.get("msg"), "type": e.get("type")}
            for e in errors
        ]
        return JSONResponse({"error": "validation_failed", "detail": detail}, status_code=422)

    @app.exception_handler(StarletteHTTPException)
    async def http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        code = _HTTP_CODES.get(exc.status_code, "http_error")
        return JSONResponse({"error": code}, status_code=exc.status_code, headers=exc.headers)

    @app.exception_handler(Exception)
    async def unexpected(request: Request, exc: Exception) -> JSONResponse:
        # Logged with the traceback on the server, never sent to the client.
        log.exception("Unhandled error on %s %s", request.method, request.url.path)
        return JSONResponse({"error": "internal_error"}, status_code=500)
