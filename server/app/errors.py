"""The error format of docs/api.md: `{ "error": "<code>" }` plus optional fields."""

import logging
from dataclasses import dataclass
from typing import Any

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


@dataclass(frozen=True)
class ErrorDoc:
    status: int
    when: str
    body: dict[str, object] | None = None  # default: {"error": <code>}
    retry_after_header: bool = False


# Every error code the server answers, for Swagger (D-01). The codes come from
# the ApiError(...) calls and the handlers below; tests/test_openapi_errors.py
# checks that each route documents exactly the codes it can really raise.
ERRORS: dict[str, ErrorDoc] = {
    "unauthorized": ErrorDoc(401, "Token missing, malformed, forged or expired"),
    "invalid_credentials": ErrorDoc(401, "Unknown email or wrong password (same answer)"),
    "not_a_confirmed_admin": ErrorDoc(
        403, "BR-01: not the owner, or the community is not confirmed"
    ),
    "not_allowed": ErrorDoc(403, "Not in the DATA_CHECK_EMAILS allow list; nothing runs"),
    "not_an_admin": ErrorDoc(403, "Admin panel: not a moderator and owns no community"),
    "moderator_only": ErrorDoc(403, "Admin panel: only a Student Union moderator may do this"),
    "not_your_community": ErrorDoc(
        403, "Admin panel: not the owner of this community and not a moderator"
    ),
    "event_not_found": ErrorDoc(404, "No such event (students: also a draft or cancelled one)"),
    "community_not_found": ErrorDoc(404, "No such community"),
    "not_registered": ErrorDoc(404, "No active registration of this student"),
    "student_not_found": ErrorDoc(404, "No student with this id or email"),
    "email_already_registered": ErrorDoc(409, "An account with this email exists"),
    "already_registered": ErrorDoc(409, "Already confirmed or on the waiting list"),
    "community_name_taken": ErrorDoc(409, "Another community already has this name"),
    "event_cancelled": ErrorDoc(409, "The event is cancelled and cannot be changed"),
    "limit_below_confirmed": ErrorDoc(
        409, "The new participant limit is below the number of confirmed students"
    ),
    "cannot_change_own_role": ErrorDoc(409, "A moderator cannot remove their own role"),
    "deadline_passed": ErrorDoc(410, "FR-02: the registration deadline has passed"),
    "event_started": ErrorDoc(410, "Cancelling after the event started"),
    "payload_too_large": ErrorDoc(413, "Body over 64 KB, refused before parsing"),
    "validation_failed": ErrorDoc(
        422,
        "The body, path or query does not match the contract",
        {
            "error": "validation_failed",
            "detail": [{"loc": ["body", "title"], "msg": "Field required", "type": "missing"}],
        },
    ),
    "timestamp_without_offset": ErrorDoc(422, "A timestamp without a time zone offset"),
    "not_a_university_email": ErrorDoc(422, "BR-01: only @kbtu.kz addresses"),
    "password_too_short": ErrorDoc(422, "Fewer than 8 characters"),
    "password_too_long": ErrorDoc(422, "More than 72 bytes (bcrypt reads only 72)"),
    "invalid_cursor": ErrorDoc(422, "`cursor` is not a `next_cursor` of this server"),
    "deadline_in_the_past": ErrorDoc(422, "FR-02: the registration deadline is in the past"),
    "deadline_after_event_start": ErrorDoc(422, "The deadline is after `starts_at`"),
    "account_locked": ErrorDoc(
        423,
        "NFR-02: 5 wrong passwords in 10 min lock the account for 15 min, "
        "even for the right password",
        {"error": "account_locked", "retry_after_minutes": 15},
        retry_after_header=True,
    ),
    "too_many_requests": ErrorDoc(429, "Rate limit; wait `Retry-After` seconds", None, True),
    "database_unavailable": ErrorDoc(
        503,
        "The server runs but cannot reach PostgreSQL",
        {"status": "unavailable", "error": "database_unavailable"},
    ),
}

# Answered by the framework for any route with parameters or a body.
FRAMEWORK_CODES = frozenset({"validation_failed", "timestamp_without_offset", "payload_too_large"})


def example_body(code: str) -> dict[str, object]:
    doc = ERRORS[code]
    return doc.body if doc.body is not None else {"error": code}


def error_responses(*codes: str) -> dict[int | str, dict[str, Any]]:
    """`responses=` for a route: one entry per status, one example per code."""
    from .schemas import ErrorOut  # schemas never imports this module

    by_status: dict[int, list[str]] = {}
    for code in codes:
        by_status.setdefault(ERRORS[code].status, []).append(code)

    responses: dict[int | str, dict[str, Any]] = {}
    for status, group in sorted(by_status.items()):
        entry: dict[str, Any] = {
            "model": ErrorOut,
            "description": "<br>".join(f"`{c}`: {ERRORS[c].when}" for c in group),
            "content": {
                "application/json": {
                    "examples": {
                        c: {"summary": ERRORS[c].when, "value": example_body(c)} for c in group
                    }
                }
            },
        }
        if any(ERRORS[c].retry_after_header for c in group):
            entry["headers"] = {
                "Retry-After": {
                    "description": "Seconds to wait before trying again",
                    "schema": {"type": "integer"},
                }
            }
        responses[status] = entry
    return responses


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
