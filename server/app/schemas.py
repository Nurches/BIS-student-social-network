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
    checked_in_at: str | None = Field(
        default=None, description="409 `already_checked_in` on check-in: when the ticket was used"
    )
    student_name: str | None = Field(
        default=None, description="409 `already_checked_in` on check-in: whose ticket it is"
    )
    opens_at: str | None = Field(
        default=None, description="409 `check_in_not_open`: when check-in opens"
    )


# ---------- auth ----------


class RegisterRequest(_Body):
    email: str = Field(max_length=120)
    password: str = Field(max_length=200)  # length rules give their own error codes
    full_name: str = Field(min_length=1, max_length=120)
    faculty: str | None = Field(
        default=None, max_length=40, description="Faculty code, e.g. SITE (table `faculty`)"
    )
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
    status: Literal["published", "cancelled"] = Field(
        description="v4: a cancelled event stays visible to the students registered for it"
    )
    previous_starts_at: AwareDatetime | None = Field(
        description="v4: the start before the last reschedule; null if never moved"
    )
    cancelled_at: AwareDatetime | None
    ends_at: AwareDatetime = Field(
        description="v5: when the event ends (two hours after the start if not set)"
    )
    poster_url: str | None = Field(
        description="v5: path of the poster image (GET, no token), null without a poster"
    )
    checked_in_at: AwareDatetime | None = Field(
        description="v5: when the caller was checked in at the door, null if not"
    )
    my_rating: int | None = Field(description="v5: the caller's rating 1-5, null if not rated")
    feedback_open: bool = Field(
        description="v5: the caller may rate it now: checked in, ended, not rated yet"
    )


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
    ends_at: AwareDatetime | None = Field(
        default=None, description="v5: optional end; default two hours after `starts_at`"
    )


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


# ---------- ticket and feedback (Week 13, schema v5) ----------


class TicketOut(BaseModel):
    """FR-06: shown in "My events"; the organiser scans `qr` or types `code`."""

    event_id: int
    registration_id: int
    code: str = Field(description="6 characters, for a phone that cannot show the QR")
    qr: str = Field(description="Text of the QR code: QATYS-T1.<registration>.<signature>")
    checked_in_at: AwareDatetime | None
    check_in_opens_at: AwareDatetime = Field(description="3 hours before the start")
    check_in_closes_at: AwareDatetime = Field(description="2 hours after the end")


class FeedbackRequest(_Body):
    rating: int = Field(ge=1, le=5, description="1 = poor … 5 = excellent")
    comment: str | None = Field(default=None, max_length=500)


class FeedbackOut(BaseModel):
    event_id: int
    rating: int
    comment: str | None
    created_at: AwareDatetime


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


CommunityStatus = Literal["pending", "confirmed", "rejected"]


class CommunityOut(BaseModel):
    community_id: int
    name: str
    description: str | None
    is_confirmed: bool = Field(description="Confirmed by the Student Union: may publish (BR-01)")
    status: CommunityStatus = Field(
        description="v4: others see only confirmed communities; the owner also sees a pending one"
    )
    is_mine: bool = Field(description="The caller owns it (requested it)")
    subscriber_count: int
    upcoming_events: int = Field(description="Published events whose deadline has not passed")
    is_subscribed: bool


class CommunityRequestCreate(_Body):
    name: str = Field(min_length=3, max_length=120)
    description: str | None = Field(default=None, max_length=2000)


class CommunityRequestOut(BaseModel):
    """A community the caller asked for, with the Student Union's answer."""

    community_id: int
    name: str
    description: str | None
    status: CommunityStatus
    reject_reason: str | None = Field(description="Set by the moderator on a rejection")
    created_at: AwareDatetime
    reviewed_at: AwareDatetime | None


class CommunityRequestsResponse(BaseModel):
    items: list[CommunityRequestOut]
    pending_limit: int = Field(description="At most this many pending requests per student")


class EventListResponse(BaseModel):
    items: list[EventOut]


NotificationKind = Literal[
    "event_published",
    "waiting_list_promoted",
    "event_cancelled",
    "event_rescheduled",
    "community_approved",
]


class NotificationOut(BaseModel):
    notification_id: int
    kind: NotificationKind
    event_id: int | None = Field(description="Null only for `community_approved`")
    community_id: int
    event_title: str | None = Field(description="Null only for `community_approved`")
    community_name: str
    starts_at: AwareDatetime | None = Field(description="The event start now (after a move)")
    previous_starts_at: AwareDatetime | None
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
    status: CommunityStatus


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
    pending_requests: int = Field(description="v4: community requests waiting for a moderator")
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
    status: CommunityStatus
    reject_reason: str | None
    reviewed_at: AwareDatetime | None
    owner: AdminOwnerOut
    subscriber_count: int
    published_events: int
    open_events: int
    created_at: AwareDatetime


class CommunityRejectRequest(_Body):
    reason: str | None = Field(default=None, max_length=300, description="Shown to the student")


class CommunityReviewOut(BaseModel):
    community: AdminCommunityOut
    notified: int = Field(description="Owners who get the `community_approved` push (0 or 1)")


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
    state: Literal["open", "closed", "live", "finished", "cancelled", "draft"] = Field(
        description="open: registration open; closed: deadline passed; "
        "live: started, not ended (v5); finished: ended"
    )
    previous_starts_at: AwareDatetime | None = Field(description="v4: start before the last move")
    cancelled_at: AwareDatetime | None
    ends_at: AwareDatetime = Field(description="v5: the end (two hours after the start if not set)")
    poster_url: str | None = Field(description="v5: the poster, null without one")
    attended_count: int = Field(description="v5: confirmed students checked in at the door")
    feedback_count: int
    average_rating: float | None = Field(description="v5: mean of the ratings, null without any")
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
    ends_at: AwareDatetime | None = Field(
        default=None, description="v5: null = back to two hours after the start"
    )

    @model_validator(mode="after")
    def _required_fields_are_not_null(self) -> "EventUpdateRequest":
        _refuse_nulls(self, ("title", "starts_at", "registration_deadline", "participant_limit"))
        return self


class EventUpdateOut(BaseModel):
    event: AdminEventOut
    promoted: int = Field(description="Students moved from the waiting list by a larger limit")
    rescheduled_notified: int = Field(
        description="v4: registered students who get the `event_rescheduled` push (0 if not moved)"
    )


class EventCancelOut(BaseModel):
    event: AdminEventOut
    notified: int = Field(description="v4: registered students who get the `event_cancelled` push")


class AdminRegistrationOut(BaseModel):
    registration_id: int
    student_id: int
    email: str
    full_name: str
    status: Literal["confirmed", "waiting_list", "cancelled"]
    position: int | None = Field(description="Place on the waiting list, 1 = next")
    checked_in_at: AwareDatetime | None = Field(description="v5: checked in at the door")
    created_at: AwareDatetime
    updated_at: AwareDatetime


class AdminRegistrationsResponse(BaseModel):
    event: AdminEventOut
    items: list[AdminRegistrationOut]


class PosterOut(BaseModel):
    event_id: int
    mime: Literal["image/jpeg", "image/png", "image/webp"]
    size_bytes: int = Field(description="After re-encoding (EXIF and GPS removed)")
    width: int
    height: int
    uploaded_at: AwareDatetime
    poster_url: str


class CheckInRequest(_Body):
    ticket: str = Field(
        min_length=1, max_length=200, description="The scanned QR text, or the 6-character code"
    )


class CheckInOut(BaseModel):
    registration_id: int
    student_id: int
    full_name: str
    email: str
    checked_in_at: AwareDatetime
    attended_count: int = Field(description="Checked in so far, this one included")
    confirmed_count: int


class AdminFeedbackItem(BaseModel):
    rating: int
    comment: str | None
    created_at: AwareDatetime


class AdminFeedbackResponse(BaseModel):
    """Anonymous: the organiser sees what was said, not who said it."""

    event: AdminEventOut
    count: int
    average_rating: float | None
    distribution: list[int] = Field(description="How many 1s, 2s, 3s, 4s and 5s")
    items: list[AdminFeedbackItem]


class AnalyticsSummary(BaseModel):
    events: int = Field(description="Events that started")
    finished_events: int = Field(description="Of them, ended: no-show counts only these")
    registered: int = Field(description="Confirmed places of the ended events")
    attended: int
    no_show: int
    no_show_rate: float | None = Field(description="Percent of registered who did not come")
    attendance_rate: float | None
    feedback_count: int
    average_rating: float | None


class AnalyticsCommunity(AnalyticsSummary):
    community_id: int
    community_name: str


class AnalyticsEvent(BaseModel):
    event_id: int
    title: str
    community_id: int
    community_name: str
    starts_at: AwareDatetime
    ends_at: AwareDatetime
    finished: bool
    registered: int = Field(description="Confirmed places")
    attended: int = Field(description="Checked in at the door")
    no_show: int | None = Field(description="Null while the event is still live")
    no_show_rate: float | None
    feedback_count: int
    average_rating: float | None


class AnalyticsResponse(BaseModel):
    totals: AnalyticsSummary
    communities: list[AnalyticsCommunity]
    events: list[AnalyticsEvent]


class NotifyOut(BaseModel):
    new_recipients: int = Field(description="Subscribers who had no notification of this event")
    queued: int = Field(description="Notifications not yet accepted by FCM, sent again now")


class AdminNotificationOut(BaseModel):
    notification_id: int
    kind: NotificationKind
    event_id: int | None
    community_id: int
    event_title: str | None
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
