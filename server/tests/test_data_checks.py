"""The /data-checks tool (docs/tools/data-checks-spec.md §9).

The most important tests inject a violation into a clean database and expect
exactly that check to fail: they turn "0 rows" from "maybe the query is wrong"
into "the query is proven to catch the problem".
"""

from collections.abc import Iterator
from pathlib import Path

import psycopg
import pytest
from fastapi.testclient import TestClient

import seed
from app.config import DATA_CHECKS_FILE, Settings
from app.main import create_app
from app.security import data_checks_rate_limiter, hash_password
from app.services import data_checks
from app.services.data_checks import Check, DataChecksFileError, load_checks, parse_checks

from .conftest import TEST_DATABASE_URL, FakePushSender

URL = "/api/v1/admin/data-checks"
SEED_PASSWORD = "qatys2026"
SHIPPED = load_checks(DATA_CHECKS_FILE)
IDS = [f"C{n:02d}" for n in range(1, 10)]


def block(
    check_id: str,
    body: str,
    *,
    title: str = "A rule",
    requirement: str = "FR-03",
    sensitive: str = "false",
) -> str:
    return (
        f"-- @check {check_id}\n-- @title {title}\n-- @requirement {requirement}\n"
        f"-- @sensitive {sensitive}\n{body}\n\n"
    )


@pytest.fixture
def seeded(db: psycopg.Connection) -> psycopg.Connection:
    # Cost 12 as in production, so C08 sees real hashes.
    seed.seed(db, SEED_PASSWORD, rounds=12)
    return db


def run(conn: psycopg.Connection, checks: list[Check] = SHIPPED) -> dict[str, dict]:
    return {r["id"]: r for r in data_checks.run_checks(conn, checks)}


def not_passing(results: dict[str, dict]) -> set[str]:
    return {check_id for check_id, r in results.items() if r["status"] != "pass"}


def headers(client: TestClient, email: str) -> dict[str, str]:
    response = client.post("/api/v1/auth/login", json={"email": email, "password": SEED_PASSWORD})
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['token']}"}


@pytest.fixture
def custom_client(
    settings: Settings, db: psycopg.Connection, push: FakePushSender, tmp_path: Path
) -> Iterator:
    """`custom_client(sql_text, **settings)`: an app that runs another check file."""
    clients: list[TestClient] = []

    def make(text: str, **overrides: object) -> TestClient:
        path = tmp_path / "data_checks.sql"
        path.write_text(text, encoding="utf-8")
        app = create_app(settings.model_copy(update={"data_checks_path": path, **overrides}), push)
        client = TestClient(app)
        client.__enter__()
        clients.append(client)
        return client

    data_checks_rate_limiter.reset()
    yield make
    for client in clients:
        client.__exit__(None, None, None)


# ---------- file format ----------


def test_parser_reads_the_shipped_file_9_selects() -> None:
    assert [c.id for c in SHIPPED] == IDS
    assert all(c.error is None and c.sql for c in SHIPPED)
    assert all(c.sql.lstrip().upper().startswith(("SELECT", "WITH")) for c in SHIPPED)
    assert all(not c.sql.rstrip().endswith(";") for c in SHIPPED)
    by_id = {c.id: c for c in SHIPPED}
    assert by_id["C08"].sensitive is True
    assert [c.id for c in SHIPPED if c.sensitive] == ["C08"]
    assert (
        by_id["C07"].note
        == "If this returns rows, a cancellation did not promote the waiting list."
    )
    assert by_id["C07"].requirement == "FR-03"


def test_duplicate_id_stops_the_server_at_start(settings: Settings, tmp_path: Path) -> None:
    path = tmp_path / "data_checks.sql"
    path.write_text(block("C01", "SELECT 1 WHERE false;") * 2, encoding="utf-8")

    with pytest.raises(DataChecksFileError, match="duplicate @check id C01"):
        load_checks(path)
    with pytest.raises(DataChecksFileError, match="duplicate"):
        create_app(settings.model_copy(update={"data_checks_path": path}))
    # Debug-mode reloads show it on the page instead.
    assert [c.error for c in load_checks(path, strict=False)] == ["duplicate @check id C01"] * 2


def test_missing_title_makes_only_that_block_an_error() -> None:
    text = (
        block("C01", "SELECT 1 WHERE false;")
        + "-- @check C02\n-- @requirement FR-03\n-- @sensitive false\nSELECT 1;\n\n"
        + block("C03", "SELECT 1 WHERE false;")
    )
    checks = parse_checks(text)

    assert [(c.id, c.error) for c in checks] == [
        ("C01", None),
        ("C02", "missing @title"),
        ("C03", None),
    ]
    assert checks[1].sql is None


@pytest.mark.parametrize(
    ("body", "error"),
    [
        ("UPDATE event SET title = 'x';", "not a SELECT"),
        ("DELETE FROM event;", "not a SELECT"),
        ("SELECT 1", "the SELECT must end with ';'"),
        ("SELECT 1; SELECT 2;", "only one statement per check"),
        ("SELECT 1) AS c; UPDATE event SET title = 'x'; --", "only one statement per check"),
        ("", "no SELECT after the metadata lines"),
    ],
)
def test_parser_refuses_anything_but_one_select(body: str, error: str) -> None:
    [check] = parse_checks(block("C01", body))
    assert check.error == error
    assert check.sql is None


@pytest.mark.parametrize(
    "body",
    [
        "select ';' AS semicolon_in_a_string WHERE false;",
        "WITH x AS (SELECT 1 AS n) SELECT n FROM x WHERE n > 1;  -- trailing comment",
        "/* leading */ SELECT $$;$$ AS dollar_quoted WHERE false;",
    ],
)
def test_parser_accepts_select_and_with(body: str) -> None:
    [check] = parse_checks(block("C01", body))
    assert check.error is None


def test_parser_reports_bad_metadata() -> None:
    [bad_id, bad_requirement, bad_sensitive, long_title] = parse_checks(
        block("X1", "SELECT 1;")
        + block("C02", "SELECT 1;", requirement="FR-3")
        + block("C03", "SELECT 1;", sensitive="maybe")
        + block("C04", "SELECT 1;", title="x" * 101)
    )
    assert bad_id.error == "@check must be C and two digits, got 'X1'"
    assert bad_requirement.error is not None
    assert bad_requirement.error.startswith("unknown @requirement 'FR-3'")
    assert bad_sensitive.error == "@sensitive must be true or false"
    assert bad_sensitive.sensitive is True  # unclear = hidden
    assert long_title.error == "@title is longer than 100 characters"


# ---------- read only and time limit ----------


def test_an_update_in_the_file_is_refused_and_changes_nothing(seeded: psycopg.Connection) -> None:
    titles = seeded.execute("SELECT event_id, title FROM event ORDER BY 1").fetchall()
    sequence = seeded.execute("SELECT last_value FROM event_event_id_seq").fetchone()
    checks = parse_checks(
        block("C01", "UPDATE event SET title = 'x';")
        # These pass the parser; PostgreSQL itself refuses them (READ ONLY).
        + block("C02", "SELECT nextval('event_event_id_seq');")
        + block(
            "C03",
            "WITH changed AS (UPDATE event SET title = 'x' RETURNING 1) SELECT * FROM changed;",
        )
    )
    # Even a write that skipped the parser is refused by the transaction.
    checks.append(Check("C04", "t", "FR-03", False, None, sql="UPDATE event SET title = 'x'"))

    results = run(seeded, checks)

    assert {r["status"] for r in results.values()} == {"error"}
    assert results["C01"]["error"] == "not a SELECT"
    assert "read-only transaction" in results["C02"]["error"]
    assert results["C03"]["error"]
    assert results["C04"]["error"] is not None
    assert seeded.execute("SELECT event_id, title FROM event ORDER BY 1").fetchall() == titles
    assert seeded.execute("SELECT last_value FROM event_event_id_seq").fetchone() == sequence


def test_update_without_the_subquery_wrap_is_refused_by_read_only(db: psycopg.Connection) -> None:
    # Rule 1 on its own: the transaction the runner opens refuses any write.
    with pytest.raises(psycopg.errors.ReadOnlySqlTransaction), db.transaction():
        db.execute("SET TRANSACTION READ ONLY")
        db.execute("UPDATE event SET title = 'x'")


def test_a_slow_check_times_out_and_the_others_still_run(db: psycopg.Connection) -> None:
    checks = parse_checks(
        block("C01", "SELECT 1 WHERE false;")
        + block("C02", "SELECT pg_sleep(5);")
        + block("C03", "SELECT 1 WHERE false;")
    )

    results = run(db, checks)

    assert [r["status"] for r in results.values()] == ["pass", "error", "pass"]
    assert "statement timeout" in results["C02"]["error"]
    assert 2500 <= results["C02"]["duration_ms"] < 5000
    # SET LOCAL and the rollback leave the pooled connection as it was.
    assert db.execute("SHOW statement_timeout").fetchone()["statement_timeout"] == "0"
    assert db.info.transaction_status == psycopg.pq.TransactionStatus.IDLE


# ---------- the shipped checks on real data ----------


def test_seeded_database_passes_all_9_checks(
    seeded: psycopg.Connection, client: TestClient
) -> None:
    response = client.get(URL, headers=headers(client, "laila@kbtu.kz"))

    assert response.status_code == 200
    body = response.json()
    assert body["summary"] == {"total": 9, "passed": 9, "failed": 0, "errors": 0}
    assert [c["id"] for c in body["checks"]] == IDS
    assert body["duration_ms"] < 5000
    assert body["ran_at"].endswith("+00:00")


FLUTTER = "FROM student s, event e WHERE e.title = 'Flutter workshop'"
DEBATE = "FROM student s, event e WHERE e.title = 'Debate tournament'"

VIOLATIONS = {
    "C01": (
        [
            "INSERT INTO registration (student_id, event_id, status) "
            f"SELECT s.student_id, e.event_id, 'confirmed' {FLUTTER} "
            "AND s.email IN ('madina@kbtu.kz', 'laila@kbtu.kz')"
        ],
        "Flutter workshop",
    ),
    "C05": (
        ["UPDATE event SET status = 'published' WHERE title = 'Debate tournament'"],
        "Debate Society",
    ),
    "C06": (
        [
            "ALTER TABLE student DROP CONSTRAINT chk_university_email",
            "UPDATE student SET email = 'aru@gmail.com' WHERE email = 'aru@kbtu.kz'",
        ],
        "aru@gmail.com",
    ),
    "C07": (
        [
            "INSERT INTO registration (student_id, event_id, status) "
            f"SELECT s.student_id, e.event_id, 'waiting_list' {FLUTTER} "
            "AND s.email = 'madina@kbtu.kz'"
        ],
        "Flutter workshop",
    ),
    "C08": (["UPDATE student SET password_hash = 'qatys2026' WHERE email = 'dias@kbtu.kz'"], None),
    "C09": (
        [
            "INSERT INTO notification (student_id, event_id) "
            f"SELECT s.student_id, e.event_id {DEBATE} AND s.email = 'akbota@kbtu.kz'"
        ],
        "draft",
    ),
}


@pytest.mark.parametrize("check_id", sorted(VIOLATIONS))
def test_an_injected_violation_fails_exactly_its_check(
    seeded: psycopg.Connection, check_id: str
) -> None:
    statements, expected_value = VIOLATIONS[check_id]
    assert not_passing(run(seeded)) == set()

    for statement in statements:
        seeded.execute(statement)
    results = run(seeded)

    assert not_passing(results) == {check_id}
    assert results[check_id]["status"] == "fail"
    assert results[check_id]["row_count"] == 1
    if expected_value is not None:
        assert expected_value in results[check_id]["rows"][0]


def test_c08_also_catches_a_bcrypt_hash_below_cost_12(seeded: psycopg.Connection) -> None:
    seeded.execute(
        "UPDATE student SET password_hash = %s WHERE email = 'dias@kbtu.kz'",
        (hash_password("qatys2026", 10),),
    )
    assert not_passing(run(seeded)) == {"C08"}


PROTECTED = {
    "C02": (
        "registration",
        "uq_registration",
        "INSERT INTO registration (student_id, event_id, status) "
        "SELECT student_id, event_id, 'cancelled' FROM registration LIMIT 1",
    ),
    "C03": (
        "notification",
        "uq_notification",
        "INSERT INTO notification (student_id, event_id, kind) "
        "SELECT student_id, event_id, kind FROM notification LIMIT 1",
    ),
    "C04": (
        "event",
        "chk_deadline_before_start",
        "UPDATE event SET registration_deadline = starts_at + INTERVAL '1 hour' "
        "WHERE title = 'IT Career Day'",
    ),
}


@pytest.mark.parametrize("check_id", sorted(PROTECTED))
def test_schema_refuses_the_violation_and_the_check_catches_it_without_the_constraint(
    seeded: psycopg.Connection, check_id: str
) -> None:
    table, constraint, statement = PROTECTED[check_id]

    with pytest.raises(psycopg.errors.IntegrityError) as refused:
        seeded.execute(statement)
    assert refused.value.diag.constraint_name == constraint
    assert not_passing(run(seeded)) == set()

    # Without the constraint, the check is the last line of defence.
    seeded.execute(f"ALTER TABLE {table} DROP CONSTRAINT {constraint}")
    seeded.execute(statement)
    assert not_passing(run(seeded)) == {check_id}


# ---------- endpoint ----------


def test_access_needs_a_token_and_the_allow_list(
    seeded: psycopg.Connection, client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    assert client.get(URL).status_code == 401
    assert client.get(URL).json() == {"error": "unauthorized"}
    assert client.get(URL, headers=headers(client, "madina@kbtu.kz")).status_code == 200

    def must_not_run(*_: object, **__: object) -> None:
        raise AssertionError("checks ran for a student outside the allow list")

    monkeypatch.setattr(data_checks, "run_checks", must_not_run)
    denied = client.get(URL, headers=headers(client, "aru@kbtu.kz"))
    assert denied.status_code == 403
    assert denied.json() == {"error": "not_allowed"}


def test_allow_list_comes_from_data_check_emails(
    monkeypatch: pytest.MonkeyPatch, seeded: psycopg.Connection, custom_client
) -> None:
    monkeypatch.setenv("DATA_CHECK_EMAILS", " Aru@KBTU.kz , dias@kbtu.kz,")
    settings = Settings(
        database_url=TEST_DATABASE_URL,
        jwt_secret="x" * 32,
        _env_file=None,  # type: ignore[call-arg]
    )
    assert settings.data_check_allow_list == {"aru@kbtu.kz", "dias@kbtu.kz"}

    client = custom_client(DATA_CHECKS_FILE.read_text(), data_check_emails="aru@kbtu.kz")
    assert client.get(URL, headers=headers(client, "aru@kbtu.kz")).status_code == 200
    assert client.get(URL, headers=headers(client, "laila@kbtu.kz")).status_code == 403


def test_second_run_within_10_seconds_is_429_per_student(
    seeded: psycopg.Connection, client: TestClient
) -> None:
    laila = headers(client, "laila@kbtu.kz")
    assert client.get(URL, headers=laila).status_code == 200

    again = client.get(URL, headers=laila)
    assert again.status_code == 429
    assert again.json() == {"error": "too_many_requests"}
    assert 1 <= int(again.headers["Retry-After"]) <= 10
    assert client.get(URL, headers=headers(client, "madina@kbtu.kz")).status_code == 200


def test_sensitive_check_returns_the_count_but_no_rows(
    seeded: psycopg.Connection, client: TestClient
) -> None:
    seeded.execute("UPDATE student SET password_hash = 'qatys2026' WHERE email = 'dias@kbtu.kz'")

    response = client.get(URL, headers=headers(client, "laila@kbtu.kz"))

    c08 = next(c for c in response.json()["checks"] if c["id"] == "C08")
    assert c08 == {**c08, "status": "fail", "row_count": 1, "columns": [], "rows": []}
    assert "dias@kbtu.kz" not in response.text
    assert "qatys2026" not in response.text


def test_fail_shows_count_up_to_20_rows_and_iso_timestamps(
    seeded: psycopg.Connection, custom_client
) -> None:
    client = custom_client(
        block("C01", "SELECT g AS n FROM generate_series(1, 25) AS g;")  # noqa: S608
        + block("C02", "SELECT title, starts_at FROM event WHERE title = 'IT Career Day';")
        + block("C03", "SELECT 1 FROM nowhere;")
        + "-- @check C04\n-- @requirement FR-03\n-- @sensitive false\nSELECT 1;\n"
    )

    body = client.get(URL, headers=headers(client, "laila@kbtu.kz")).json()

    many, timestamp, broken_sql, broken_block = body["checks"]
    assert body["summary"] == {"total": 4, "passed": 0, "failed": 2, "errors": 2}
    assert (many["row_count"], many["truncated"], len(many["rows"])) == (25, True, 20)
    assert many["columns"] == ["n"]
    assert many["rows"][0] == [1]
    assert timestamp["columns"] == ["title", "starts_at"]
    assert timestamp["rows"][0][1].endswith("+00:00")
    assert broken_sql["status"] == "error"
    assert broken_sql["error"] == 'relation "nowhere" does not exist'
    assert (broken_block["status"], broken_block["error"]) == ("error", "missing @title")
    # The label names the database, never the user or the password.
    assert body["database"].endswith("/ qatys_test")
    assert "qatys:" not in body["database"]


def test_a_10th_check_needs_only_the_sql_file(seeded: psycopg.Connection, custom_client) -> None:
    tenth = block("C10", "SELECT event_id FROM event WHERE participant_limit < 1;")
    client = custom_client(DATA_CHECKS_FILE.read_text() + "\n" + tenth)

    body = client.get(URL, headers=headers(client, "laila@kbtu.kz")).json()

    assert body["summary"] == {"total": 10, "passed": 10, "failed": 0, "errors": 0}
    assert body["checks"][-1]["id"] == "C10"


def test_debug_mode_rereads_the_file_on_every_run(
    seeded: psycopg.Connection, custom_client, tmp_path: Path
) -> None:
    client = custom_client(block("C01", "SELECT 1 WHERE false;"), data_checks_reload=True)
    laila = headers(client, "laila@kbtu.kz")
    assert client.get(URL, headers=laila).json()["summary"]["total"] == 1

    path = tmp_path / "data_checks.sql"
    path.write_text(path.read_text() + block("C02", "SELECT 1;"), encoding="utf-8")
    data_checks_rate_limiter.reset()

    body = client.get(URL, headers=laila).json()
    assert [(c["id"], c["status"]) for c in body["checks"]] == [("C01", "pass"), ("C02", "fail")]


def test_database_label_hides_credentials() -> None:
    label = data_checks.database_label
    neon = "postgresql://qatys:secret@ep-cool-1.eu-central-1.aws.neon.tech/qatys?sslmode=require"
    assert label(neon) == "neon / qatys"
    assert label("postgresql://qatys:qatys@localhost:5432/qatys_test") == "local / qatys_test"
    assert label("postgresql://u:p@dpg-abc.frankfurt-postgres.render.com/db") == "dpg-abc / db"


def test_page_is_served_without_external_scripts(client: TestClient) -> None:
    response = client.get("/data-checks")

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/html")
    assert "Copy as Markdown" in response.text
    assert "<script src" not in response.text
