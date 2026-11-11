# Usability test — Qatys (Week 11)

**Owner:** Gulnazym Ualikhan (Requirements & UX). Results go into [`sus.xlsx`](sus.xlsx).
**Only real sessions count:** nothing in this test may be filled in without a participant.

## Goal

Find where a first-time student hesitates or fails in the **main process**: get a
notification → open the event → register, or join the waiting list when it is full → cancel.
The three biggest problems become three interface changes in Week 12 (before / after).

## Participants

* **3 KBTU students who are not on the team** (and have not seen the app before).
* Each session takes **about 10 minutes**: 1 min intro, 6 min tasks, 3 min SUS.
* They use a **team iPhone** with Qatys from TestFlight, signed in with a spare demo account
  (`aru@`, `dias@`, `alikhan@kbtu.kz`; never `zhanel@`, it is used for the lockout test).
* Write **P1, P2, P3**, never full names.

**Consent line** (read it, write "Yes" in the notes only when they agree):

> "We are testing our app, not you. There are no wrong answers. I will take notes and time
> the tasks, no recording of your face or voice. Your name will not be written anywhere. You
> can stop at any time. Is that OK?"

## Before each session (Gulnazym + Nurassyl, 5 minutes)

1. Open https://qatys-api.onrender.com/api/v1/health (wake the server).
2. Sign in on the test iPhone with the participant's spare account; allow notifications.
3. Nurassyl publishes **"Career Day"** in Career Center (community 2) from `/admin` **when you
   give the sign** during task 1, so the push arrives in front of the participant.
4. Have a stopwatch and a printed note template (below).

## Say this

> "Imagine you are a student at KBTU and this app collects all university events in one
> place. I will give you small tasks. Please think aloud: say what you look at and what you
> expect. I cannot help you during a task; if you get stuck, say 'I give up', that is
> useful for us."

## Tasks (read them exactly like this)

| # | Say to the student | Done when |
|---|---|---|
| T1 | "You got a notification about Career Day. Register for it." | The app shows *Registered ✓* for Career Day |
| T2 | "CV clinic sounds useful. Try to get a place, then tell me: will you go or not?" | Joins the waiting list **and** says correctly that they are not confirmed yet |
| T3 | "You cannot go to Career Day after all. Free your place for someone else." | Registration cancelled |
| T4 | "How many free places does IT Job Fair have, and until when can you register?" | Says both the number and the deadline |

Start the stopwatch on "please start", stop it when the task is done or they say "I give up".

## What to observe

* **Time** per task (seconds).
* **Success:** *Yes* = alone · *Help* = after a hint · *No* = gave up.
* **Errors and hesitations:** wrong taps, going back, scrolling around, long pauses (> 5 s).
* **Quotes:** what they *say*, word for word ("Where is the button?", "Am I registered now?").
* Write what they **do and say**, not what you think they feel.

## Observer note template (one per participant)

```
Participant: P_   Date/time: ____   Course/faculty: ____   iPhone user before? Y / N
Consent: Yes / No

T1 notification → register     time ___ s   success Yes / Help / No
   errors / hesitations: ______________________________________________
   quote: "__________________________________________________________"
T2 full event → waiting list    time ___ s   success Yes / Help / No
   says confirmed? Y / N  errors: ________  quote: "___________________"
T3 cancel                       time ___ s   success Yes / Help / No
   errors / hesitations: ________________  quote: "____________________"
T4 free places + deadline       time ___ s   success Yes / Help / No
   answer given: ____________ correct? Y / N

Biggest problem I saw (screen + what happened): ___________________________

SUS answers (1–5):  Q1 _ Q2 _ Q3 _ Q4 _ Q5 _ Q6 _ Q7 _ Q8 _ Q9 _ Q10 _
```

## SUS — the 10 standard statements

Give them on paper after the tasks. Answer 1 = strongly disagree … 5 = strongly agree.

1. I think that I would like to use this app frequently.
2. I found the app unnecessarily complex.
3. I thought the app was easy to use.
4. I think that I would need the support of a technical person to be able to use this app.
5. I found the various functions in this app were well integrated.
6. I thought there was too much inconsistency in this app.
7. I would imagine that most people would learn to use this app very quickly.
8. I found the app very cumbersome to use.
9. I felt very confident using the app.
10. I needed to learn a lot of things before I could get going with this app.

Score: ((Q1−1) + (Q3−1) + (Q5−1) + (Q7−1) + (Q9−1) + (5−Q2) + (5−Q4) + (5−Q6) + (5−Q8) +
(5−Q10)) × 2.5 = 0…100. `sus.xlsx` does it; an average app scores 68.

## After each session

1. Thank them. Cancel their registrations if any are left (or tell Nurassyl).
2. Within an hour, type the notes into `sus.xlsx`: answers on sheet **SUS**, problems on
   **Findings** (merge the same problem across participants).
