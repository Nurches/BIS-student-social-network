"""Week 13 (schema v5): posters, QR check-in, feedback and attendance analytics.

Migration: docs/migrations/005_checkin_feedback_posters.sql.
Madina's test cases are named in the test names (TC-16 … TC-24); Akbota's
threats in the comments (forged / reused QR, check-in on another community's
event, fake feedback, disguised file, huge file, GPS in EXIF, upload to another
community's event, inappropriate poster).
"""

import io
from datetime import UTC, datetime, timedelta
from pathlib import Path

import psycopg
import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.db import SCHEMA_SQL
from app.services import posters, tickets

from .conftest import Data
from .test_schema_and_seed import _load, _structure

A = "/api/v1/admin"
ROOT = Path(__file__).parents[2]
MIGRATION_005 = ROOT / "docs" / "migrations" / "005_checkin_feedback_posters.sql"
SCHEMA_V4 = Path(__file__).with_name("fixtures") / "schema_v4.sql"
SECRET = "test-secret-that-is-at-least-32-characters"  # conftest settings


def moderator(data: Data, email: str = "union@kbtu.kz") -> int:
    student = data.student(email)
    data.conn.execute("UPDATE student SET is_moderator = TRUE WHERE student_id = %s", (student,))
    return student


def image_bytes(fmt: str = "JPEG", size: tuple[int, int] = (800, 450), **save) -> bytes:
    out = io.BytesIO()
    mode = "RGBA" if fmt == "PNG" and save.pop("alpha", False) else "RGB"
    Image.new(mode, size, (30, 80, 200)).save(out, fmt, **save)
    return out.getvalue()


def jpeg_with_gps() -> bytes:
    """A phone photo: EXIF with GPS coordinates and orientation 6 (rotated)."""
    image = Image.new("RGB", (400, 200), (200, 40, 40))
    exif = Image.Exif()
    exif[0x0112] = 6  # orientation: rotate 90° clockwise to display
    exif[0x010F] = "PhoneMaker"
    gps = exif.get_ifd(0x8825)
    gps[1] = "N"
    gps[2] = (43.0, 14.0, 6.0)  # Almaty, KBTU
    gps[3] = "E"
    gps[4] = (76.0, 56.0, 34.0)
    out = io.BytesIO()
    image.save(out, "JPEG", exif=exif)
    return out.getvalue()


def soon_event(data: Data, community: int, *, starts_in: timedelta, limit: int = 30) -> int:
    """An event whose door is already open (check-in opens 3 h before the start)."""
    now = datetime.now(UTC)
    starts_at = now + starts_in
    deadline = min(starts_at, now + timedelta(minutes=30)) - timedelta(minutes=1)
    return data.event(community, deadline=deadline, starts_at=starts_at, limit=limit)


def past_event(data: Data, community: int, *, ended_ago: timedelta = timedelta(hours=1)) -> int:
    """An event that started 2 h before its end and has ended."""
    now = datetime.now(UTC)
    ends_at = now - ended_ago
    event = data.event(
        community,
        deadline=ends_at - timedelta(hours=3),
        starts_at=ends_at - timedelta(hours=2),
    )
    data.conn.execute("UPDATE event SET ends_at = %s WHERE event_id = %s", (ends_at, event))
    return event


def registration_id(data: Data, student: int, event: int) -> int:
    return data.scalar(  # type: ignore[return-value]
        "SELECT registration_id FROM registration WHERE student_id = %s AND event_id = %s",
        student,
        event,
    )


def check_in_row(data: Data, student: int, event: int) -> None:
    data.conn.execute(
        "UPDATE registration SET checked_in_at = NOW() WHERE student_id = %s AND event_id = %s",
        (student, event),
    )


def setup_club(data: Data) -> tuple[int, int, dict]:
    owner = data.student("owner@kbtu.kz")
    community = data.community(owner)
    return owner, community, data.headers(owner)


# ---------- tickets (pure functions) ----------


def test_a_ticket_is_signed_and_its_code_is_readable() -> None:
    payload = tickets.qr_payload(SECRET, 42)
    assert payload.startswith("QATYS-T1.42.")
    assert tickets.registration_from_payload(SECRET, payload) == 42
    assert (
        tickets.registration_from_payload("another-secret-of-thirty-two-chars!!", payload) is None
    )
    # Forged: the id changed, the signature kept (moving a ticket to another place).
    assert tickets.registration_from_payload(SECRET, payload.replace(".42.", ".43.")) is None
    assert tickets.registration_from_payload(SECRET, "QATYS-T1.42.") is None
    assert tickets.registration_from_payload(SECRET, "hello") is None

    code = tickets.code(SECRET, 42)
    assert len(code) == 6 and set(code) <= set(tickets.CODE_ALPHABET)
    assert tickets.normalize_code(" " + code[:3].lower() + "-" + code[3:]) == code
    # Different registrations, different codes (on a sample of 2000).
    assert len({tickets.code(SECRET, i) for i in range(1, 2001)}) == 2000


# ---------- posters (FR-08) ----------


def test_tc21_poster_upload_is_shown_in_the_feed_and_on_the_event(
    client: TestClient, data: Data
) -> None:
    _, community, headers = setup_club(data)
    student = data.student()
    data.subscribe(student, community)
    event = data.event(community)

    upload = client.put(
        f"{A}/events/{event}/poster",
        content=image_bytes("JPEG", (3000, 1500)),
        headers={**headers, "Content-Type": "image/jpeg"},
    )

    assert upload.status_code == 200, upload.text
    body = upload.json()
    assert (body["mime"], body["width"], body["height"]) == ("image/jpeg", 1600, 800)
    url = body["poster_url"]
    assert url.startswith(f"/api/v1/events/{event}/poster?v=")

    feed = client.get("/api/v1/feed", headers=data.headers(student)).json()["items"]
    assert feed[0]["poster_url"] == url
    detail = client.get(f"/api/v1/events/{event}", headers=data.headers(student)).json()
    assert detail["poster_url"] == url
    announcements = client.get("/api/v1/events/announcements", headers=data.headers(student))
    assert announcements.json()["items"][0]["poster_url"] == url

    # The image itself needs no token (Image.network in the app) and is cached.
    image = client.get(url)
    assert image.status_code == 200
    assert image.headers["content-type"] == "image/jpeg"
    assert "max-age" in image.headers["cache-control"]
    assert image.headers["x-content-type-options"] == "nosniff"
    assert Image.open(io.BytesIO(image.content)).size == (1600, 800)


def test_tc22_replacing_a_poster_changes_its_url(client: TestClient, data: Data) -> None:
    _, community, headers = setup_club(data)
    event = data.event(community)
    put = lambda content, kind: client.put(  # noqa: E731
        f"{A}/events/{event}/poster", content=content, headers={**headers, "Content-Type": kind}
    )

    first = put(image_bytes("JPEG"), "image/jpeg").json()
    second = put(image_bytes("PNG", alpha=True), "image/png").json()

    assert second["mime"] == "image/png"
    assert second["poster_url"] != first["poster_url"]
    assert data.scalar("SELECT COUNT(*) FROM event_poster") == 1
    image = client.get(second["poster_url"])
    assert image.headers["content-type"] == "image/png"

    deleted = client.delete(f"{A}/events/{event}/poster", headers=headers)
    assert deleted.status_code == 204
    assert client.get(second["poster_url"]).json() == {"error": "poster_not_found"}
    detail = client.get(f"/api/v1/events/{event}", headers=headers).json()
    assert detail["poster_url"] is None
    again = client.delete(f"{A}/events/{event}/poster", headers=headers)
    assert again.json() == {"error": "poster_not_found"}


def test_tc23_a_too_big_or_disguised_file_is_refused(client: TestClient, data: Data) -> None:
    _, community, headers = setup_club(data)
    event = data.event(community)
    url = f"{A}/events/{event}/poster"

    def put(content: bytes, kind: str = "image/jpeg"):
        return client.put(url, content=content, headers={**headers, "Content-Type": kind})

    # Threat "huge file": refused before the body is read (2 MB + 1 byte).
    big = put(b"\xff\xd8\xff" + b"0" * (2 * 1024 * 1024 - 2))
    assert (big.status_code, big.json()) == (413, {"error": "poster_too_large"})

    # Threat "disguised file": the name and Content-Type say JPEG, the bytes do not.
    for fake in (
        b"MZ\x90\x00 this is a windows program",
        b'<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>',
        b"%PDF-1.7 ...",
        image_bytes("GIF"),
        b"",
    ):
        refused = put(fake)
        assert (refused.status_code, refused.json()) == (415, {"error": "unsupported_poster_type"})

    # The right magic bytes, broken data.
    broken = put(b"\x89PNG\r\n\x1a\n" + b"garbage" * 100, "image/png")
    assert (broken.status_code, broken.json()) == (422, {"error": "poster_unreadable"})
    assert data.scalar("SELECT COUNT(*) FROM event_poster") == 0


def test_a_decompression_bomb_is_refused() -> None:
    # 10000 x 5000 = 50 megapixels in a tiny PNG.
    bomb = image_bytes("PNG", (10_000, 5_000), optimize=True)
    assert len(bomb) < posters.MAX_POSTER_BYTES
    with pytest.raises(Exception) as caught:
        posters.process(bomb)
    assert getattr(caught.value, "code", None) == "poster_unreadable"


def test_gps_and_other_exif_are_removed_and_the_photo_is_upright() -> None:
    original = jpeg_with_gps()
    assert Image.open(io.BytesIO(original)).getexif().get_ifd(0x8825)  # GPS is there

    poster = posters.process(original)

    clean = Image.open(io.BytesIO(poster.data))
    assert dict(clean.getexif()) == {}
    assert b"PhoneMaker" not in poster.data and b"Exif" not in poster.data
    assert (poster.width, poster.height) == (200, 400)  # turned upright
    webp = posters.process(image_bytes("WEBP"))
    assert webp.mime == "image/webp"


def test_tc24_a_poster_for_another_communitys_event_is_forbidden(
    client: TestClient, data: Data
) -> None:
    _, community, _ = setup_club(data)
    event = data.event(community)
    other_owner = data.student("other@kbtu.kz")
    data.community(other_owner)  # owns a community: has /admin, but not this event
    stranger = data.headers(other_owner)

    upload = client.put(
        f"{A}/events/{event}/poster",
        content=image_bytes(),
        headers={**stranger, "Content-Type": "image/jpeg"},
    )
    assert (upload.status_code, upload.json()) == (403, {"error": "not_your_community"})

    plain = data.headers(data.student())
    upload = client.put(
        f"{A}/events/{event}/poster",
        content=image_bytes(),
        headers={**plain, "Content-Type": "image/jpeg"},
    )
    assert (upload.status_code, upload.json()) == (403, {"error": "not_an_admin"})
    assert data.scalar("SELECT COUNT(*) FROM event_poster") == 0


def test_a_moderator_removes_any_poster_and_no_poster_on_a_cancelled_event(
    client: TestClient, data: Data
) -> None:
    _, community, headers = setup_club(data)
    event = data.event(community)
    client.put(
        f"{A}/events/{event}/poster",
        content=image_bytes(),
        headers={**headers, "Content-Type": "image/jpeg"},
    )
    union = data.headers(moderator(data))

    # Threat "inappropriate poster": the Student Union removes it.
    assert client.delete(f"{A}/events/{event}/poster", headers=union).status_code == 204

    client.post(f"{A}/events/{event}/cancel", headers=headers)
    late = client.put(
        f"{A}/events/{event}/poster",
        content=image_bytes(),
        headers={**headers, "Content-Type": "image/jpeg"},
    )
    assert late.json() == {"error": "event_cancelled"}


def test_no_poster_once_the_community_is_unconfirmed_and_none_for_a_draft(
    client: TestClient, data: Data
) -> None:
    owner, community, headers = setup_club(data)
    other = data.community(owner, name="Second Club")  # keeps /admin access
    event = data.event(community)
    draft = data.event(other, status="draft")
    data.conn.execute(
        "UPDATE community SET status = 'pending' WHERE community_id = %s", (community,)
    )

    refused = client.put(
        f"{A}/events/{event}/poster",
        content=image_bytes(),
        headers={**headers, "Content-Type": "image/jpeg"},
    )
    assert refused.json() == {"error": "community_not_confirmed"}

    data.conn.execute(
        "INSERT INTO event_poster (event_id, mime, size_bytes, width, height, data, uploaded_by) "
        "VALUES (%s, 'image/jpeg', 3, 1, 1, '\\x010203', %s)",
        (draft, owner),
    )
    assert client.get(f"/api/v1/events/{draft}/poster").json() == {"error": "poster_not_found"}


# ---------- QR check-in (FR-06) ----------


def test_tc16_a_registered_student_is_checked_in_with_the_qr(
    client: TestClient, data: Data
) -> None:
    _, community, headers = setup_club(data)
    student = data.student()
    event = soon_event(data, community, starts_in=timedelta(hours=1))
    me = data.headers(student)
    assert client.post(f"/api/v1/events/{event}/registrations", headers=me).status_code == 201

    ticket = client.get(f"/api/v1/events/{event}/ticket", headers=me)
    assert ticket.status_code == 200
    t = ticket.json()
    assert t["qr"] == tickets.qr_payload(SECRET, t["registration_id"])
    assert len(t["code"]) == 6 and t["checked_in_at"] is None

    done = client.post(f"{A}/events/{event}/check-in", json={"ticket": t["qr"]}, headers=headers)

    assert done.status_code == 200, done.text
    body = done.json()
    assert body["student_id"] == student
    assert (body["attended_count"], body["confirmed_count"]) == (1, 1)
    detail = client.get(f"/api/v1/events/{event}", headers=me).json()
    assert detail["checked_in_at"] is not None
    assert client.get(f"/api/v1/events/{event}/ticket", headers=me).json()["checked_in_at"]
    listed = client.get(f"{A}/events/{event}/registrations", headers=headers).json()["items"]
    assert listed[0]["checked_in_at"] is not None
    # Checked in: the place is used, it cannot be cancelled any more.
    leave = client.delete(f"/api/v1/events/{event}/registrations", headers=me)
    assert leave.json() == {"error": "already_checked_in"}


def test_tc16_the_six_character_code_works_too(client: TestClient, data: Data) -> None:
    _, community, headers = setup_club(data)
    student = data.student()
    event = soon_event(data, community, starts_in=timedelta(hours=2))
    data.registration(student, event)
    code = tickets.code(SECRET, registration_id(data, student, event))

    typed = code[:3].lower() + " " + code[3:]
    done = client.post(f"{A}/events/{event}/check-in", json={"ticket": typed}, headers=headers)

    assert done.status_code == 200, done.text
    wrong = client.post(f"{A}/events/{event}/check-in", json={"ticket": "ZZZZZZ"}, headers=headers)
    assert wrong.json() == {"error": "invalid_ticket"}


def test_tc17_a_ticket_works_once(client: TestClient, data: Data) -> None:
    _, community, headers = setup_club(data)
    student = data.student()
    event = soon_event(data, community, starts_in=timedelta(minutes=30))
    data.registration(student, event)
    qr = tickets.qr_payload(SECRET, registration_id(data, student, event))
    first = client.post(f"{A}/events/{event}/check-in", json={"ticket": qr}, headers=headers)
    assert first.status_code == 200

    # Threat "reused QR": a screenshot shown a second time.
    second = client.post(f"{A}/events/{event}/check-in", json={"ticket": qr}, headers=headers)

    assert second.status_code == 409
    body = second.json()
    assert body["error"] == "already_checked_in"
    assert body["student_name"].startswith("Student")
    first_time = datetime.fromisoformat(first.json()["checked_in_at"].replace("Z", "+00:00"))
    assert datetime.fromisoformat(body["checked_in_at"]) == first_time


def test_a_forged_or_foreign_ticket_is_refused(client: TestClient, data: Data) -> None:
    _, community, headers = setup_club(data)
    student = data.student()
    event = soon_event(data, community, starts_in=timedelta(hours=1))
    other_event = soon_event(data, community, starts_in=timedelta(hours=1))
    data.registration(student, event)
    data.registration(student, other_event)
    mine = registration_id(data, student, event)

    # Threat "forged QR": right format, wrong signature.
    forged = client.post(
        f"{A}/events/{event}/check-in",
        json={"ticket": f"QATYS-T1.{mine}.AAAAAAAAAAAAAAAA"},
        headers=headers,
    )
    assert (forged.status_code, forged.json()) == (422, {"error": "invalid_ticket"})

    # A genuine ticket for another event.
    foreign = client.post(
        f"{A}/events/{other_event}/check-in",
        json={"ticket": tickets.qr_payload(SECRET, mine)},
        headers=headers,
    )
    assert (foreign.status_code, foreign.json()) == (409, {"error": "ticket_other_event"})
    assert data.scalar("SELECT COUNT(*) FROM registration WHERE checked_in_at IS NOT NULL") == 0


def test_check_in_only_by_the_owner_or_a_moderator(client: TestClient, data: Data) -> None:
    _, community, _ = setup_club(data)
    student = data.student()
    event = soon_event(data, community, starts_in=timedelta(hours=1))
    data.registration(student, event)
    qr = tickets.qr_payload(SECRET, registration_id(data, student, event))

    # Threat "check-in on another community's event".
    other = data.student("other@kbtu.kz")
    data.community(other)
    refused = client.post(
        f"{A}/events/{event}/check-in", json={"ticket": qr}, headers=data.headers(other)
    )
    assert refused.json() == {"error": "not_your_community"}
    # The student cannot check themselves in.
    own = client.post(
        f"{A}/events/{event}/check-in", json={"ticket": qr}, headers=data.headers(student)
    )
    assert own.json() == {"error": "not_an_admin"}

    union = data.headers(moderator(data))
    assert (
        client.post(f"{A}/events/{event}/check-in", json={"ticket": qr}, headers=union).status_code
        == 200
    )


def test_waiting_list_has_no_ticket_and_the_door_has_hours(client: TestClient, data: Data) -> None:
    _, community, headers = setup_club(data)
    first, waiting = data.student(), data.student()
    event = soon_event(data, community, starts_in=timedelta(hours=1), limit=1)
    data.registration(first, event)
    data.registration(waiting, event, status="waiting_list")

    no_ticket = client.get(f"/api/v1/events/{event}/ticket", headers=data.headers(waiting))
    assert (no_ticket.status_code, no_ticket.json()) == (409, {"error": "ticket_waiting_list"})
    nobody = client.get(f"/api/v1/events/{event}/ticket", headers=data.headers(data.student()))
    assert nobody.json() == {"error": "not_registered"}
    qr = tickets.qr_payload(SECRET, registration_id(data, waiting, event))
    refused = client.post(f"{A}/events/{event}/check-in", json={"ticket": qr}, headers=headers)
    assert refused.json() == {"error": "ticket_not_confirmed"}

    later = data.event(community)  # starts in 6 days: the door is closed
    data.registration(first, later)
    early_qr = tickets.qr_payload(SECRET, registration_id(data, first, later))
    early = client.post(f"{A}/events/{later}/check-in", json={"ticket": early_qr}, headers=headers)
    assert early.status_code == 409
    assert early.json()["error"] == "check_in_not_open" and early.json()["opens_at"]

    old = past_event(data, community, ended_ago=timedelta(hours=3))
    data.registration(first, old)
    late_qr = tickets.qr_payload(SECRET, registration_id(data, first, old))
    late = client.post(f"{A}/events/{old}/check-in", json={"ticket": late_qr}, headers=headers)
    assert (late.status_code, late.json()) == (410, {"error": "check_in_closed"})


def test_guessing_codes_is_rate_limited(client: TestClient, data: Data) -> None:
    _, community, headers = setup_club(data)
    event = soon_event(data, community, starts_in=timedelta(hours=1))
    answers = [
        client.post(f"{A}/events/{event}/check-in", json={"ticket": "AAAAAA"}, headers=headers)
        for _ in range(61)
    ]
    assert {a.status_code for a in answers[:60]} == {422}
    assert answers[60].status_code == 429
    assert int(answers[60].headers["Retry-After"]) > 0


# ---------- feedback (FR-07) ----------


def test_feedback_after_check_in_and_the_end(client: TestClient, data: Data) -> None:
    _, community, headers = setup_club(data)
    student = data.student()
    event = past_event(data, community)
    data.registration(student, event)
    check_in_row(data, student, event)
    me = data.headers(student)
    before = client.get(f"/api/v1/events/{event}", headers=me).json()
    assert (before["feedback_open"], before["my_rating"]) == (True, None)

    sent = client.post(
        f"/api/v1/events/{event}/feedback",
        json={"rating": 4, "comment": "  Good talks  "},
        headers=me,
    )

    assert sent.status_code == 201, sent.text
    assert (sent.json()["rating"], sent.json()["comment"]) == (4, "Good talks")
    after = client.get(f"/api/v1/events/{event}", headers=me).json()
    assert (after["feedback_open"], after["my_rating"]) == (False, 4)
    mine = client.get("/api/v1/me/registrations", headers=me).json()["items"]
    assert mine[0]["my_rating"] == 4

    # One rating per student: the second one is refused, the first stays.
    again = client.post(f"/api/v1/events/{event}/feedback", json={"rating": 1}, headers=me)
    assert (again.status_code, again.json()) == (409, {"error": "feedback_already_sent"})
    listed = client.get(f"{A}/events/{event}/feedback", headers=headers).json()
    assert (listed["count"], listed["average_rating"], listed["distribution"]) == (
        1,
        4.0,
        [0, 0, 0, 1, 0],
    )
    assert listed["items"] == [
        {"rating": 4, "comment": "Good talks", "created_at": listed["items"][0]["created_at"]}
    ]  # anonymous: no name, no email


def test_tc18_no_feedback_before_the_end(client: TestClient, data: Data) -> None:
    _, community, headers = setup_club(data)
    student = data.student()
    event = soon_event(data, community, starts_in=timedelta(minutes=20))
    data.registration(student, event)
    qr = tickets.qr_payload(SECRET, registration_id(data, student, event))
    client.post(f"{A}/events/{event}/check-in", json={"ticket": qr}, headers=headers)
    me = data.headers(student)

    early = client.post(f"/api/v1/events/{event}/feedback", json={"rating": 5}, headers=me)

    assert (early.status_code, early.json()) == (409, {"error": "event_not_finished"})
    assert client.get(f"/api/v1/events/{event}", headers=me).json()["feedback_open"] is False


def test_tc19_no_feedback_without_attendance(client: TestClient, data: Data) -> None:
    _, community, _ = setup_club(data)
    registered, stranger = data.student(), data.student()
    event = past_event(data, community)
    data.registration(registered, event)  # registered, never came

    # Threat "fake feedback": only a student checked in at the door may rate.
    for student in (registered, stranger):
        refused = client.post(
            f"/api/v1/events/{event}/feedback", json={"rating": 1}, headers=data.headers(student)
        )
        assert (refused.status_code, refused.json()) == (403, {"error": "not_checked_in"})
    assert data.scalar("SELECT COUNT(*) FROM event_feedback") == 0


def test_a_rating_must_be_1_to_5_and_a_comment_at_most_500(client: TestClient, data: Data) -> None:
    _, community, _ = setup_club(data)
    student = data.student()
    event = past_event(data, community)
    data.registration(student, event)
    check_in_row(data, student, event)
    me = data.headers(student)
    for body in ({"rating": 0}, {"rating": 6}, {"rating": 5, "comment": "x" * 501}, {}):
        bad = client.post(f"/api/v1/events/{event}/feedback", json=body, headers=me)
        assert (bad.status_code, bad.json()["error"]) == (422, "validation_failed")
    with pytest.raises(psycopg.errors.CheckViolation):
        data.conn.execute(
            "INSERT INTO event_feedback (event_id, student_id, rating) VALUES (%s, %s, 9)",
            (event, student),
        )


def test_finish_now_opens_the_feedback(client: TestClient, data: Data) -> None:
    _, community, headers = setup_club(data)
    student = data.student()
    now = datetime.now(UTC)
    started = data.event(
        community, deadline=now - timedelta(minutes=30), starts_at=now - timedelta(minutes=10)
    )
    data.registration(student, started)
    check_in_row(data, student, started)
    me = data.headers(student)
    live = client.get(f"{A}/events", headers=headers).json()["items"][0]
    assert live["state"] == "live"

    finished = client.post(f"{A}/events/{started}/finish", headers=headers)

    assert finished.status_code == 200, finished.text
    assert finished.json()["state"] == "finished"
    assert client.get(f"/api/v1/events/{started}", headers=me).json()["feedback_open"] is True
    twice = client.post(f"{A}/events/{started}/finish", headers=headers)
    assert twice.json() == {"error": "event_already_finished"}
    future = data.event(community)
    too_early = client.post(f"{A}/events/{future}/finish", headers=headers)
    assert too_early.json() == {"error": "event_not_started"}


def test_publish_and_edit_with_an_end(client: TestClient, data: Data) -> None:
    _, community, headers = setup_club(data)
    now = datetime.now(UTC)
    starts = now + timedelta(days=2)
    body = {
        "title": "Meetup",
        "starts_at": starts.isoformat(),
        "registration_deadline": (now + timedelta(days=1)).isoformat(),
        "participant_limit": 10,
    }
    bad = client.post(
        f"/api/v1/communities/{community}/events",
        json={**body, "ends_at": starts.isoformat()},
        headers=headers,
    )
    assert bad.json() == {"error": "end_before_start"}

    created = client.post(
        f"/api/v1/communities/{community}/events",
        json={**body, "ends_at": (starts + timedelta(hours=4)).isoformat()},
        headers=headers,
    )
    event = created.json()["event_id"]
    detail = client.get(f"/api/v1/events/{event}", headers=headers).json()
    assert datetime.fromisoformat(detail["ends_at"]) == starts + timedelta(hours=4)

    # Moving the start keeps the length of the event.
    moved = client.patch(
        f"{A}/events/{event}",
        json={"starts_at": (starts + timedelta(days=1)).isoformat()},
        headers=headers,
    ).json()["event"]
    assert datetime.fromisoformat(moved["ends_at"]) == starts + timedelta(days=1, hours=4)
    reset = client.patch(f"{A}/events/{event}", json={"ends_at": None}, headers=headers)
    # After the end the times are frozen: ratings and check-ins belong to them.
    old = past_event(data, community)
    frozen = client.patch(
        f"{A}/events/{old}",
        json={"starts_at": (now + timedelta(days=3)).isoformat()},
        headers=headers,
    )
    assert frozen.json() == {"error": "event_already_finished"}
    renamed = client.patch(f"{A}/events/{old}", json={"title": "Renamed"}, headers=headers)
    assert renamed.status_code == 200
    assert datetime.fromisoformat(reset.json()["event"]["ends_at"]) == starts + timedelta(
        days=1, hours=2
    )


# ---------- analytics ----------


def test_tc20_analytics_counts_registered_attended_and_ratings(
    client: TestClient, data: Data
) -> None:
    owner, community, headers = setup_club(data)
    second = data.community(owner, name="Second Club")
    students = [data.student() for _ in range(5)]
    meetup = past_event(data, community)
    for s in students[:4]:
        data.registration(s, meetup)
    for s in students[:3]:
        check_in_row(data, s, meetup)
    data.registration(students[4], meetup, status="cancelled")  # not counted
    for s, rating in zip(students[:2], (5, 3), strict=True):
        data.conn.execute(
            "INSERT INTO event_feedback (event_id, student_id, rating) VALUES (%s, %s, %s)",
            (meetup, s, rating),
        )
    workshop = past_event(data, second, ended_ago=timedelta(days=2))
    data.registration(students[0], workshop)
    check_in_row(data, students[0], workshop)
    data.conn.execute(
        "INSERT INTO event_feedback (event_id, student_id, rating) VALUES (%s, %s, 5)",
        (workshop, students[0]),
    )
    data.event(community)  # in the future: not in the analytics

    stats = client.get(f"{A}/analytics", headers=headers).json()

    by_event = {e["event_id"]: e for e in stats["events"]}
    assert set(by_event) == {meetup, workshop}
    m = by_event[meetup]
    assert (m["registered"], m["attended"], m["no_show"], m["no_show_rate"]) == (4, 3, 1, 25.0)
    assert (m["feedback_count"], m["average_rating"]) == (2, 4.0)
    totals = stats["totals"]
    assert (totals["registered"], totals["attended"], totals["no_show"]) == (5, 4, 1)
    assert totals["no_show_rate"] == 20.0 and totals["attendance_rate"] == 80.0
    assert totals["average_rating"] == round(13 / 3, 2)
    assert [c["community_id"] for c in stats["communities"]] == [community, second]
    assert stats["communities"][1]["average_rating"] == 5.0

    # Another owner sees none of it; a moderator sees all.
    other = data.student("other@kbtu.kz")
    data.community(other)
    assert client.get(f"{A}/analytics", headers=data.headers(other)).json()["events"] == []
    union = data.headers(moderator(data))
    assert len(client.get(f"{A}/analytics", headers=union).json()["events"]) == 2
    listed = {e["event_id"]: e for e in client.get(f"{A}/events", headers=headers).json()["items"]}
    assert (listed[meetup]["attended_count"], listed[meetup]["average_rating"]) == (3, 4.0)


# ---------- seed and migration ----------


def test_the_seed_has_analytics_and_posters(client: TestClient, db: psycopg.Connection) -> None:
    import seed

    seed.seed(db, "qatys2026", rounds=4)
    login = client.post(
        "/api/v1/auth/login", json={"email": "union@kbtu.kz", "password": "qatys2026"}
    )
    headers = {"Authorization": f"Bearer {login.json()['token']}"}
    stats = client.get(f"{A}/analytics", headers=headers).json()
    assert {e["title"] for e in stats["events"]} == {"Python meetup", "LinkedIn profile workshop"}
    assert stats["totals"]["no_show"] == 1 and stats["totals"]["feedback_count"] == 5
    student = client.post(
        "/api/v1/auth/login", json={"email": "nurassyl@kbtu.kz", "password": "qatys2026"}
    )
    feed = client.get(
        "/api/v1/feed", headers={"Authorization": f"Bearer {student.json()['token']}"}
    ).json()["items"]
    with_poster = [e for e in feed if e["poster_url"]]
    assert {e["title"] for e in with_poster} == {"IT Job Fair", "Autumn Hackathon 2026"}
    assert client.get(with_poster[0]["poster_url"]).status_code == 200


def test_migration_005_on_a_v4_database_equals_a_fresh_schema(db: psycopg.Connection) -> None:
    _load(db, "migrated", SCHEMA_V4.read_text(encoding="utf-8"))
    _load(db, "fresh", SCHEMA_SQL.read_text(encoding="utf-8"))
    try:
        db.execute("SET search_path TO migrated")
        db.execute(MIGRATION_005.read_text(encoding="utf-8"))
        db.execute("SET search_path TO public")
        assert _structure(db, "migrated") == _structure(db, "fresh")
    finally:
        db.execute("SET search_path TO public")
        db.execute("DROP SCHEMA migrated CASCADE")
        db.execute("DROP SCHEMA fresh CASCADE")
