from fastapi import APIRouter, Depends, Response

from ..db import Pool, get_pool
from ..schemas import DeviceTokenDeleteRequest, DeviceTokenRequest
from ..security import CurrentStudent, current_student
from ..services import devices

router = APIRouter(prefix="/me", tags=["devices"])


@router.put("/device-token", status_code=204, summary="Store this phone's FCM token")
def save_device_token(
    body: DeviceTokenRequest,
    me: CurrentStudent = Depends(current_student),
    pool: Pool = Depends(get_pool),
) -> Response:
    with pool.connection() as conn:
        devices.save_token(conn, me.student_id, body.token, body.platform)
    return Response(status_code=204)


@router.delete("/device-token", status_code=204, summary="Forget this phone's FCM token")
def delete_device_token(
    body: DeviceTokenDeleteRequest,
    me: CurrentStudent = Depends(current_student),
    pool: Pool = Depends(get_pool),
) -> Response:
    """Called on logout. 204 also when the token was not stored."""
    with pool.connection() as conn:
        devices.delete_token(conn, me.student_id, body.token)
    return Response(status_code=204)
