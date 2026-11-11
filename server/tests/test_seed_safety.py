"""W11-10: a reseed of the live database cannot happen by accident, and the
demo starts from a clean, checked state."""

import psycopg
import pytest

import seed
from app.config import Settings

LIVE_URL = "postgresql://neondb_owner:s3cret-pw@ep-cool-name-123.eu-central-1.aws.neon.tech/neondb?sslmode=require"
LOCAL_URL = "postgresql://qatys:qatys@localhost:5432/qatys"


def never_asked(prompt: str) -> str:
    raise AssertionError(f"should not ask: {prompt}")


def test_target_is_printed_without_the_password(capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit):
        seed.confirm_target(LIVE_URL, yes=True, live=False, ask=never_asked)

    out = capsys.readouterr().out
    assert "neondb" in out and "ep-cool-name-123.eu-central-1.aws.neon.tech" in out
    assert "s3cret-pw" not in out and "neondb_owner" not in out


@pytest.mark.parametrize(
    "url",
    [
        LOCAL_URL,
        "postgresql://qatys:qatys@127.0.0.1:54329/qatys_test",
        "postgresql://qatys:qatys@db:5432/qatys",
    ],
)
def test_local_databases_need_only_yes(url: str) -> None:
    seed.confirm_target(url, yes=True, live=False, ask=never_asked)


def test_without_yes_nothing_runs() -> None:
    with pytest.raises(SystemExit, match="--yes"):
        seed.confirm_target(LOCAL_URL, yes=False, live=False, ask=never_asked)


def test_a_live_host_without_live_is_refused() -> None:
    with pytest.raises(SystemExit, match="--live"):
        seed.confirm_target(LIVE_URL, yes=True, live=False, ask=never_asked)


def test_a_live_host_needs_the_database_name_typed() -> None:
    with pytest.raises(SystemExit, match="does not match"):
        seed.confirm_target(LIVE_URL, yes=True, live=True, ask=lambda _: "qatys")
    with pytest.raises(SystemExit, match="does not match"):
        seed.confirm_target(LIVE_URL, yes=True, live=True, ask=lambda _: "")

    seed.confirm_target(LIVE_URL, yes=True, live=True, ask=lambda _: " neondb ")


def test_main_refuses_a_live_host_before_connecting(monkeypatch: pytest.MonkeyPatch) -> None:
    settings = Settings(
        database_url=LIVE_URL,
        jwt_secret="test-secret-that-is-at-least-32-characters",
        _env_file=None,  # type: ignore[call-arg]
    )
    monkeypatch.setattr(seed, "get_settings", lambda: settings)

    def no_connection(*args: object, **kwargs: object) -> None:
        raise AssertionError("connected to the live database")

    monkeypatch.setattr(seed.psycopg, "connect", no_connection)

    with pytest.raises(SystemExit):
        seed.main(["--yes"])


def test_readonly_role_comes_from_database_url_readonly() -> None:
    assert seed.readonly_role("") == "qatys_readonly"
    assert seed.readonly_role("postgresql://checker:pw@host/db") == "checker"


# ---------- after the reseed ----------


@pytest.fixture
def readonly_role(db: psycopg.Connection):
    # Roles belong to the whole PostgreSQL server: start clean, leave nothing behind.
    if db.execute("SELECT 1 FROM pg_roles WHERE rolname = 'qatys_readonly'").fetchone():
        db.execute("DROP OWNED BY qatys_readonly")
    else:
        db.execute("CREATE ROLE qatys_readonly NOLOGIN")
    yield "qatys_readonly"
    db.execute("RESET ROLE")
    db.execute("DROP OWNED BY qatys_readonly")
    db.execute("DROP ROLE qatys_readonly")


def test_the_readonly_role_can_read_every_table_after_a_reseed(
    db: psycopg.Connection, readonly_role: str
) -> None:
    seed.seed(db, "qatys2026", rounds=4)  # drops and recreates every table: grants are gone
    assert seed.grant_readonly(db, readonly_role) is True

    tables = [
        r["tablename"]
        for r in db.execute(
            "SELECT tablename FROM pg_tables WHERE schemaname = 'public'"
        ).fetchall()
    ]
    assert "event" in tables
    db.execute(f"SET ROLE {readonly_role}")
    for table in tables:
        db.execute(f"SELECT 1 FROM {table} LIMIT 1")  # noqa: S608 — names from pg_tables
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        db.execute("UPDATE event SET title = 'x'")
    db.execute("RESET ROLE")


def test_grant_is_skipped_when_the_role_does_not_exist(db: psycopg.Connection) -> None:
    assert seed.grant_readonly(db, "no_such_role_qatys") is False


def test_demo_accounts_follow_both_clubs_and_career_day_is_not_seeded(
    db: psycopg.Connection,
) -> None:
    seed.seed(db, "qatys2026", rounds=4)

    rows = db.execute(
        """
        SELECT s.email, ARRAY_AGG(c.name ORDER BY c.name) AS clubs
        FROM student s
        JOIN subscription sub USING (student_id)
        JOIN community c USING (community_id)
        WHERE s.email IN ('nurassyl@kbtu.kz', 'madina@kbtu.kz', 'laila@kbtu.kz')
        GROUP BY s.email
        """
    ).fetchall()
    assert len(rows) == 3
    assert all({"IT Club", "Career Center"} <= set(r["clubs"]) for r in rows)
    # "Career Day" is published live in the demo (2 places): no look-alike in the feed.
    same_name = db.execute("SELECT title FROM event WHERE title ILIKE '%career day%'").fetchall()
    assert same_name == []
    # The demo phones start with no registrations anywhere.
    mine = db.execute(
        "SELECT COUNT(*) AS n FROM registration r JOIN student s USING (student_id) "
        "WHERE s.email IN ('nurassyl@kbtu.kz', 'madina@kbtu.kz', 'laila@kbtu.kz')"
    ).fetchone()
    assert mine["n"] == 0
