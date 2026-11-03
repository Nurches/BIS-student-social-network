"""Request and response bodies of docs/api.md."""

from typing import Literal

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field


class _Body(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


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
