"""Request and response bodies of docs/api.md."""

from typing import Any, Literal

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator


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


# ---------- admin panel (/admin page; moderators and community owners) ----------


class AdminCommunityRef(BaseModel):
    community_id: int
    name: str
    is_confirmed: bool


class AdminMeOut(BaseModel):
    student_id: int
    email: str
    full_name: str
    is_moderator: bool = Field(description="Student Union moderator: sees and manages everything")
    communities: list[AdminCommunityRef] = Field(description="Communities this account owns")


class AdminOverviewOut(BaseModel):
    """Counts over the caller's scope: every community for a moderator, the
    owned ones for an owner. `students` and `devices` are moderator-only."""

    communities: int
    unconfirmed_communities: int
    subscribers: int = Field(description="Distinct students following a community in scope")
    open_events: int = Field(description="Published, registration deadline not passed")
    published_events: int
    cancelled_events: int
    confirmed_registrations: int
    waiting_registrations: int
    notifications: int
    notifications_sent: int
    notifications_unsent: int
    students: int | None
    devices: int | None


class AdminOwnerOut(BaseModel):
    student_id: int
    email: str
    full_name: str


class AdminCommunityOut(BaseModel):
    community_id: int
    name: str
    description: str | None
    is_confirmed: bool
    owner: AdminOwnerOut
    subscriber_count: int
    published_events: int
    open_events: int
    created_at: AwareDatetime


class CommunityCreateRequest(_Body):
    name: str = Field(min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=2000)
    owner_email: str = Field(min_length=1, max_length=120)
    is_confirmed: bool = Field(default=True, description="Confirmed by the Student Union (BR-01)")


class CommunityUpdateRequest(_Body):
    """Only the fields sent are changed; `description: null` clears it."""

    name: str | None = Field(default=None, min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=2000)
    owner_email: str | None = Field(default=None, min_length=1, max_length=120)
    is_confirmed: bool | None = None

    @model_validator(mode="after")
    def _required_fields_are_not_null(self) -> "CommunityUpdateRequest":
        _refuse_nulls(self, ("name", "owner_email", "is_confirmed"))
        return self


class AdminEventOut(BaseModel):
    event_id: int
    community_id: int
    community_name: str
    title: str
    description: str | None
    location: str | None
    starts_at: AwareDatetime
    registration_deadline: AwareDatetime
    participant_limit: int
    status: Literal["draft", "published", "cancelled"]
    state: Literal["open", "closed", "finished", "cancelled", "draft"] = Field(
        description="open: registration open; closed: deadline passed; finished: started"
    )
    confirmed_count: int
    waiting_count: int
    notified_count: int = Field(description="Notification rows of this event (all kinds)")
    sent_count: int = Field(description="Of them, accepted by FCM")
    created_at: AwareDatetime


class AdminEventListResponse(BaseModel):
    items: list[AdminEventOut]


class EventUpdateRequest(_Body):
    """Only the fields sent are changed; `description` and `location` may be null."""

    title: str | None = Field(default=None, min_length=1, max_length=160)
    description: str | None = Field(default=None, max_length=5000)
    location: str | None = Field(default=None, max_length=160)
    starts_at: AwareDatetime | None = None
    registration_deadline: AwareDatetime | None = None
    participant_limit: int | None = Field(default=None, gt=0, le=10_000)

    @model_validator(mode="after")
    def _required_fields_are_not_null(self) -> "EventUpdateRequest":
        _refuse_nulls(self, ("title", "starts_at", "registration_deadline", "participant_limit"))
        return self


class EventUpdateOut(BaseModel):
    event: AdminEventOut
    promoted: int = Field(description="Students moved from the waiting list by a larger limit")


class AdminRegistrationOut(BaseModel):
    registration_id: int
    student_id: int
    email: str
    full_name: str
    status: Literal["confirmed", "waiting_list", "cancelled"]
    position: int | None = Field(description="Place on the waiting list, 1 = next")
    created_at: AwareDatetime
    updated_at: AwareDatetime


class AdminRegistrationsResponse(BaseModel):
    event: AdminEventOut
    items: list[AdminRegistrationOut]


class NotifyOut(BaseModel):
    new_recipients: int = Field(description="Subscribers who had no notification of this event")
    queued: int = Field(description="Notifications not yet accepted by FCM, sent again now")


class AdminNotificationOut(BaseModel):
    notification_id: int
    kind: Literal["event_published", "waiting_list_promoted"]
    event_id: int
    event_title: str
    community_name: str
    student_email: str
    student_name: str
    devices: int = Field(description="Push tokens the student has now")
    created_at: AwareDatetime
    sent_at: AwareDatetime | None
    is_read: bool


class AdminNotificationsResponse(BaseModel):
    items: list[AdminNotificationOut]


class PushTestOut(BaseModel):
    fcm_configured: bool = Field(description="False: FCM_SERVICE_ACCOUNT_JSON is empty")
    devices: int
    sent: int
    failed: int
    removed: int = Field(description="Tokens FCM reported as dead; deleted")


class AdminStudentOut(BaseModel):
    student_id: int
    email: str
    full_name: str
    enrolled_year: int | None
    is_moderator: bool
    is_locked: bool = Field(description="NFR-02 lockout in force")
    subscriptions: int
    active_registrations: int
    devices: int
    owned_communities: int
    created_at: AwareDatetime


class AdminStudentsResponse(BaseModel):
    items: list[AdminStudentOut]


class ModeratorRoleRequest(_Body):
    is_moderator: bool


def _refuse_nulls(body: BaseModel, names: tuple[str, ...]) -> None:
    """PATCH bodies: a field may be left out, but these may not be sent as null."""
    for name in names:
        if name in body.model_fields_set and getattr(body, name) is None:
            raise ValueError(f"{name} cannot be null")
