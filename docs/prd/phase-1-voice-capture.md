# Phase 1 — Voice Capture iOS App
**Status:** Ready for Build
**Linear:** TOK-5
**Last updated:** 2026-04-03

---

## Problem

Jake's current capture flow is an iOS Shortcut that dictates text and POSTs to `/api/capture`. It works for the happy path but fails on anything more complex:

- If Claude isn't confident about the project, the Shortcut can display a picker — but the UX is clunky and easy to dismiss accidentally
- If no project matches at all, there is no way to create one on the fly; the note either fails or gets mis-routed
- There is no useful feedback — Jake can't see what actions were extracted or confirm they're correct
- There is no error recovery — a failed POST gives a generic notification with no way to retry

The result is low trust in the system. If Jake suspects a note might not route correctly, he won't use it — and he falls back to Notion manually.

---

## Solution

A native iOS app (SwiftUI, iOS 17+) that replaces the Shortcut entirely and handles the full capture flow:

1. Single large mic button — tap to start recording, tap to stop
2. Audio is sent to Whisper API for transcription
3. Transcription is POSTed to the existing `/api/capture` endpoint
4. If Claude is confident: show a success screen listing the project name and extracted actions
5. If Claude needs clarification: show a bottom sheet with the project options; user taps one; app re-POSTs with `confirmed_project`
6. If no project matches: show a text field prompting Jake to name the new project; app calls `POST /api/projects` to create it, then re-POSTs the capture with the new project name
7. If the API fails: show a clear error with a retry button

Two new API endpoints are needed to support this:
- `POST /api/projects` — create a new project in Notion
- `GET /api/projects` — list active projects (used to validate a new project name doesn't already exist)

The existing `/api/capture` endpoint is unchanged.

---

## User Stories

**As Jake, I want to** tap a mic button and speak a note **so that** my voice is captured without any setup friction.

**As Jake, I want to** see which project my note was routed to and what actions were extracted **so that** I can trust the system did the right thing.

**As Jake, I want to** choose between project options when Claude isn't sure **so that** my note ends up in the right place even when it's ambiguous.

**As Jake, I want to** name and create a new project on the fly **so that** I'm not blocked when I'm working on something that doesn't have a project yet.

**As Jake, I want to** see a clear error and retry button when something goes wrong **so that** I don't lose a note due to a transient failure.

---

## Acceptance Criteria

### Recording
- [ ] Tapping the mic button starts recording and the button animates to indicate active recording
- [ ] Tapping the button again stops recording
- [ ] Recording stops automatically after 60 seconds of continuous audio
- [ ] If microphone permission is not granted, the app shows a permission prompt and links to Settings
- [ ] If no audio is detected after 5 seconds of recording, the app shows a "nothing recorded" message

### Transcription
- [ ] Audio is sent to Whisper API for transcription after recording stops
- [ ] A loading state is shown during transcription
- [ ] The transcribed text is displayed on screen before the capture API call is made
- [ ] If transcription fails or produces empty text, the app shows an error and does not submit

### Happy path (confident match)
- [ ] The transcription is POSTed to `/api/capture` as `{ "transcription": "..." }`
- [ ] On `{ success: true }`, a success view shows the matched project name and the list of extracted actions
- [ ] The success view has a "Done" button that resets to the mic screen

### Clarification path
- [ ] On `{ needs_clarification: true }`, a bottom sheet appears with the question text and project options as tappable buttons
- [ ] Tapping a project option re-POSTs to `/api/capture` with both `transcription` and `confirmed_project`
- [ ] The confirmed submission follows the happy path from that point

### New project path
- [ ] If the user dismisses the clarification sheet without selecting, a "Create new project" option is available
- [ ] Tapping it shows a text field prompting for the new project name
- [ ] Submitting calls `POST /api/projects` with the name and a default description
- [ ] After project creation, the app re-POSTs the original capture with the new project name as `confirmed_project`
- [ ] The completed submission follows the happy path from that point

### Error handling
- [ ] Network errors show a message and a retry button
- [ ] API 4xx/5xx errors show the error message and a retry button
- [ ] Retry uses the same transcription text without requiring re-recording

### New API endpoints
- [ ] `POST /api/projects` accepts `{ name, description }`, creates a Notion project with `Status: Active`, returns `{ id, name }`
- [ ] `GET /api/projects` returns the list of active projects `[{ id, name, description }]`
- [ ] Both endpoints return appropriate HTTP status codes and error messages on failure

---

## Execution Order

1. Set up the Xcode project at `/ios/` — SwiftUI app, iOS 17 deployment target, no third-party dependencies initially
2. Build `VoiceRecorderService` — wraps `AVAudioEngine`, exposes `startRecording()`, `stopRecording()`, saves audio file, publishes `state: RecordingState`
2a. Build `TranscriptionService` — sends recorded audio to Whisper API (via a new `/api/transcribe` endpoint or direct), returns transcript text
3. Build `CaptureViewModel` — owns `VoiceRecorderService`, manages submission state, drives UI state machine
4. Build `MicView` — the main screen: mic button, transcript preview, submission states
5. Build `ClarificationSheetView` — bottom sheet showing question + project options
6. Build `NewProjectSheetView` — text field + submit for creating a new project
7. Build `SuccessView` — shows project name and action list
8. Build `ErrorView` — shows error message with retry button
9. Build `CaptureAPIClient` — URLSession wrapper for `/api/capture`, `/api/projects` (GET + POST)
10. Implement `POST /api/projects` in Vercel (`api/projects.js`)
11. Implement `GET /api/projects` in Vercel (`api/projects.js` or separate file)
12. Wire `CaptureViewModel` to `CaptureAPIClient`; test full flow end-to-end against deployed API
13. Handle microphone permissions — `NSMicrophoneUsageDescription` in `Info.plist`

---

## Out of Scope

- Task viewer / Today view (Phase 2)
- Marking actions as done (Phase 2)
- Background processing or push notifications
- iPad or macOS support
- Editing the transcript before submission
- Inline creation of actions outside of voice capture
- Due date assignment during capture

---

## Open Questions

~~All resolved:~~
1. **Transcription**: Whisper API — more accurate than on-device, especially for proper nouns. Cost: ~$0.006/min, negligible for voice notes.
2. **New project description**: Claude generates it from transcription context. No extra step for Jake.
3. **Bundle ID**: `com.jakecox.noteee` — confirmed.
