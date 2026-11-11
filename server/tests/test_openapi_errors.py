"""D-01 (Week 11): Swagger shows the errors every route can really return.

The codes are not copied by hand into the test. A static walk over the code
follows each route into the services and dependencies it calls and collects
every `ApiError(status, "code")` it can reach; the route's OpenAPI responses
must list exactly those codes (plus the framework's 422/413), no more, no less.
Then real answers are compared with the documented examples.
"""

import ast
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import get_args

import psycopg
import pytest
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient
from pydantic import AwareDatetime

import app as app_package
from app.config import Settings
from app.errors import ERRORS, FRAMEWORK_CODES, example_body
from app.main import API_PREFIX, create_app
from app.routers import (
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

from .conftest import PASSWORD, Data

APP_DIR = Path(app_package.__file__).parent
FunctionKey = tuple[str, str]  # ("services.events", "publish")


# ---------- static walk over the code ----------


class CodeIndex:
    def __init__(self) -> None:
        self.functions: dict[FunctionKey, ast.FunctionDef] = {}
        self.imported_names: dict[str, dict[str, FunctionKey]] = {}
        self.imported_modules: dict[str, dict[str, str]] = {}
        for path in APP_DIR.rglob("*.py"):
            module = ".".join(path.relative_to(APP_DIR).with_suffix("").parts)
            tree = ast.parse(path.read_text(encoding="utf-8"))
            names: dict[str, FunctionKey] = {}
            modules: dict[str, str] = {}
            for node in ast.walk(tree):
                if isinstance(node, ast.FunctionDef):
                    self.functions[(module, node.name)] = node
                elif isinstance(node, ast.ImportFrom) and node.level == 2:
                    for alias in node.names:
                        local = alias.asname or alias.name
                        if node.module is None:  # from .. import x
                            modules[local] = alias.name
                        else:  # from ..services import events / from ..security import f
                            target = f"{node.module}.{alias.name}"
                            if (APP_DIR / Path(*target.split("."))).with_suffix(".py").exists():
                                modules[local] = target
                            else:
                                names[local] = (node.module, alias.name)
            self.imported_names[module] = names
            self.imported_modules[module] = modules

    def _resolve(self, module: str, func: ast.expr) -> FunctionKey | None:
        if isinstance(func, ast.Name):
            if (module, func.id) in self.functions:
                return (module, func.id)
            return self.imported_names[module].get(func.id)
        if isinstance(func, ast.Attribute) and isinstance(func.value, ast.Name):
            target = self.imported_modules[module].get(func.value.id)
            if target is not None:
                return (target, func.attr)
        return None

    def codes(self, key: FunctionKey, seen: set[FunctionKey] | None = None) -> set[tuple[int, str]]:
        seen = seen if seen is not None else set()
        if key in seen or key not in self.functions:
            return set()
        seen.add(key)
        module, _ = key
        found: set[tuple[int, str]] = set()
        for node in ast.walk(self.functions[key]):
            if not isinstance(node, ast.Call):
                continue
            if isinstance(node.func, ast.Name) and node.func.id == "ApiError":
                status, code = (a.value for a in node.args[:2])  # type: ignore[attr-defined]
                found.add((status, code))
                continue
            targets = [node.func]
            if isinstance(node.func, ast.Name) and node.func.id == "Depends" and node.args:
                targets = [node.args[0]]  # Depends(current_student) runs current_student
            for target in targets:
                resolved = self._resolve(module, target)
                if resolved is not None:
                    found |= self.codes(resolved, seen)
        return found


INDEX = CodeIndex()
# Only the OpenAPI document is read: the pool of this app is never opened.
APP = create_app(
    Settings(
        database_url="postgresql://unused@localhost/unused",
        jwt_secret="test-secret-that-is-at-least-32-characters",
        _env_file=None,  # type: ignore[call-arg]
    )
)
OPENAPI = APP.openapi()
# (full path, route) of every documented endpoint, read from the routers themselves.
ROUTES = [
    (API_PREFIX + route.path, route)
    for module in (
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
    )
    for route in module.router.routes
    if isinstance(route, APIRoute) and route.include_in_schema
]


def documented(path: str, method: str) -> dict[int, set[str]]:
    responses = OPENAPI["paths"][path][method.lower()]["responses"]
    result: dict[int, set[str]] = {}
    for status, entry in responses.items():
        examples = entry.get("content", {}).get("application/json", {}).get("examples", {})
        codes = {e["value"]["error"] for e in examples.values() if "error" in e["value"]}
        if codes:
            result[int(status)] = codes
    return result


def documented_example(path: str, method: str, status: int, code: str) -> dict:
    content = OPENAPI["paths"][path][method.lower()]["responses"][str(status)]["content"]
    return content["application/json"]["examples"][code]["value"]


def _is_timestamp(annotation: object) -> bool:
    """`AwareDatetime`, or `AwareDatetime | None` of a PATCH body."""
    return annotation is AwareDatetime or AwareDatetime in get_args(annotation)


def expected(route: APIRoute) -> set[tuple[int, str]]:
    module = route.endpoint.__module__.removeprefix("app.")
    codes = INDEX.codes((module, route.endpoint.__name__))
    dependant = route.dependant
    if dependant.path_params or dependant.query_params or dependant.body_params:
        codes.add((422, "validation_failed"))
    if route.body_field is not None:
        codes.add((413, "payload_too_large"))
        body_model = dependant.body_params[0].field_info.annotation
        if any(_is_timestamp(f.annotation) for f in body_model.model_fields.values()):
            codes.add((422, "timestamp_without_offset"))
    return codes


# ---------- static tests ----------


def test_the_walk_finds_codes_through_services_and_dependencies() -> None:
    # Sanity check of the walk itself, so an empty result cannot pass silently.
    publish = INDEX.codes(("routers.admin", "publish"))
    assert (401, "unauthorized") in publish  # Depends(current_student) in security.py
    assert (422, "deadline_in_the_past") in publish  # services/events.py
    login = INDEX.codes(("routers.auth", "login"))
    assert (429, "too_many_requests") in login  # dependencies=[Depends(limit_login_rate)]
    assert (423, "account_locked") in login


def test_every_api_error_in_the_code_is_in_the_catalog_with_its_status() -> None:
    raised = set().union(*(INDEX.codes(key) for key in INDEX.functions))
    assert raised, "no ApiError found: the walk is broken"
    for status, code in raised:
        assert code in ERRORS, f"{code} is raised but missing from app/errors.py ERRORS"
        assert ERRORS[code].status == status, code


@pytest.mark.parametrize(
    ("path", "route"), ROUTES, ids=[f"{sorted(r.methods)[0]} {p}" for p, r in ROUTES]
)
def test_route_documents_exactly_the_errors_it_can_return(path: str, route: APIRoute) -> None:
    (method,) = route.methods
    docs = {(status, code) for status, codes in documented(path, method).items() for code in codes}
    want = expected(route)
    if path.endswith("/health"):
        want.add((503, "database_unavailable"))  # answered by the route itself

    assert want - docs == set(), "raised but not in Swagger"
    assert docs - want == set(), "in Swagger but never raised"


def test_framework_codes_are_in_the_catalog() -> None:
    assert set(ERRORS) >= FRAMEWORK_CODES


def test_default_fastapi_422_schema_is_replaced_by_ours() -> None:
    assert len(ROUTES) == 33
    for path, route in ROUTES:
        (method,) = route.methods
        entry = OPENAPI["paths"][path][method.lower()]["responses"].get("422")
        if entry is not None:
            schema = entry["content"]["application/json"]["schema"]["$ref"]
            assert schema.endswith("/ErrorOut"), path
    assert "HTTPValidationError" not in OPENAPI["components"]["schemas"]


# ---------- documented examples match real answers ----------


def test_401_matches_the_documented_body(client: TestClient) -> None:
    response = client.get("/api/v1/feed")
    assert response.status_code == 401
    assert response.json() == documented_example("/api/v1/feed", "GET", 401, "unauthorized")


def _publish_body(deadline: datetime) -> dict:
    return {
        "title": "Career Day",
        "starts_at": (deadline + timedelta(days=2)).isoformat(),
        "registration_deadline": deadline.isoformat(),
        "participant_limit": 2,
    }


PUBLISH = "/api/v1/communities/{community_id}/events"


def test_403_and_422_deadline_match_the_documented_bodies(client: TestClient, data: Data) -> None:
    admin = data.student()
    community = data.community(admin)
    student = data.student()

    forbidden = client.post(
        PUBLISH.format(community_id=community),
        json=_publish_body(datetime.now(UTC) + timedelta(days=3)),
        headers=data.headers(student),
    )
    assert forbidden.status_code == 403
    assert forbidden.json() == documented_example(PUBLISH, "POST", 403, "not_a_confirmed_admin")

    past = client.post(
        PUBLISH.format(community_id=community),
        json=_publish_body(datetime.now(UTC) - timedelta(hours=1)),
        headers=data.headers(admin),
    )
    assert past.status_code == 422
    assert past.json() == documented_example(PUBLISH, "POST", 422, "deadline_in_the_past")


def test_422_validation_failed_has_the_documented_shape(client: TestClient, data: Data) -> None:
    admin = data.student()
    community = data.community(admin)
    body = _publish_body(datetime.now(UTC) + timedelta(days=3))
    del body["title"]

    response = client.post(
        PUBLISH.format(community_id=community), json=body, headers=data.headers(admin)
    )

    assert response.status_code == 422
    real = response.json()
    example = documented_example(PUBLISH, "POST", 422, "validation_failed")
    assert real == example  # the example is exactly this mistake: a missing title


def test_423_matches_the_documented_body(client: TestClient, data: Data) -> None:
    data.student("locked@kbtu.kz")
    for _ in range(5):
        wrong = client.post(
            "/api/v1/auth/login", json={"email": "locked@kbtu.kz", "password": "wrong-password"}
        )
        assert wrong.status_code == 401

    response = client.post(
        "/api/v1/auth/login", json={"email": "locked@kbtu.kz", "password": PASSWORD}
    )

    assert response.status_code == 423
    assert response.json() == documented_example(
        "/api/v1/auth/login", "POST", 423, "account_locked"
    )
    assert response.json() == example_body("account_locked")
    assert int(response.headers["Retry-After"]) > 0


def test_swagger_is_served_with_the_error_examples(
    client: TestClient, db: psycopg.Connection
) -> None:
    spec = client.get("/openapi.json").json()
    login = spec["paths"]["/api/v1/auth/login"]["post"]["responses"]
    assert set(login) >= {"200", "401", "413", "422", "423", "429"}
    assert "Retry-After" in login["423"]["headers"]
