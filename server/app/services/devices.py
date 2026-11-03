"""FCM device tokens of the students' phones (FR-01)."""

from ..db import Conn


def save_token(conn: Conn, student_id: int, token: str, platform: str) -> None:
    """A token belongs to one phone: if another account used this phone
    before, the token moves to the caller."""
    with conn.transaction():
        conn.execute(
            """
            INSERT INTO device_token (student_id, token, platform)
            VALUES (%s, %s, %s)
            ON CONFLICT (token) DO UPDATE
               SET student_id = EXCLUDED.student_id,
                   platform   = EXCLUDED.platform,
                   updated_at = NOW()
            """,
            (student_id, token, platform),
        )


def delete_token(conn: Conn, student_id: int, token: str) -> None:
    with conn.transaction():
        conn.execute(
            "DELETE FROM device_token WHERE token = %s AND student_id = %s",
            (token, student_id),
        )
