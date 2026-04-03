# Noteee — Claude Code Agent Instructions

## Project Overview
Noteee is a voice-to-action personal project management tool. Jake speaks a voice note, Claude extracts actions and routes them to the right project in Notion. The iOS app handles capture and task viewing — Notion is the database layer only, never the UI.

This is a personal productivity tool. Single user. No auth. No compliance. No payments.

## Tooling
- **GitHub**: All code, PRs, issues, ADRs
- **Linear**: ALL tasks must exist in Linear before work begins (team key: `NTE`)
- **Notion**: Database layer (Projects, Inbox, Actions) + decision log

## Agent Instructions
Each agent has its own CLAUDE.md in agents/{role}/. Read yours before starting work.
- Orchestrator: agents/orchestrator/CLAUDE.md (opus)
- PM: agents/pm/CLAUDE-pm.md (sonnet)
- Backend: agents/backend/CLAUDE-backend.md (sonnet)
- iOS: agents/ios/CLAUDE-ios.md (sonnet)

## Key Docs
- Project overview: docs/project-overview.md
- Phasing: docs/phasing.md
- Domain rules: docs/domain-rules/noteee-rules.md (authoritative business logic specification)
- PRDs: docs/prd/
- Active plans: docs/plans/active/

## Non-Negotiable Rules

### Before Starting ANY Task
1. Find the Linear task — if it doesn't exist, create it
2. Move Linear task to "In Progress"
3. Create a feature branch: `feature/NTE-{id}-{short-description}`
4. Read relevant PRD before writing any code

### Completing Work
1. All code changes go via Pull Request — NEVER push directly to main
2. PR template must be filled out completely
3. Move Linear task to "In Review" when PR is raised

### Gate Decisions
If you encounter a decision marked GATE:
- STOP — do not make the decision yourself
- Create a Linear task assigned to the human owner
- Continue with other unblocked work while waiting

### Escalation Triggers (always escalate)
- Any decision with cost implications (API pricing, paid services)
- Changes to the Notion database schema
- App Store submission decisions
- Adding new third-party dependencies

## Architecture Principles
- App talks to Vercel API only — never calls Notion or Claude directly
- All business logic lives server-side in Vercel functions
- No secrets in source code — use environment variables only
- Notion is the single source of truth for all data

## Tech Stack
| Layer | Technology |
|-------|-----------|
| iOS app | SwiftUI (iOS 17+), MVVM |
| API | Vercel serverless (Node.js, ES modules) |
| AI | Claude API via `@anthropic-ai/sdk` |
| Transcription | Whisper API |
| Database | Notion via `@notionhq/client` |
| Hosting | Vercel |

## Branch Strategy
- main — production, protected
- feature/NTE-* — all feature work
- fix/NTE-* — bug fixes
- chore/NTE-* — non-feature changes

## Current Phase
Read `docs/phasing.md` for phase overview and `docs/prd/` for current PRDs.

## Behaviour Rules
- Never ask for yes/no confirmation — proceed with the most conservative, reversible option
- Never ask "should I proceed?" — proceed
- When in doubt, choose the option that is easiest to undo
- Only stop for: missing credentials, GATE decisions, irreversible actions
