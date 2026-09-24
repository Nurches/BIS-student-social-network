# Requirements — Student Social Network

Basics of Information Systems, Lab 04. Team artifact.

| Name | Student ID | Area |
|---|---|---|
| Ualikhan Gulnazym | 24B032093 | Systems Analysis & Requirements |
| Taubay Laila | 24B032051 | Data & Database |
| Turarbek Nurassyl | 24B032077 | Application & Development |
| Nurkasymova Akbota | 24B031933 | Architecture & Security |
| Shpanova Madina | 24B032120 | Testing, Analytics & Integration |

## 1. Target stakeholder and problem

**Target stakeholder:** a first-year bachelor student during the first semester of study.

**Problem:** our university has no fixed academic groups: every student takes a different
combination of courses and therefore belongs to a different set of chats each semester. As a
result, university event announcements (student clubs, olympiads, career days, deadlines) are
spread across five or more WhatsApp and Telegram chats, Instagram stories and paper
noticeboards, and no chat covers all of them. A first-year student typically sees an
announcement only after the registration deadline has passed, or registers for an event whose
places are already taken. There is no single place where a student sees only the announcements
that concern them, with a deadline they can still meet.

## 2. Functional Requirements

- **FR-01:** The system shall send a push notification to every student subscribed to a
  community when that community publishes an event announcement.
- **FR-02:** The system shall reject the publication of an event announcement if its
  registration deadline is earlier than the current date and time.
- **FR-03:** The system shall reject a registration request for an event that has already
  reached its participant limit and shall offer the student the waiting list instead.

## 3. Non-Functional Requirements

- **NFR-01 (Performance):** 95% of feed load requests shall return a result within 2 seconds
  when 1000 students are using the system simultaneously.
- **NFR-02 (Security):** The system shall store every password hashed with bcrypt (cost factor
  12 or higher) and shall lock an account for 15 minutes after 5 failed login attempts within a
  10-minute window.

## 4. Business Rule / Constraint

**BR-01:** Only a person with a valid university email address may create an account, and only
a student whose community-admin role has been confirmed by the Student Union office may publish
event announcements. All other users may read, react and register only.

## 5. Acceptance Criteria (FR-02)

**GIVEN** a confirmed community admin is creating an event announcement and the current date is
24.09.2026,
**WHEN** the admin sets the registration deadline to 20.09.2026 and presses "Publish",
**THEN** the system rejects the publication, keeps all data already entered in the form, and
displays the message "Registration deadline must be later than the current date and time".

## 6. Requirements Traceability Matrix

| ID | Business Need | Requirement | Test / Status |
|---|---|---|---|
| R-01 | Student must learn about an event in time | The system notifies all subscribers when an event is published | TC-01 · Not run |
| R-02 | Student must not see events that can no longer be joined | The system rejects events with a past registration deadline | TC-02 · Not run |
| R-03 | Student must not register for a full event | The system rejects registration over the limit and offers the waiting list | TC-03 · Not run |

The full matrix with six rows and eight test cases is in `test_cases_and_rtm.xlsx`.

## 7. Weak requirement found and fixed

**Before:** "The system shall be user-friendly and show announcements quickly."

**Problem:** "user-friendly" and "quickly" cannot be measured or tested, and the sentence mixes
two different things in one requirement.

**After:** the sentence was split into FR-01 (a single testable behaviour: the notification is
sent to subscribers) and NFR-01 (a measurable limit: 95% of requests within 2 seconds at 1000
concurrent users).
