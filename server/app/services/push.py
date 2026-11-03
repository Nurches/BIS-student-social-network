"""Push delivery over the FCM HTTP v1 API (FR-01).

Runs after the request has answered (FastAPI background task), so publishing
never waits for Google. Every notification row is delivered to every device
token of its student; `sent_at` is set once FCM accepts the message, and tokens
FCM reports as dead are deleted.
"""

import json
import logging
import threading
from dataclasses import dataclass
from enum import Enum
from typing import Protocol
from zoneinfo import ZoneInfo

import httpx
from psycopg_pool import ConnectionPool

from ..config import Settings
from ..db import Conn

log = logging.getLogger("qatys.push")

ANDROID_CHANNEL_ID = "events_high"
_FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"


class SendResult(Enum):
    SENT = "sent"
    INVALID_TOKEN = "invalid_token"  # noqa: S105 — not a secret; uninstalled app or rotated token: delete it
    FAILED = "failed"  # anything else: keep the token, sent_at stays NULL


@dataclass(frozen=True)
class PushMessage:
    token: str
    title: str
    body: str
    data: dict[str, str]


class PushSender(Protocol):
    def send(self, message: PushMessage) -> SendResult: ...


class LoggingPushSender:
    """Used when no Firebase key is configured (local runs, tests of other parts)."""

    def send(self, message: PushMessage) -> SendResult:
        log.info("FCM not configured, push not sent: %s", message.data)
        return SendResult.FAILED


class FcmPushSender:
    def __init__(self, service_account_json: str) -> None:
        # Imported here so the server starts without google-auth when FCM is off.
        from google.oauth2 import service_account

        info = json.loads(service_account_json)
        self._project_id: str = info["project_id"]
        self._credentials = service_account.Credentials.from_service_account_info(
            info, scopes=[_FCM_SCOPE]
        )
        self._lock = threading.Lock()
        self._http = httpx.Client(timeout=10)

    def _access_token(self) -> str:
        from google.auth.transport.requests import Request

        with self._lock:
            if not self._credentials.valid:
                self._credentials.refresh(Request())
            return self._credentials.token

    def send(self, message: PushMessage) -> SendResult:
        payload = {
            "message": {
                "token": message.token,
                "notification": {"title": message.title, "body": message.body},
                "data": message.data,
                # High priority + a high-importance channel: the phone vibrates
                # even in silent mode (brief §9, "Silent phone").
                "android": {
                    "priority": "high",
                    "notification": {"channel_id": ANDROID_CHANNEL_ID},
                },
                # iPhone: without a sound iOS delivers the alert silently;
                # with it, a muted phone still vibrates (per its settings).
                "apns": {"payload": {"aps": {"sound": "default"}}},
            }
        }
        try:
            response = self._http.post(
                f"https://fcm.googleapis.com/v1/projects/{self._project_id}/messages:send",
                headers={"Authorization": f"Bearer {self._access_token()}"},
                json=payload,
            )
        except Exception:
            log.exception("FCM request failed")
            return SendResult.FAILED

        if response.is_success:
            return SendResult.SENT
        if _is_dead_token(response):
            return SendResult.INVALID_TOKEN
        log.warning("FCM answered %s: %s", response.status_code, response.text[:300])
        return SendResult.FAILED


def _is_dead_token(response: httpx.Response) -> bool:
    if response.status_code == 404:
        return True
    try:
        details = response.json()["error"].get("details", [])
    except (ValueError, KeyError, AttributeError):
        return False
    return any(d.get("errorCode") in ("UNREGISTERED", "INVALID_ARGUMENT") for d in details)


def create_sender(settings: Settings) -> PushSender:
    if settings.fcm_service_account_json.strip():
        return FcmPushSender(settings.fcm_service_account_json)
    log.warning("FCM_SERVICE_ACCOUNT_JSON is empty: pushes will be logged, not sent")
    return LoggingPushSender()


def _texts(row: dict, zone: ZoneInfo) -> tuple[str, str]:
    deadline = row["registration_deadline"].astimezone(zone).strftime("%d %b, %H:%M")
    if row["kind"] == "waiting_list_promoted":
        return "You got a place", f"{row['title']}: you were moved from the waiting list."
    return row["title"], f"{row['community_name']} · register by {deadline}"


def deliver(
    pool: ConnectionPool[Conn],
    sender: PushSender,
    notification_ids: list[int],
    settings: Settings,
) -> None:
    if not notification_ids:
        return
    zone = ZoneInfo(settings.display_timezone)
    with pool.connection() as conn:
        rows = conn.execute(
            """
            SELECT n.notification_id, n.student_id, n.event_id, n.kind,
                   e.title, e.registration_deadline, c.name AS community_name
            FROM notification n
            JOIN event e     ON e.event_id = n.event_id
            JOIN community c ON c.community_id = e.community_id
            WHERE n.notification_id = ANY(%s) AND n.sent_at IS NULL
            """,
            (notification_ids,),
        ).fetchall()

        for row in rows:
            tokens = conn.execute(
                "SELECT token FROM device_token WHERE student_id = %s",
                (row["student_id"],),
            ).fetchall()
            title, body = _texts(row, zone)
            data = {"type": row["kind"], "event_id": str(row["event_id"])}

            delivered = False
            for t in tokens:
                result = sender.send(PushMessage(t["token"], title, body, data))
                if result is SendResult.SENT:
                    delivered = True
                elif result is SendResult.INVALID_TOKEN:
                    conn.execute("DELETE FROM device_token WHERE token = %s", (t["token"],))
            if delivered:
                conn.execute(
                    "UPDATE notification SET sent_at = NOW() WHERE notification_id = %s",
                    (row["notification_id"],),
                )
