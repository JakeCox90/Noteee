# Noteee — Project Overview

**Last updated:** 2026-04-03

---

## What It Is

Noteee is a voice-to-action personal project management tool. Jake speaks a voice note; Claude categorises it, extracts concrete actions, and routes them to the right project in Notion. Jake then views and manages his tasks inside the Noteee iOS app — Notion is the database layer only, never the UI.

The goal is zero friction capture. Jake should be able to speak a thought hands-free and trust that it lands in the right place, correctly structured, without touching Notion.

---

## Architecture

```
iOS App (SwiftUI)
    │
    ├── Voice capture → POST /api/capture
    │       ↓
    │   Vercel serverless (Node.js)
    │       ↓
    │   Claude API (action extraction + project matching)
    │       ↓
    │   Notion API (write to Inbox + Actions databases)
    │
    └── Task viewer → GET /api/actions, /api/projects
            ↓
        Vercel serverless (Node.js)
            ↓
        Notion API (read Actions + Projects databases)
```

The iOS app talks exclusively to the Vercel API layer. It never calls Notion or Claude directly. All business logic lives server-side.

---

## Tech Stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| iOS app | SwiftUI (iOS 17+) | Native, MVVM |
| API | Vercel serverless (Node.js, ES modules) | Already deployed |
| AI | Claude API via `@anthropic-ai/sdk` | `claude-sonnet-4-20250514` |
| Database | Notion via `@notionhq/client` | Three databases: Projects, Inbox, Actions |
| Hosting | Vercel | `https://noteee-jakecox90s-projects.vercel.app` |

---

## Notion Database Schema

### Projects
| Property | Type | Values |
|----------|------|--------|
| Name | Title | — |
| Description | Text | Used as context for Claude routing |
| Status | Select | Active, Archived |

### Inbox
| Property | Type | Notes |
|----------|------|-------|
| Name | Title | First 100 chars of transcription |
| Raw Transcription | Text | Full spoken text |
| Project | Relation | → Projects |
| Notes | Text | Non-action context from the note |
| Status | Select | New, Processed, Archived |

### Actions
| Property | Type | Values |
|----------|------|--------|
| Name | Title | Normalised action (starts with verb) |
| Project | Relation | → Projects |
| Priority | Select | High, Medium, Low |
| Status | Select | To Do, In Progress, Done |
| Due Date | Date | Optional |

---

## Existing API: `/api/capture`

The only endpoint currently deployed. Accepts `POST` with:
- `transcription` (string) — the spoken text
- `confirmed_project` (string, optional) — used when the user confirms a project after a clarification prompt

**Happy path:** Claude is confident → actions written to Notion → `{ success: true, project, actions }`

**Clarification path:** Claude is not confident → returns `{ needs_clarification: true, question, options, transcription }` → client re-POSTs with `confirmed_project`

The existing API works and is deployed. Phase 1 extends it, does not replace it.

---

## Current Limitations (motivating the iOS app)

1. The iOS Shortcut cannot handle the clarification flow gracefully — it can ask but has no real UI
2. There is no way to create a new project on the fly during capture
3. There is no task viewer — Jake has to open Notion to see his actions
4. No success/error feedback beyond a notification

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Platform | Native iOS (SwiftUI) | Jake's primary device is iPhone; native gives best mic access and UX |
| Backend | Keep existing Vercel API | It works. Extend, don't rewrite. |
| Database | Keep Notion | Already has data, already works, no migration cost |
| App talks to | Vercel API only | Keeps business logic server-side; app stays thin |
| New project creation | Via new API endpoint | Notion project creation is server-side logic, not client logic |
| AI model | Claude Sonnet | Already in use, good quality for extraction tasks |

---

## Repository Structure

```
/
├── api/
│   └── capture.js          # POST /api/capture — voice note processing (deployed)
├── scripts/
│   └── seed.js             # One-off data seed
├── docs/
│   ├── project-overview.md # This file
│   ├── prd/                # Per-phase PRDs
│   └── domain-rules/       # Authoritative business logic spec
├── agents/                 # Agent instruction files
├── package.json
└── vercel.json
```

iOS app will live at `/ios/` when Phase 1 begins.
