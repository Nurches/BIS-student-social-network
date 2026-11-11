"""Recreates the schema and fills it with demo data.

    python seed.py --yes            # local database (localhost, 127.0.0.1, docker "db")
    python seed.py --yes --live     # any other host: also asks to type the database name

DELETES EVERY TABLE first, with every registration, notification and phone push
token in it. Dates are relative to now, so the demo never goes stale: re-run it
on the morning of the defence (docs/demo-runbook.md says when and how).

Demo data: 10 students, 5 communities, 8 events, 1 confirmed admin
(union@kbtu.kz, owner of IT Club, Career Center, Sports Club, Volunteer Hub).
The team's demo accounts follow IT Club and Career Center only, so the other
communities are there to be discovered in the app's Explore tab. Every account uses the
password from SEED_PASSWORD (default: qatys2026, the same as the app's mock mode).
"""

import argparse
import os
import sys
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo

import psycopg
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict
from psycopg.rows import dict_row

from app.config import get_settings
from app.db import apply_schema
from app.security import hash_password

ALMATY = ZoneInfo("Asia/Almaty")

STUDENTS = [
    # email, full name, faculty, enrolled year
    ("nurassyl@kbtu.kz", "Turarbek Nurassyl", "SITE", 2024),
    ("akbota@kbtu.kz", "Nurkasymova Akbota", "SITE", 2024),
    ("laila@kbtu.kz", "Taubay Laila", "SITE", 2024),
    ("madina@kbtu.kz", "Shpanova Madina", "SITE", 2024),
    ("gulnazym@kbtu.kz", "Ualikhan Gulnazym", "SITE", 2024),
    ("aru@kbtu.kz", "Sadykova Aru", "SITE", 2026),
    ("dias@kbtu.kz", "Omarov Dias", "BS", 2026),
    ("alikhan@kbtu.kz", "Bekov Alikhan", "SITE", 2026),
    ("zhanel@kbtu.kz", "Karimova Zhanel", "ISE", 2026),
    ("union@kbtu.kz", "Student Union Staff", "Student Union", 2020),
]
ADMIN_EMAIL = "union@kbtu.kz"

COMMUNITIES = [
    # name, description, owner email, confirmed by the Student Union
    ("IT Club", "Programming contests, hackathons and workshops", ADMIN_EMAIL, True),
    ("Career Center", "Internships, job fairs, CV clinics", ADMIN_EMAIL, True),
    ("Debate Society", "Weekly debates and tournaments", "akbota@kbtu.kz", False),
    ("Sports Club", "Futsal, volleyball and the KBTU running club", ADMIN_EMAIL, True),
    ("Volunteer Hub", "Charity drives, campus clean-ups and mentoring", ADMIN_EMAIL, True),
]
# Extra followers of the communities the demo accounts do not follow.
EXTRA_SUBSCRIPTIONS = [
    ("akbota@kbtu.kz", "Debate Society"),
    ("dias@kbtu.kz", "Debate Society"),
    ("aru@kbtu.kz", "Sports Club"),
    ("alikhan@kbtu.kz", "Sports Club"),
    ("zhanel@kbtu.kz", "Volunteer Hub"),
]


def at(days: int, hour: int, minute: int = 0) -> datetime:
    """A round local time `days` from today in Almaty."""
    day = datetime.now(ALMATY).date() + timedelta(days=days)
    return datetime(day.year, day.month, day.day, hour, minute, tzinfo=ALMATY)


def events() -> list[dict]:
    now = datetime.now(UTC)
    return [
        dict(
            community="IT Club",
            title="Autumn Hackathon 2026",
            description="24-hour team hackathon. Teams of 3 to 4, mentors on site.",
            location="Block C, room 301",
            starts_at=at(14, 10),
            deadline=at(10, 23, 59),
            limit=30,
            confirmed=3,
            waiting=0,
            status="published",
        ),
        dict(
            community="Career Center",
            title="IT Job Fair",
            description="Meeting with 12 companies. Bring a printed CV.",
            location="Main hall",
            starts_at=at(7, 11),
            deadline=at(5, 18),
            limit=200,
            confirmed=1,
            waiting=0,
            status="published",
        ),
        # One place left: the race on the last place (brief §9).
        dict(
            community="IT Club",
            title="Flutter workshop",
            description="Build and ship your first mobile app in two hours.",
            location="Block C, room 204",
            starts_at=at(2, 15),
            deadline=now + timedelta(hours=20),
            limit=5,
            confirmed=4,
            waiting=0,
            status="published",
        ),
        # Full: registration lands on the waiting list (FR-03).
        dict(
            community="Career Center",
            title="CV clinic",
            description="One-to-one CV review with recruiters.",
            location="Block B, room 210",
            starts_at=at(4, 14),
            deadline=at(2, 18),
            limit=3,
            confirmed=3,
            waiting=1,
            status="published",
        ),
        # Deadline passed: hidden from the feed, opened from an old push (FR-02).
        dict(
            community="IT Club",
            title="Git workshop for first-years",
            description="Basics of version control.",
            location="Block A, room 105",
            starts_at=at(3, 12),
            deadline=now - timedelta(days=1),
            limit=25,
            confirmed=2,
            waiting=0,
            status="published",
        ),
        dict(
            community="Sports Club",
            title="Futsal cup",
            description="5-a-side tournament between faculties. Teams of 5 to 7.",
            location="Sports hall",
            starts_at=at(8, 17),
            deadline=at(6, 18),
            limit=40,
            confirmed=4,
            waiting=0,
            status="published",
        ),
        dict(
            community="Volunteer Hub",
            title="Campus clean-up day",
            description="Two hours outdoors, gloves and tea provided.",
            location="Main entrance",
            starts_at=at(5, 10),
            deadline=at(3, 20),
            limit=25,
            confirmed=2,
            waiting=0,
            status="published",
        ),
        dict(
            community="Debate Society",
            title="Debate tournament",
            description="Draft, not published yet.",
            location="Block B",
            starts_at=at(21, 16),
            deadline=at(18, 18),
            limit=16,
            confirmed=0,
            waiting=0,
            status="draft",
        ),
    ]


def seed(conn: psycopg.Connection, password: str, rounds: int) -> None:
    apply_schema(conn)
    password_hash = hash_password(password, rounds)

    with conn.transaction():
        ids: dict[str, int] = {}
        for email, name, faculty, year in STUDENTS:
            row = conn.execute(
                "INSERT INTO student (email, full_name, password_hash, faculty, enrolled_year, "
                "is_moderator) VALUES (%s, %s, %s, %s, %s, %s) RETURNING student_id",
                (email, name, password_hash, faculty, year, email == ADMIN_EMAIL),
            ).fetchone()
            ids[email] = row["student_id"]

        communities: dict[str, int] = {}
        for name, description, owner, confirmed in COMMUNITIES:
            row = conn.execute(
                "INSERT INTO community (name, description, owner_id, is_confirmed) "
                "VALUES (%s, %s, %s, %s) RETURNING community_id",
                (name, description, ids[owner], confirmed),
            ).fetchone()
            communities[name] = row["community_id"]

        students = [ids[s[0]] for s in STUDENTS if s[0] != ADMIN_EMAIL]
        for student_id in students:
            for name in ("IT Club", "Career Center"):
                conn.execute(
                    "INSERT INTO subscription (student_id, community_id) VALUES (%s, %s)",
                    (student_id, communities[name]),
                )
        for email, name in EXTRA_SUBSCRIPTIONS:
            conn.execute(
                "INSERT INTO subscription (student_id, community_id) VALUES (%s, %s)",
                (ids[email], communities[name]),
            )

        # Registrations come from the students at the end of the list, so the
        # team's own accounts (the demo phones) start unregistered everywhere.
        others = list(reversed(students))
        for event in events():
            row = conn.execute(
                "INSERT INTO event (community_id, title, description, location, starts_at, "
                "registration_deadline, participant_limit, status, created_at) "
                "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, NOW() - INTERVAL '2 days') "
                "RETURNING event_id",
                (
                    communities[event["community"]],
                    event["title"],
                    event["description"],
                    event["location"],
                    event["starts_at"],
                    event["deadline"],
                    event["limit"],
                    event["status"],
                ),
            ).fetchone()
            event_id = row["event_id"]

            queue = [("confirmed", s) for s in others[: event["confirmed"]]] + [
                ("waiting_list", s)
                for s in others[event["confirmed"] : event["confirmed"] + event["waiting"]]
            ]
            for i, (status, student_id) in enumerate(queue):
                conn.execute(
                    "INSERT INTO registration (student_id, event_id, status, created_at, "
                    "updated_at) VALUES (%s, %s, %s, NOW() - %s * INTERVAL '1 hour', "
                    "NOW() - %s * INTERVAL '1 hour')",
                    (student_id, event_id, status, 30 - i, 30 - i),
                )

            if event["status"] == "published":
                conn.execute(
                    "INSERT INTO notification (student_id, event_id, created_at, sent_at, is_read) "
                    "SELECT s.student_id, %s, NOW() - INTERVAL '2 days', "
                    "NOW() - INTERVAL '2 days', TRUE "
                    "FROM subscription s WHERE s.community_id = %s",
                    (event_id, communities[event["community"]]),
                )


# Hosts where --yes alone is enough: this laptop and the docker-compose service.
LOCAL_HOSTS = frozenset({"localhost", "127.0.0.1", "::1", "db", ""})
READONLY_ROLE = "qatys_readonly"  # docs/team/setup/readonly_role.sql


def describe(database_url: str) -> tuple[str, str]:
    """Host and database name of a connection string, never the user or password."""
    info = conninfo_to_dict(database_url)
    return str(info.get("host") or ""), str(info.get("dbname") or "")


def confirm_target(
    database_url: str, *, yes: bool, live: bool, ask: Callable[[str], str] = input
) -> None:
    """Exits (nothing changed) unless the target was confirmed for its kind of host."""
    host, dbname = describe(database_url)
    print(f"Target: database '{dbname}' on host '{host or 'local socket'}'")
    if not yes:
        sys.exit("Refusing to run without --yes: this deletes every table first.")
    if host in LOCAL_HOSTS or host.startswith("/"):
        return
    if not live:
        sys.exit(
            f"Refusing: '{host}' is not a local database. To reset it on purpose, add --live "
            "(it deletes every registration and every phone's push token)."
        )
    typed = ask(f"Type the database name '{dbname}' to delete every table in it: ").strip()
    if typed != dbname:
        sys.exit("The name does not match. Nothing was changed.")


def readonly_role(settings_readonly_url: str) -> str:
    """The role of DATABASE_URL_READONLY, or the default qatys_readonly."""
    if settings_readonly_url:
        user = conninfo_to_dict(settings_readonly_url).get("user")
        if user:
            return str(user)
    return READONLY_ROLE


def grant_readonly(conn: psycopg.Connection, role: str) -> bool:
    """Re-grants SELECT on the recreated tables, if the read-only role exists.

    Dropping a table drops its grants too, so after every reseed the data checks
    (DATABASE_URL_READONLY) would otherwise fail with "permission denied".
    """
    exists = conn.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (role,)).fetchone()
    if exists is None:
        return False
    conn.execute(sql.SQL("GRANT USAGE ON SCHEMA public TO {}").format(sql.Identifier(role)))
    conn.execute(
        sql.SQL("GRANT SELECT ON ALL TABLES IN SCHEMA public TO {}").format(sql.Identifier(role))
    )
    return True


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--yes", action="store_true", help="confirm: every table is deleted")
    parser.add_argument(
        "--live", action="store_true", help="allow a non-local host (asks for the database name)"
    )
    args = parser.parse_args(argv)

    settings = get_settings()
    confirm_target(settings.database_url, yes=args.yes, live=args.live)

    password = os.environ.get("SEED_PASSWORD", "qatys2026")
    with psycopg.connect(settings.database_url, autocommit=True, row_factory=dict_row) as conn:
        seed(conn, password, settings.bcrypt_rounds)
        role = readonly_role(settings.database_url_readonly)
        granted = grant_readonly(conn, role)
    print(
        f"Seeded {len(STUDENTS)} students, {len(COMMUNITIES)} communities, "
        f"{len(events())} events. Admin: {ADMIN_EMAIL}"
    )
    print(f"Read-only role {role}: " + ("SELECT granted again" if granted else "not present"))
    print("Push tokens were deleted: log out and log in again on every phone.")


if __name__ == "__main__":
    main()
