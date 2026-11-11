"""Request and response bodies of docs/api.md."""

from typing import Any, Literal

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field


class _Body(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


# ---------- errors (docs/api.md, "Conventions") ----------


class ValidationIssue(BaseModel):
    loc: list[str | int]
    msg: str
    type: str


class ErrorOut(BaseModel):
    """Every error body: `{ "error": "<code>" }`, plus the optional fields below."""

    error: str = Field(description="Stable snake_case code the client switches on")
    retry_after_minutes: int | None = Field(
        default=None, description="423 `account_locked` only: minutes left, never 0"
    )
    detail: list[ValidationIssue] | None = Field(
        default=None, description="422 `validation_failed` only: what did not match"
    )


# ---------- auth ----------


class RegisterRequest(_Body):
    email: str = Field(max_length=120)
    password: str = Field(max_length=200)  # length rules give their own error codes
    full_name: str = Field(min_length=1, max_length=120)
    faculty: str | None = Field(default=None, max_length=80)
    enrolled_year: int | None = Field(default=None, ge=1990, le=2100)


class LoginRequest(_Body):
    email: str = Field(max_length=120)
    password: str = Field(max_length=200)


class StudentOut(BaseModel):
    student_id: int
    email: str
    full_name: str


class LoginResponse(BaseModel):
    token: str
    student: StudentOut


# ---------- events ----------


class EventOut(BaseModel):
    event_id: int
    community_id: int
    community_name: str
    title: str
    description: str | None
    location: str | None
    starts_at: AwareDatetime
    registration_deadline: AwareDatetime
    participant_limit: int
    free_places: int
    my_status: Literal["confirmed", "waiting_list"] | None
    waiting_position: int | None


class FeedResponse(BaseModel):
    items: list[EventOut]
    next_cursor: str | None


class PublishEventRequest(_Body):
    title: str = Field(min_length=1, max_length=160)
    description: str | None = Field(default=None, max_length=5000)
    location: str | None = Field(default=None, max_length=160)
    starts_at: AwareDatetime
    registration_deadline: AwareDatetime
    participant_limit: int = Field(gt=0, le=10_000)


class PublishEventResponse(BaseModel):
    event_id: int
    status: Literal["published"]


class RegistrationConfirmedOut(BaseModel):
    status: Literal["confirmed"]
    registration_id: int


class RegistrationWaitingOut(BaseModel):
    status: Literal["waiting_list"]
    position: int


class CancelOut(BaseModel):
    status: Literal["cancelled"]


# ---------- devices ----------


class DeviceTokenRequest(_Body):
    token: str = Field(min_length=1, max_length=512)
    platform: Literal["android", "ios", "web"] = "android"


class DeviceTokenDeleteRequest(_Body):
    token: str = Field(min_length=1, max_length=512)


# ---------- tools (not part of the product) ----------


class DataCheckResult(BaseModel):
    id: str
    title: str | None
    requirement: str | None
    note: str | None
    status: Literal["pass", "fail", "error"]
    row_count: int | None
    truncated: bool
    columns: list[str]
    rows: list[list[Any]]
    duration_ms: int
    error: str | None


class DataChecksSummary(BaseModel):
    total: int
    passed: int
    failed: int
    errors: int


class DataChecksReport(BaseModel):
    ran_at: str  # ISO 8601 with offset, e.g. 2026-11-10T09:14:03+00:00
    database: str
    duration_ms: int
    summary: DataChecksSummary
    checks: list[DataCheckResult]


# ---------- communities and the student's own lists (MVP extension) ----------


class CommunityOut(BaseModel):
    community_id: int
    name: str
    description: str | None
    is_confirmed: bool = Field(description="Confirmed by the Student Union: may publish (BR-01)")
    subscriber_count: int
    upcoming_events: int = Field(description="Published events whose deadline has not passed")
    is_subscribed: bool


class EventListResponse(BaseModel):
    items: list[EventOut]


class NotificationOut(BaseModel):
    notification_id: int
    kind: Literal["event_published", "waiting_list_promoted"]
    event_id: int
    event_title: str
    community_name: str
    created_at: AwareDatetime
    is_read: bool


class NotificationsResponse(BaseModel):
    items: list[NotificationOut]
    unread_count: int
