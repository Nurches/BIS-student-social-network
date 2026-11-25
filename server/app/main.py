"""Qatys API — FastAPI application (docs/api.md v0.2).

Run locally:  uvicorn app.main:app --reload
"""

import logging
import re
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from .config import Settings, get_settings
from .db import create_pool
from .errors import install_error_handlers
from .routers import (
    admin,
    admin_panel,
    auth,
    communities,
    data_checks,
    devices,
    events,
    feed,
    health,
    me,
)
from .services.data_checks import load_checks
from .services.push import PushSender, create_sender

API_PREFIX = "/api/v1"
ADMIN_PAGE = Path(__file__).with_name("static") / "admin.html"
DATA_CHECKS_PAGE = Path(__file__).with_name("static") / "data_checks.html"

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")


# v5 (FR-08): the poster upload is the only body larger than 64 KB.
POSTER_UPLOAD_PATH = re.compile(rf"^{API_PREFIX}/admin/events/\d+/poster$")


class BodySizeLimit:
    """413 for bodies over the limit, also when no Content-Length is sent.

    `large` lists the paths allowed a bigger body: (pattern, limit, error code)."""

    def __init__(
        self,
        app: ASGIApp,
        max_bytes: int,
        large: tuple[tuple[re.Pattern[str], int, str], ...] = (),
    ) -> None:
        self.app = app
        self.max_bytes = max_bytes
        self.large = large

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        limit, code = self.max_bytes, "payload_too_large"
        for pattern, large_limit, large_code in self.large:
            if pattern.match(scope.get("path", "")):
                limit, code = large_limit, large_code
                break

        headers = dict(scope.get("headers") or [])
        declared = headers.get(b"content-length")
        if declared is not None and declared.isdigit() and int(declared) > limit:
            await _too_large(scope, receive, send, code)
            return

        received = 0

        async def limited_receive() -> Message:
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > limit:
                    raise _BodyTooLarge
            return message

        try:
            await self.app(scope, limited_receive, send)
        except _BodyTooLarge:
            await _too_large(scope, receive, send, code)


class _BodyTooLarge(Exception):
    pass


async def _too_large(scope: Scope, receive: Receive, send: Send, code: str) -> None:
    response = JSONResponse({"error": code}, status_code=413)
    await response(scope, receive, send)


def create_app(settings: Settings | None = None, push_sender: PushSender | None = None) -> FastAPI:
    settings = settings or get_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        pools = [app.state.pool]
        if app.state.readonly_pool is not None:
            pools.append(app.state.readonly_pool)
        for pool in pools:
            pool.open(wait=False)
        try:
            yield
        finally:
            for pool in pools:
                pool.close()

    app = FastAPI(
        title="Qatys API",
        version="0.2.0",
        description=(
            "Student social network of KBTU: one feed of events and a push at "
            "publication time. Contract: docs/api.md. **To publish as an admin:** "
            "`POST /api/v1/auth/login`, copy `token`, press *Authorize*, then "
            "`POST /api/v1/communities/{community_id}/events`."
        ),
        lifespan=lifespan,
        docs_url="/docs" if settings.enable_docs else None,
        redoc_url=None,
        openapi_url="/openapi.json" if settings.enable_docs else None,
    )
    app.state.settings = settings
    app.state.pool = create_pool(settings.database_url)
    app.state.readonly_pool = (
        create_pool(settings.database_url_readonly, max_size=2)
        if settings.database_url_readonly
        else None
    )
    # Parsed once at start; a duplicate check id stops the server here (spec §4).
    app.state.data_checks = load_checks(settings.data_checks_path)
    app.state.push_sender = push_sender or create_sender(settings)
    app.dependency_overrides[get_settings] = lambda: settings

    install_error_handlers(app)
    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
            allow_headers=["Authorization", "Content-Type"],
        )
    app.add_middleware(
        BodySizeLimit,
        max_bytes=settings.max_body_bytes,
        large=((POSTER_UPLOAD_PATH, settings.max_poster_bytes, "poster_too_large"),),
    )

    for router in (
        health,
        auth,
        feed,
        events,
        admin,
        admin_panel,
        devices,
        communities,
        me,
        data_checks,
    ):
        app.include_router(router.router, prefix=API_PREFIX)

    @app.get("/", include_in_schema=False)
    def root() -> RedirectResponse:
        return RedirectResponse("/docs" if settings.enable_docs else "/admin")

    @app.get("/admin", include_in_schema=False)
    def admin_page() -> FileResponse:
        return FileResponse(ADMIN_PAGE, media_type="text/html")

    @app.get("/data-checks", include_in_schema=False)
    def data_checks_page() -> FileResponse:
        return FileResponse(DATA_CHECKS_PAGE, media_type="text/html")

    return app


def __getattr__(name: str) -> FastAPI:
    # `uvicorn app.main:app` builds the app on first access, so importing this
    # module (tests, tools) does not require the production environment.
    if name == "app":
        globals()["app"] = application = create_app()
        return application
    raise AttributeError(name)
