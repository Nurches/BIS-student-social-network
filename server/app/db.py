"""PostgreSQL access with psycopg 3 and plain SQL.

Business rules are written as the SQL in docs/api.md, so the code can be read
next to the document. Every connection runs in UTC.
"""

from pathlib import Path

from fastapi import Request
from psycopg import Connection
from psycopg.rows import DictRow, dict_row
from psycopg_pool import ConnectionPool

SCHEMA_SQL = Path(__file__).with_name("schema.sql")

Conn = Connection[DictRow]
Pool = ConnectionPool[Conn]


def create_pool(database_url: str, *, max_size: int = 10) -> ConnectionPool[Conn]:
    return ConnectionPool(
        database_url,
        min_size=1,
        max_size=max_size,
        # Autocommit: a statement outside `conn.transaction()` commits at once,
        # and every `with conn.transaction():` block is a real BEGIN/COMMIT.
        kwargs={"row_factory": dict_row, "autocommit": True, "options": "-c timezone=UTC"},
        # A sleeping free-tier database can take a few seconds to wake up.
        timeout=15,
        open=False,
        check=ConnectionPool.check_connection,
    )


def get_pool(request: Request) -> "Pool":
    """FastAPI dependency. Endpoints take a connection with
    `with pool.connection() as conn:` inside their own function.

    Not a `yield` dependency on purpose: FastAPI runs the two halves of a sync
    `yield` dependency and the endpoint in different worker threads, so under
    load every worker thread waits for a pooled connection while the threads
    holding connections wait for a free worker — a deadlock found by the
    load test (loadtest/locustfile.py).
    """
    return request.app.state.pool


def apply_schema(conn: Conn) -> None:
    """Drops and recreates every table (used by seed.py and the tests)."""
    with conn.transaction():
        conn.execute(SCHEMA_SQL.read_text(encoding="utf-8"))  # type: ignore[arg-type]
