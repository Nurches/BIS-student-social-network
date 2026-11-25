"""Week 13 (FR-06): the ticket of a confirmed registration.

A ticket is not stored. It is derived from the registration id and the
server's secret with HMAC-SHA256, so it cannot be forged without the secret
and a registration has exactly one ticket:

* the QR payload ``QATYS-T1.<registration_id>.<signature>`` (scanned at the door);
* a 6-character code for a phone that cannot show the QR (typed in /admin).
  The code is unique among the registrations of one event with overwhelming
  probability (31^6 ≈ 8.9·10^8 values); the organiser types it on a given event,
  so the server compares it with that event's registrations only.

Rotating JWT_SECRET invalidates every ticket (the app fetches a fresh one).
"""

import base64
import hashlib
import hmac

TOKEN_PREFIX = "QATYS-T1"  # noqa: S105 — a format marker, not a secret
CODE_LENGTH = 6
# No 0/O, 1/I/L: the code is read aloud and typed by hand.
CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
_SIGNATURE_BYTES = 12  # 96 bits, 16 base64url characters


def _mac(secret: str, purpose: str, registration_id: int) -> bytes:
    message = f"qatys:{purpose}:v1:{registration_id}".encode()
    return hmac.new(secret.encode(), message, hashlib.sha256).digest()


def qr_payload(secret: str, registration_id: int) -> str:
    signature = base64.urlsafe_b64encode(_mac(secret, "ticket", registration_id)[:_SIGNATURE_BYTES])
    return f"{TOKEN_PREFIX}.{registration_id}.{signature.decode().rstrip('=')}"


def code(secret: str, registration_id: int) -> str:
    number = int.from_bytes(_mac(secret, "code", registration_id)[:8], "big")
    chars = []
    for _ in range(CODE_LENGTH):
        number, index = divmod(number, len(CODE_ALPHABET))
        chars.append(CODE_ALPHABET[index])
    return "".join(chars)


def normalize_code(text: str) -> str:
    """What the organiser typed: case, spaces and dashes do not matter."""
    return "".join(ch for ch in text.upper() if ch.isalnum())


def registration_from_payload(secret: str, payload: str) -> int | None:
    """The registration id of a genuine QR payload; None for anything else."""
    parts = payload.strip().split(".")
    if len(parts) != 3 or parts[0] != TOKEN_PREFIX or not parts[1].isdigit():
        return None
    registration_id = int(parts[1])
    if registration_id <= 0 or registration_id > 2**31 - 1:
        return None
    expected = qr_payload(secret, registration_id)
    return registration_id if hmac.compare_digest(expected, payload.strip()) else None


def looks_like_payload(text: str) -> bool:
    return text.strip().startswith(TOKEN_PREFIX + ".")
