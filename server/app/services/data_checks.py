"""Data checks of the /data-checks tool page (docs/tools/data-checks-spec.md).

The checks themselves live in app/checks/data_checks.sql, owned by the Data &
Database member. This module only parses and runs that file, so adding or
changing a check never needs a code change.

Every run is one READ ONLY transaction with a statement timeout, rolled back at
the end. Even a write that slipped past the parser is refused by PostgreSQL.
"""

import math
import re
import time
from collections import Counter
from dataclasses import dataclass, replace
from datetime import UTC, date, datetime
from datetime import time as clock_time
from pathlib import Path

import psycopg
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict
from psycopg.rows import tuple_row

from ..db import Conn

ROW_CAP = 20  # rows shown per failing check
STATEMENT_TIMEOUT = "3s"
TITLE_MAX = 100

_FIELDS = ("check", "title", "requirement", "sensitive")
_META = re.compile(r"--\s*@(\w+)[ \t]*(.*)")
_ID = re.compile(r"C\d{2}")
_REQUIREMENT = re.compile(r"(?:FR|NFR|BR)-\d{2}|—")
_COMMENTS = re.compile(r"(?:\s+|--[^\n]*|/\*.*?\*/)*", re.DOTALL)
_DOLLAR_TAG = re.compile(r"\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$")


class DataChecksFileError(Exception):
    """The file cannot be used at all: missing, or two checks share an id."""


@dataclass(frozen=True)
class Check:
    id: str
    title: str | None
    requirement: str | None
    sensitive: bool
    note: str | None
    # The SELECT without its final ';'. None when the block is broken; then
    # `error` says why and the check is shown as Error without being run.
    sql: str | None
    error: str | None = None


# ---------- parser ----------


def load_checks(path: Path, *, strict: bool = True) -> list[Check]:
    """Reads the check file. `strict` (server start) refuses duplicate ids;
    otherwise they are shown as Error, like every other format mistake."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise DataChecksFileError(f"cannot read {path}: {exc}") from exc
    checks = parse_checks(text)
    if strict:
        duplicates = sorted({c.id for c in checks if c.error and c.error.startswith("duplicate")})
        if duplicates:
            raise DataChecksFileError(
                f"{path}: duplicate @check id {', '.join(duplicates)}; every id must be unique"
            )
    return checks


def parse_checks(text: str) -> list[Check]:
    """Every block starts at a `-- @check` line; text before the first one is a
    file header. A broken block becomes a Check with `error`, never an exception."""
    blocks: list[list[str]] = []
    for line in text.splitlines():
        meta = _META.fullmatch(line.strip())
        if meta and meta.group(1) == "check":
            blocks.append([])
        if blocks:
            blocks[-1].append(line)

    checks = [_parse_block(block) for block in blocks]
    seen = Counter(c.id for c in checks)
    return [
        replace(c, sql=None, error=f"duplicate @check id {c.id}") if seen[c.id] > 1 else c
        for c in checks
    ]


def _parse_block(lines: list[str]) -> Check:
    meta: dict[str, str] = {}
    note: list[str] = []
    problems: list[str] = []
    body_start = len(lines)
    for i, line in enumerate(lines):
        stripped = line.strip()
        if not stripped:
            continue
        match = _META.fullmatch(stripped)
        if match:
            key, value = match.group(1), match.group(2).strip()
            if key not in _FIELDS:
                problems.append(f"unknown field @{key}")
            elif key in meta:
                problems.append(f"@{key} is given twice")
            else:
                meta[key] = value
        elif stripped.startswith("--"):
            note.append(stripped[2:].strip())
        else:
            body_start = i
            break

    check_id = meta.get("check", "")
    if not _ID.fullmatch(check_id):
        problems.insert(0, f"@check must be C and two digits, got {check_id!r}")

    title = meta.get("title") or None
    if title is None:
        problems.append("missing @title")
    elif len(title) > TITLE_MAX:
        problems.append(f"@title is longer than {TITLE_MAX} characters")

    requirement = meta.get("requirement")
    if requirement == "-":
        requirement = "—"
    if requirement is None:
        problems.append("missing @requirement")
    elif not _REQUIREMENT.fullmatch(requirement):
        problems.append(
            f"unknown @requirement {requirement!r}: use an ID from requirements.md "
            "(FR-01, NFR-01, BR-01, ...) or —"
        )

    sensitive = meta.get("sensitive", "").lower()
    if sensitive not in ("true", "false"):
        problems.append("@sensitive must be true or false")

    statement, statement_problem = _single_select("\n".join(lines[body_start:]))
    if statement_problem:
        problems.append(statement_problem)

    return Check(
        id=check_id or "?",
        title=title,
        requirement=requirement,
        sensitive=sensitive != "false",  # anything unclear hides the rows
        note=" ".join(note) or None,
        sql=None if problems else statement,
        error="; ".join(problems) or None,
    )


def _single_select(body: str) -> tuple[str | None, str | None]:
    """Returns (statement, None) or (None, problem). The statement must be
    exactly one SELECT (or WITH) ending with ';'."""
    if not _strip_comments(body):
        return None, "no SELECT after the metadata lines"
    split = _split_at_semicolon(body)
    if split is None:
        return None, "the SELECT must end with ';'"
    statement, rest = split
    if _strip_comments(rest):
        return None, "only one statement per check"
    statement = _strip_comments(statement)
    if not re.match(r"(?:select|with)\b", statement, re.IGNORECASE):
        return None, "not a SELECT"
    return statement, None


def _strip_comments(text: str) -> str:
    """Drops leading whitespace and comments, and trailing whitespace."""
    return text[_COMMENTS.match(text).end() :].rstrip()  # type: ignore[union-attr]


def _split_at_semicolon(body: str) -> tuple[str, str] | None:
    """Splits at the first ';' outside quotes, dollar quotes and comments."""
    i, n = 0, len(body)
    while i < n:
        if body.startswith("--", i):
            end = body.find("\n", i)
            i = n if end < 0 else end
        elif body.startswith("/*", i):
            end = body.find("*/", i + 2)
            i = n if end < 0 else end + 2
        elif body[i] in "'\"":
            quote, i = body[i], i + 1
            while i < n:
                if body[i] == quote:
                    if body.startswith(quote * 2, i):  # '' inside a string
                        i += 2
                        continue
                    break
                i += 1
            i += 1
        elif tag := _DOLLAR_TAG.match(body, i):
            end = body.find(tag.group(), tag.end())
            i = n if end < 0 else end + len(tag.group())
        elif body[i] == ";":
            return body[:i], body[i + 1 :]
        else:
            i += 1
    return None


# ---------- runner ----------


def run_checks(conn: Conn, checks: list[Check], *, timeout: str = STATEMENT_TIMEOUT) -> list[dict]:
    """Runs the checks one by one in a single READ ONLY transaction, then rolls
    it back. A failing or slow check does not stop the others."""
    results: list[dict] = []
    with conn.transaction():
        conn.execute("SET TRANSACTION READ ONLY")
        conn.execute("SELECT set_config('statement_timeout', %s, true)", (timeout,))
        results.extend(_run_one(conn, check) for check in checks)
        raise psycopg.Rollback
    return results


def report(conn: Conn, checks: list[Check], database_url: str) -> dict:
    """The body of GET /admin/data-checks (docs/api.md, Tools)."""
    ran_at = datetime.now(UTC)
    started = time.perf_counter()
    results = run_checks(conn, checks)
    statuses = Counter(r["status"] for r in results)
    return {
        "ran_at": ran_at.isoformat(timespec="seconds"),
        "database": database_label(database_url),
        "duration_ms": _ms_since(started),
        "summary": {
            "total": len(results),
            "passed": statuses["pass"],
            "failed": statuses["fail"],
            "errors": statuses["error"],
        },
        "checks": results,
    }


def database_label(database_url: str) -> str:
    """Host alias and database name only: never the user or the password."""
    params = conninfo_to_dict(database_url)
    host = str(params.get("host") or "local")
    if "neon" in host:
        alias = "neon"
    elif host in ("localhost", "127.0.0.1", "::1") or host.startswith("/"):
        alias = "local"
    else:
        alias = host.split(".")[0]
    return f"{alias} / {params.get('dbname') or '?'}"


def _run_one(conn: Conn, check: Check) -> dict:
    result = {
        "id": check.id,
        "title": check.title,
        "requirement": check.requirement,
        "note": check.note,
        "status": "error",
        "row_count": None,
        "truncated": False,
        "columns": [],
        "rows": [],
        "duration_ms": 0,
        "error": check.error,
    }
    if check.sql is None:
        return result

    started = time.perf_counter()
    body = sql.SQL(check.sql)  # type: ignore[arg-type]  # Laila's own file, never user input
    try:
        # A savepoint per check: an error rolls back only this check.
        with conn.transaction(), conn.cursor(row_factory=tuple_row) as cur:
            cur.execute(
                sql.SQL("SELECT * FROM (\n{}\n) AS c LIMIT {}").format(
                    body, sql.Literal(ROW_CAP + 1)
                )
            )
            columns = [column.name for column in cur.description or ()]
            rows = cur.fetchall()
            row_count = len(rows)
            if row_count > ROW_CAP:
                cur.execute(sql.SQL("SELECT COUNT(*) FROM (\n{}\n) AS c").format(body))
                row_count = cur.fetchone()[0]  # type: ignore[index]
    except psycopg.Error as exc:
        # Laila's own SQL error, without connection details.
        message = exc.diag.message_primary or str(exc).splitlines()[0]
        result.update(duration_ms=_ms_since(started), error=message)
        return result

    result.update(
        status="pass" if row_count == 0 else "fail",
        row_count=row_count,
        truncated=row_count > ROW_CAP,
        duration_ms=_ms_since(started),
    )
    if not check.sensitive:
        result.update(
            columns=columns,
            rows=[[_json_value(v) for v in row] for row in rows[:ROW_CAP]],
        )
    return result


def _json_value(value: object) -> object:
    if value is None or isinstance(value, bool | int | str):
        return value
    if isinstance(value, float):
        return value if math.isfinite(value) else str(value)
    if isinstance(value, datetime | date | clock_time):
        return value.isoformat()
    return str(value)


def _ms_since(started: float) -> int:
    return round((time.perf_counter() - started) * 1000)
