"""NFR-01 load test: 95% of feed loads under 2 s.

    locust -f loadtest/locustfile.py --host http://localhost:8000 \\
           --headless -u 200 -r 20 -t 60s --csv loadtest/result

Needs a seeded database (python seed.py --yes). Every simulated user shares one
of the seeded accounts: logging in 1000 times would measure bcrypt, not the feed.
"""

import random

import requests
from locust import HttpUser, between, events, task

STUDENTS = [
    "nurassyl",
    "akbota",
    "laila",
    "madina",
    "gulnazym",
    "aru",
    "dias",
    "alikhan",
    "zhanel",
]
PASSWORD = "qatys2026"  # noqa: S105 — the public demo password from seed.py
TOKENS: list[str] = []


@events.test_start.add_listener
def log_in_once(environment, **_: object) -> None:
    for name in STUDENTS:
        response = requests.post(
            f"{environment.host}/api/v1/auth/login",
            json={"email": f"{name}@kbtu.kz", "password": PASSWORD},
            timeout=30,
        )
        response.raise_for_status()
        TOKENS.append(response.json()["token"])


class Student(HttpUser):
    # A student opens the app, scrolls, opens an event: a few seconds apart.
    wait_time = between(1, 3)

    def on_start(self) -> None:
        self.client.headers["Authorization"] = f"Bearer {random.choice(TOKENS)}"

    @task(5)
    def feed(self) -> None:
        self.client.get("/api/v1/feed?limit=20", name="GET /feed")

    @task(1)
    def event_detail(self) -> None:
        self.client.get(f"/api/v1/events/{random.randint(1, 4)}", name="GET /events/{id}")
