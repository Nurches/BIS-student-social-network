"""Race on the last place (brief §9, promised for Week 10).

Real concurrent transactions on a real PostgreSQL: without `SELECT ... FOR
UPDATE` in services.events.register, both students read "1 place left" and
both are confirmed. With the lock, exactly one wins.
"""

import threading

import psycopg
import pytest
from psycopg.rows import dict_row

from app.services import events

from .conftest import TEST_DATABASE_URL, Data


def _race(event_id: int, students: list[int]) -> list[dict]:
    barrier = threading.Barrier(len(students))
    results: list[dict] = []
    errors: list[BaseException] = []
    lock = threading.Lock()

    def take_place(student_id: int) -> None:
        try:
            with psycopg.connect(TEST_DATABASE_URL, autocommit=True, row_factory=dict_row) as conn:
                barrier.wait()  # every transaction starts at the same moment
                result = events.register(conn, student_id, event_id)
            with lock:
                results.append(result)
        except BaseException as exc:
            with lock:
                errors.append(exc)

    threads = [threading.Thread(target=take_place, args=(s,)) for s in students]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=30)
    assert not errors, errors
    return results


@pytest.mark.parametrize("round_", range(5))
def test_two_students_tap_the_last_place_at_the_same_moment(data: Data, round_: int) -> None:
    event = data.event(data.community(data.student()), limit=2)
    data.registration(data.student(), event)  # one place left
    a, b = data.student(), data.student()

    results = _race(event, [a, b])

    assert sorted(r["status"] for r in results) == ["confirmed", "waiting_list"]
    assert (
        data.scalar(
            "SELECT COUNT(*) FROM registration WHERE event_id = %s AND status = 'confirmed'", event
        )
        == 2
    )


def test_eight_students_for_one_place_get_one_seat_and_a_clean_queue(data: Data) -> None:
    event = data.event(data.community(data.student()), limit=1)
    students = [data.student() for _ in range(8)]

    results = _race(event, students)

    confirmed = [r for r in results if r["status"] == "confirmed"]
    positions = sorted(r["position"] for r in results if r["status"] == "waiting_list")
    assert len(confirmed) == 1
    assert positions == list(range(1, 8))
