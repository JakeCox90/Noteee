# Noteee — Agent Entry Point
> This file is a MAP. It points you to docs/. It does not repeat what docs/ contains.
> Keep this file under 80 lines. If adding content here, ask: does this belong in docs/ instead?

## What This Project Is
Voice-to-action personal project management. iOS app (SwiftUI) + Vercel API + Notion as database.
Jake speaks a thought, Claude extracts actions and routes them. Jake views and manages tasks in the app, not Notion.
Human owner is the sole gate approver. Agents execute. Humans steer.

## Read Before Anything Else
| If you are...                      | Read first |
|------------------------------------|---|
| Starting any session               | `docs/phasing.md` — find the current phase |
| Building any feature               | `docs/prd/` — find the PRD and acceptance criteria |
| Touching capture or routing logic  | `docs/domain-rules/noteee-rules.md` — the authoritative rules spec |
| Unsure about architecture          | `docs/project-overview.md` |

## The 5 Rules That Override Everything
1. **If it's not in docs/, it doesn't exist.** Context in chat or someone's head is invisible to you.
2. **Failing CI = PR does not merge.** No exceptions.
3. **GATE decisions = stop and escalate.** Never guess on decisions marked GATE.
4. **Read the PRD before writing code.** Every time.
5. **Struggling = fix the environment first.** Missing tool/doc/guardrail beats re-prompting.

## Task Flow (every task, every time)
```
Find/create Linear task → In Progress
→ Read PRD + domain rules
→ Branch: feature/NTE-{id}-{desc}
→ Build → CI passes → PR with template
→ Move Linear to In Review
→ Human review
→ Merge → Linear Done
```

## Repo Structure
```
/
├── api/                           # Vercel serverless functions (Node.js)
│   └── capture.js                 # POST /api/capture — deployed, working
├── ios/                           # SwiftUI app (Phase 1+)
├── scripts/
│   └── seed.js                    # One-off Notion data seed
├── docs/
│   ├── project-overview.md
│   ├── phasing.md
│   ├── prd/                       # Per-phase PRDs
│   └── domain-rules/              # Authoritative business logic
├── agents/                        # Per-agent CLAUDE.md files
├── package.json
├── vercel.json
└── CLAUDE.md
```

## Branch Naming
- `main` — production, protected
- `feature/NTE-{id}-{desc}` | `fix/NTE-{id}-{desc}` | `chore/NTE-{id}-{desc}`

## Current Phase
See `docs/phasing.md`
