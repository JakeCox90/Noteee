# Noteee — Phasing

**Last updated:** 2026-04-03

---

## Guiding Principle

Each phase must be useful on its own. Jake should be able to stop after any phase and have something that works better than what he had before.

---

## Phase 1 — Voice Capture iOS App

**The job:** Replace the iOS Shortcut with a proper native app that handles the full capture flow — including project clarification and new project creation — with clean feedback.

**Why this first:** The Shortcut is the weakest link. It breaks on clarification flows, can't create projects, and gives no useful feedback. A working capture UI is the foundation everything else sits on.

**What's included:**
- SwiftUI app with a single tap-to-record mic button
- Voice recording → transcription (using iOS `SFSpeechRecognizer` or similar)
- POST to existing `/api/capture` endpoint
- Handle the clarification flow natively: if `needs_clarification: true`, show a project picker sheet
- Handle no-match case: if no project fits, prompt Jake to name a new project, then create it via a new `/api/projects` endpoint
- Success state: show project name + extracted actions
- Error state: show what went wrong, option to retry

**New API work required:**
- `POST /api/projects` — create a new project in Notion (simple wrapper)
- `GET /api/projects` — list active projects (needed for new-project flow pre-flight)

**What's NOT included:**
- Task viewer (Phase 2)
- Editing or completing tasks (Phase 2)
- Any background processing or notifications
- iPad or macOS support

**Definition of done:** Jake can speak a note, see it routed correctly (or confirm/create a project), and trust that the actions are in Notion — all from the iOS app, no Shortcut involved.

---

## Phase 2 — Task Viewer

**The job:** Replace Notion as the task UI. Two views: Today (all projects, priority-sorted) and per-project action list. Ability to mark tasks done and change priority.

**Why this second:** Once capture is solid, the natural next problem is "where do I see what I need to do?" Notion is functional but not optimised for this. A clean native view wins.

**What's included:**
- Today view: all actions across all projects, sorted by priority, filterable by project
- Project view: tap a project → see its prioritised action list
- Mark action as Done
- Change action priority (High / Medium / Low)
- Pull-to-refresh
- Empty states

**New API work required:**
- `GET /api/actions` — list actions, filterable by project, status
- `PATCH /api/actions/:id` — update status or priority

**What's NOT included:**
- Due date setting from the app (can be done in Notion)
- Creating actions manually (capture is the creation path)
- Inline editing of action titles

**Definition of done:** Jake can open the app, see everything he needs to do today, mark things done, and never need to open Notion for day-to-day task management.

---

## Phase 3 — Polish and Depth (Future)

Items deliberately deferred. Not planned in detail yet.

- **Due dates** — set a due date from the capture flow or task view; surface overdue actions
- **Natural language query** — "what's next for DJ Booth?" answered by Claude
- **Widgets** — iOS home screen widget for Today view
- **Inbox review** — surface raw inbox items that haven't been actioned yet
- **Archive / project management** — archive or create projects from within the app
- **Notifications** — daily digest, overdue reminders
- **Siri / Shortcuts integration** — trigger capture from lock screen

---

## Phase Dependencies

```
Phase 1 (Capture)
    └── Phase 2 (Task Viewer)   — needs capture working; also needs /api/actions endpoints
            └── Phase 3 (Polish) — incremental on top of Phase 2
```

Phase 2 can reuse the iOS app shell from Phase 1. The Notion schema requires no changes between phases — all data is already structured correctly.

---

## What We're Not Building (Ever)

- Multi-user support — this is a personal tool
- Android app — iOS only
- Replacing Notion as the database — Notion stays as the backend store
- A web UI — iOS native only
- Paid features, accounts, auth — single user, no auth layer needed
