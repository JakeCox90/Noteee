# Noteee — Domain Rules

**Last updated:** 2026-04-03
**Status:** Authoritative. All engineering on core logic must match what is written here.

---

## 1. Voice Capture

### 1.1 Recording

- Recording is manually triggered (tap to start, tap to stop). There is no automatic start.
- Maximum recording duration is 60 seconds. Recording stops automatically at this limit.
- Minimum meaningful recording is any audio that produces a non-empty transcript after processing.
- If no audio is detected within the first 5 seconds of recording being active, the app treats this as an empty recording and shows an error — it does not submit.
- The app must hold a `AVAudioSession` category of `.record` during recording and release it on stop.

### 1.2 Transcription

- Transcription is performed by the Whisper API (OpenAI). Audio is sent from the iOS app to a backend endpoint (`POST /api/transcribe`) which forwards to Whisper.
- Transcription runs immediately after recording stops. A loading state is shown. The user sees the transcript before submission.
- If Whisper returns an empty string or the API call fails, the submission is blocked. The app shows "Couldn't transcribe — please try again."
- The raw transcript is sent to the capture API exactly as returned by Whisper. No client-side normalisation.
- Language hint: `en` (Whisper auto-detects, but hinting improves accuracy).
- Audio format: m4a or wav. Whisper accepts most common formats.

### 1.3 Submission

- The transcript is submitted as a single POST to `/api/capture` with body `{ "transcription": "<text>" }`.
- Submission happens once transcription is complete. The user does not manually trigger submission (it is automatic after transcription).
- If the user closes the app or navigates away during submission, the in-flight request completes (it is not cancelled).

---

## 2. Project Matching

### 2.1 How Claude matches projects

Claude receives the transcription text and the full list of active projects (name + description). It returns one of three responses:

**Confident match:**
```json
{
  "confident": true,
  "project_name": "Project Name",
  "actions": [...],
  "notes": "..."
}
```
Claude is confident when one project clearly aligns with the content of the note and there is no plausible alternative.

**Needs clarification:**
```json
{
  "confident": false,
  "question": "Was that note for Project A or Project B?",
  "options": ["Project A", "Project B"]
}
```
Claude returns clarification when two or more projects could plausibly match and the confidence is below approximately 80%.

**No match (not currently returned by API — future):**
Currently, if nothing matches, Claude may force-match to the closest project or return a clarification. The new project creation flow is triggered by the user choosing not to select from the clarification options, not by the API explicitly signalling "no match".

### 2.2 Project matching rules

- Only `Active` projects are sent to Claude. `Archived` projects are excluded.
- Project names are matched case-insensitively when looking up by name after clarification (`confirmed_project`).
- If `confirmed_project` is provided but does not match any active project name exactly (case-insensitive), the API returns 404.
- New projects created on the fly are immediately `Active` and are available for routing on the next capture.

### 2.3 Clarification flow

1. App receives `needs_clarification: true`
2. App displays `question` and `options` to the user
3. User selects an option
4. App re-POSTs with `{ "transcription": "<original>", "confirmed_project": "<selected>" }`
5. API processes as a confirmed match — Claude is called again with the same transcription but the project is now locked to the confirmed value

Note: Claude is called a second time in the confirmed path (see `capture.js` line 155). This is intentional — the action extraction still needs to run. The second call does not need to make a routing decision; Claude will extract actions for the given project.

### 2.4 New project creation flow

1. User is shown the clarification sheet but chooses not to select any option
2. User taps "Create new project"
3. User enters a project name
4. App calls `GET /api/projects` to check the name doesn't already exist (case-insensitive match)
5. If the name exists, the app tells the user and asks them to pick that project instead
6. If the name is new, app calls `POST /api/projects` with `{ name, description }` — description is either user-provided or Claude-generated from the transcription
7. On success, app re-POSTs the original capture with `confirmed_project` set to the new project name
8. The new project is live in Notion immediately and will appear in future capture routing

---

## 3. Action Extraction

### 3.1 What makes a valid action

An action must be:
- **Concrete** — something that can be physically done
- **Specific** — includes enough context to act on without referring back to the original note
- **Verb-first** — normalised to start with an imperative verb (e.g. "Write", "Review", "Send", "Build")
- **Single** — one action per item; compound tasks are split

Examples of good actions:
- "Write design specification for Chris covering agentic workflow patterns"
- "Apply for new passport"
- "Update 3D model to reflect current build dimensions"

Examples that should be split or rejected:
- "Think about the project" — not concrete
- "Write spec and review with Chris and send to team" — three actions, not one

### 3.2 Priority rules

Claude assigns priority based on urgency and importance signals in the spoken note. Default rules:

| Priority | When Claude assigns it |
|----------|----------------------|
| High | Explicit deadline or blocking, or user uses words like "urgent", "need to", "must", "today", "ASAP" |
| Medium | No urgency signals, but the task is clearly important |
| Low | Speculative, exploratory, or prefixed with "at some point", "eventually", "would be nice to" |

If no priority signals are present, default to Medium.

### 3.3 Notes field

The `notes` field captures context from the transcription that is not an action — background, observations, decisions made. It is stored on the Inbox record and is not surfaced in the task viewer. It exists for audit/recall purposes only.

### 3.4 Action count limits

- Minimum: 1 action per capture. If Claude cannot extract any action from a transcription, the capture still succeeds but `actions` is empty. The raw transcription is stored in Inbox with `Status: Processed`.
- Maximum: no hard limit. In practice, a single voice note should not yield more than ~10 actions. If Claude extracts more than 10, this is a signal the note was too long and should have been split — but it is not an error.

---

## 4. Data Storage

### 4.1 Inbox records

Every successful capture creates one Inbox record, regardless of the number of actions extracted. The Inbox record stores:
- The first 100 characters of the transcription as the Name (Notion title field limitation)
- The full raw transcription
- The matched project (relation)
- Any non-action notes
- Status: always `Processed` on write (no other status is set by the API)

The Inbox is append-only from the API's perspective. Records are never updated or deleted by the API.

### 4.2 Action records

Each extracted action creates one Action record in Notion. Fields written:
- Name (normalised action title)
- Project (relation)
- Priority (High / Medium / Low)
- Status: always `To Do` on creation

`Due Date` is not set by the capture flow. It can be set manually in Notion.

### 4.3 Project records

Projects have:
- Name (Title)
- Description (Text) — used as Claude context
- Status (Select): `Active` or `Archived`

Only `Active` projects are returned by `GET /api/projects` and sent to Claude.

---

## 5. Task Status State Machine

```
To Do → In Progress → Done
  ↑__________↓           (can move back from In Progress to To Do)
```

Valid transitions:
| From | To | Allowed |
|------|----|---------|
| To Do | In Progress | Yes |
| To Do | Done | Yes (skip In Progress) |
| In Progress | Done | Yes |
| In Progress | To Do | Yes (unstart) |
| Done | To Do | Yes (reopen) |
| Done | In Progress | No — must go via To Do |

The iOS app in Phase 1 does not expose status changes. This state machine applies from Phase 2 onwards.

---

## 6. API Behaviour

### 6.1 `/api/capture` (existing)

- Method: POST
- Auth: none (personal tool, no auth layer)
- Request: `{ transcription: string, confirmed_project?: string }`
- Response (success): `{ success: true, project: string, actions: Array<{ title, priority }> }`
- Response (clarification): `{ success: false, needs_clarification: true, question: string, options: string[], transcription: string }`
- Response (error): `{ error: string, detail?: string }` with appropriate HTTP status

### 6.2 `/api/projects` (new — Phase 1)

**GET**
- Returns all active projects
- Response: `{ projects: Array<{ id: string, name: string, description: string }> }`

**POST**
- Creates a new project in Notion
- Request: `{ name: string, description?: string }`
- `name` is required. `description` defaults to empty string if not provided.
- Returns 409 if a project with that name already exists (case-insensitive match)
- Response: `{ id: string, name: string }`

### 6.3 Error responses

All API errors return JSON in the format `{ error: string }`. HTTP status codes:
- 400: missing or invalid request body
- 404: referenced resource not found
- 405: wrong HTTP method
- 409: conflict (duplicate project name)
- 500: unexpected server error

---

## 7. Edge Cases

### 7.1 Ambiguous transcription

If the transcription is very short (e.g. "yeah" or a single word) and Claude cannot extract a meaningful action or project match, the API returns a `needs_clarification` response or an error. The app surfaces this as "Couldn't understand — please try again."

### 7.2 Project name collision during creation

If a user tries to create a project with a name that matches an existing active project (case-insensitive), `POST /api/projects` returns 409. The app shows "That project already exists" and offers to use the existing project.

### 7.3 Network failure mid-flow

If the network fails between recording stopping and submission completing, the transcript is preserved in the UI. The user can retry without re-recording. The retry re-uses the existing transcript.

### 7.4 Partial write to Notion

If writing the Inbox record succeeds but one or more Action records fail, the API returns a 500. The Inbox record is not rolled back (Notion does not support transactions). This is an acceptable edge case for a personal tool — the raw transcription is preserved in Inbox and can be manually actioned.

### 7.5 Duplicate actions from double-submission

If the user taps retry after a timeout where the first request actually succeeded, duplicate records may be created in Notion. There is no deduplication logic. Acceptable edge case for v1 — the duplicates are visible in Notion and can be manually deleted.

### 7.6 Very long transcriptions

Recording is capped at 60 seconds. Whisper handles files up to 25MB. The API has no explicit length limit on the transcript text, but extremely long transcriptions are bounded by Vercel's request body limit. Claude's `max_tokens: 1000` means very long inputs may result in truncated JSON — the API's JSON parse will fail and return a 500. Not a realistic concern for voice notes.

### 7.7 Archived project referenced in confirmed_project

If the user somehow submits `confirmed_project` with the name of an archived project, the API returns 404 (archived projects are excluded from `getProjects()`). The app surfaces this as a generic "project not found" error.
