"""The server schema stays identical to docs/schema.sql, and the seed works."""

from pathlib import Path

import psycopg
from fastapi.testclient import TestClient

import seed
from app.db import SCHEMA_SQL

DOCS_SCHEMA = Path(__file__).parents[2] / "docs" / "schema.sql"

_COLUMNS = """
SELECT table_name, column_name, data_type, is_nullable, column_default
FROM information_schema.columns WHERE table_schema = %s
ORDER BY table_name, column_name
"""
_CONSTRAINTS = """
SELECT conrelid::regclass::text AS tbl, conname, pg_get_constraintdef(oid) AS def
FROM pg_constraint WHERE connamespace = %s::regnamespace
ORDER BY 1, 2
"""
_INDEXES = """
SELECT tablename, indexname, replace(indexdef, %s || '.', '') AS def
FROM pg_indexes WHERE schemaname = %s ORDER BY 1, 2
"""


def _structure(conn: psycopg.Connection, schema: str) -> tuple:
    columns = conn.execute(_COLUMNS, (schema,)).fetchall()
    constraints = [
        {**c, "tbl": c["tbl"].split(".")[-1]}
        for c in conn.execute(_CONSTRAINTS, (schema,)).fetchall()
    ]
    indexes = conn.execute(_INDEXES, (schema, schema)).fetchall()

    def plain(rows: list[dict]) -> list[dict]:
        # Sequence names in defaults are schema-qualified: compare without it.
        return [
            {k: v.replace(f"{schema}.", "") if isinstance(v, str) else v for k, v in r.items()}
            for r in rows
        ]

    return plain(columns), plain(constraints), plain(indexes)


def _load(conn: psycopg.Connection, schema: str, sql: str) -> None:
    conn.execute(f"DROP SCHEMA IF EXISTS {schema} CASCADE")
    conn.execute(f"CREATE SCHEMA {schema}")
    conn.execute(f"SET search_path TO {schema}")
    conn.execute(sql)
    conn.execute("SET search_path TO public")


def test_server_schema_matches_docs_schema(db: psycopg.Connection) -> None:
    _load(db, "from_docs", DOCS_SCHEMA.read_text(encoding="utf-8"))
    _load(db, "from_server", SCHEMA_SQL.read_text(encoding="utf-8"))
    try:
        docs = _structure(db, "from_docs")
        server = _structure(db, "from_server")
        assert docs[0], "docs/schema.sql created no tables"
        assert server == docs
    finally:
        db.execute("DROP SCHEMA from_docs CASCADE")
        db.execute("DROP SCHEMA from_server CASCADE")


def test_seed_builds_a_demo_where_the_team_starts_unregistered(
    db: psycopg.Connection, client: TestClient
) -> None:
    seed.seed(db, "qatys2026", rounds=4)

    assert db.execute("SELECT COUNT(*) AS n FROM student").fetchone()["n"] == 10
    assert db.execute("SELECT COUNT(*) AS n FROM community").fetchone()["n"] == 5
    assert db.execute("SELECT COUNT(*) AS n FROM event").fetchone()["n"] == 8

    login = client.post(
        "/api/v1/auth/login", json={"email": "nurassyl@kbtu.kz", "password": "qatys2026"}
    )
    headers = {"Authorization": f"Bearer {login.json()['token']}"}
    feed = client.get("/api/v1/feed", headers=headers).json()["items"]

    titles = [e["title"] for e in feed]
    assert titles == ["Flutter workshop", "CV clinic", "IT Job Fair", "Autumn Hackathon 2026"]
    assert all(e["my_status"] is None for e in feed)
    by_title = {e["title"]: e for e in feed}
    assert by_title["Flutter workshop"]["free_places"] == 1
    assert by_title["CV clinic"]["free_places"] == 0

    admin = client.post(
        "/api/v1/auth/login", json={"email": "union@kbtu.kz", "password": "qatys2026"}
    )
    assert admin.status_code == 200
