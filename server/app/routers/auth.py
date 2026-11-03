from fastapi import APIRouter, Depends

from ..config import Settings, get_settings
from ..db import Pool, get_pool
from ..schemas import LoginRequest, LoginResponse, RegisterRequest, StudentOut
from ..security import limit_login_rate
from ..services import auth

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", status_code=201, response_model=StudentOut, summary="Create an account")
def register(
    body: RegisterRequest,
    pool: Pool = Depends(get_pool),
    settings: Settings = Depends(get_settings),
) -> dict:
    """BR-01: `@kbtu.kz` only (422). Duplicate email: 409."""
    with pool.connection() as conn:
        return auth.register(conn, settings, **body.model_dump())


@router.post(
    "/login",
    response_model=LoginResponse,
    dependencies=[Depends(limit_login_rate)],
    summary="Get a 24-hour JWT",
)
def login(
    body: LoginRequest,
    pool: Pool = Depends(get_pool),
    settings: Settings = Depends(get_settings),
) -> dict:
    """NFR-02: the 5th wrong password within 10 minutes locks the account for
    15 minutes; every login during the lock answers 423."""
    with pool.connection() as conn:
        return auth.login(conn, settings, email=body.email, password=body.password)
