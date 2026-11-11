# Ualikhan Gulnazym — Requirements & UX

Her artifacts: [`docs/requirements.md`](../requirements.md), the user flow of the main process
(FigJam, owner's drafts — Nurassyl shares the board), a usability test with 3 students and
three interface changes with before / after.

## Week 11

Prepared by the AI agent in Nurassyl's session (W11-8): the test kit and the SUS calculator.
**The sessions, the answers, the findings and the choice of changes are Gulnazym's.** The
agent fills the Findings sheet only from her notes and only after she sends them.

### The kit

* [`gulnazym/usability-test.md`](gulnazym/usability-test.md) — goal, participants, consent
  line, the four tasks in a student's words, what to observe, the note template, the 10 SUS
  statements.
* [`gulnazym/sus.xlsx`](gulnazym/sus.xlsx):
  * **SUS** — one row per participant (P1–P3), 10 answers 1–5 (other values are refused),
    the score and the average fill in automatically. The row *Formula check* (all answers 3)
    must show **50**: if it does, the formula works in her copy of Excel / Numbers / Google
    Sheets.
  * **Statements** — the 10 standard SUS statements.
  * **Findings** — problem, how many participants, severity, priority (filled in
    automatically), screen, task, source note.
  * **Changes** — before, after, reason, requirement, rough cost, status.
* The formula was checked with an independent spreadsheet engine on three known examples:
  all 3s → 50, the best answers → 100, the worst → 0, their average → 50.

**Note (11 Nov):** the app got a new design and new screens (tabs, Explore, inbox). Run the
sessions on the TestFlight build with this design: it is the "before" of the three changes.

### How to run a session (10 minutes per student)

1. Find 3 students outside the team; agree a time with Nurassyl (he publishes Career Day
   during task 1 and lends the test iPhone).
2. Follow `usability-test.md` word for word: consent, intro, tasks T1–T4 with a stopwatch,
   then the SUS form.
3. Do not help during a task. If they are stuck for over a minute, give one hint and mark
   *Help*.
4. Type the notes into `sus.xlsx` the same day.

### How to pick the three changes

For each finding: **priority = participants × severity**, then prefer the **cheapest** among
the top ones. Example of reading the sheet: a problem seen by 3 of 3 with severity 2
(priority 6) beats one seen by 1 of 3 with severity 3 (priority 3). If two have the same
priority, take the one Nurassyl estimates as smaller.

Send the three chosen findings to Nurassyl. He gives a rough cost for each; they are built in
**Week 12**, not this week.

### Before / after files

* Before: screenshots from the test iPhone, named `before_C-1_<screen>.png`, … (Kit of
  4 November also has `before_screenshots/`).
* After: Figma frames named `after_C-1_<screen>`, exported as `after_C-1_<screen>.png`.
* Put both in `docs/team/gulnazym/changes/` and the names in the **Changes** sheet.
* After Week 12: repeat the task of each change with one participant and write the result
  in the *Status* column (*Re-tested*).

### Results

| Date | Participants | Average SUS | Top finding |
|---|---|---|---|
| TODO(Gulnazym) | | | |

### Explain it yourself

I tested whether a student who has never seen Qatys can finish the main process: get a
notification, open the event, register or join the waiting list, and cancel. Three students
outside the team did four short tasks on a real iPhone while I timed them and wrote down
where they hesitated and what they said. After the tasks each filled in the System Usability
Scale, a standard 10-question form that gives a score from 0 to 100 (68 is average). I merged
the problems across participants and ranked them by how many people hit them and how badly,
then picked three changes, also looking at what is cheap to build. The AI agent prepared the
script, the note template and the spreadsheet with the formulas; I ran the sessions, wrote
the notes, chose the changes and made the before / after frames in Figma.

**Likely questions**

1. *Why only three participants?* — Small usability tests find most of the serious problems
   with a few users; we wanted the biggest problems of the main process, not statistics.
2. *How is the SUS score calculated?* — For odd statements answer − 1, for even ones 5 −
   answer, sum × 2.5. Our check row (all 3s) gives 50, so the formula is right.
3. *Why these three changes and not others?* — They had the highest priority (participants ×
   severity) and were cheap enough to build before the defence.
