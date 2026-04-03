# Noteee

Voice-to-action project management. Speak a thought, Claude categorises it, extracts actions, and routes everything to the right project in Notion.

---

## How it works

1. You speak a voice note (via WhisperFlow or iOS Shortcut)
2. Transcribed text hits the `/api/capture` endpoint
3. Claude reads your active projects from Notion, matches the note to a project, extracts and normalises actions
4. If confident, actions land directly in Notion. If unsure, it asks you to confirm the project
5. You open Notion and see clean, prioritised action lists per project

---

## Setup

### 1. Clone the repo

```bash
git clone https://github.com/JakeCox90/Noteee.git
cd Noteee
npm install
```

### 2. Create your Notion databases

You need three databases in Notion. Create each one and grab the database ID from the URL (`notion.so/YOUR_WORKSPACE/DATABASE_ID?v=...`).

**Projects database** — Properties:
- `Name` (Title)
- `Description` (Text)
- `Status` (Select: Active, Archived)

**Inbox database** — Properties:
- `Name` (Title)
- `Raw Transcription` (Text)
- `Project` (Relation → Projects)
- `Notes` (Text)
- `Status` (Select: New, Processed, Archived)

**Actions database** — Properties:
- `Name` (Title)
- `Project` (Relation → Projects)
- `Priority` (Select: High, Medium, Low)
- `Status` (Select: To Do, In Progress, Done)
- `Due Date` (Date)

### 3. Create a Notion integration

Go to https://www.notion.so/my-integrations, create a new integration, copy the token. Then share each of your three databases with the integration.

### 4. Set up environment variables

```bash
cp .env.local.example .env.local
```

Fill in your keys in `.env.local`.

### 5. Seed your existing to-dos

```bash
npm run seed
```

This will create all your projects and existing actions in Notion.

### 6. Deploy to Vercel

```bash
npm run deploy
```

Add your environment variables in the Vercel dashboard under Settings → Environment Variables.

### 7. Set up your iOS Shortcut

Create a new Shortcut with these steps:

1. **Dictate Text** — records your voice note
2. **Get Contents of URL** — POST to `https://your-vercel-url.vercel.app/api/capture` with body:
   ```json
   { "transcription": "[Dictated Text]" }
   ```
3. **Get Dictionary Value** — get `needs_clarification` from response
4. **If** `needs_clarification` is `true`:
   - **Choose from List** — show `options` from response
   - **Get Contents of URL** — POST again with `confirmed_project` set to chosen option and original `transcription`
5. **Show Notification** — show `project` and first `action` title from response

---

## Adding new projects

Just add a new page to your Projects database in Notion with a Name, Description, and Status = Active. The system picks it up automatically on the next capture.

---

## Query your actions

Open Notion, filter your Actions database by Project, sort by Priority. That's your action list per project.

Coming later: natural language querying via a `/api/query` endpoint — ask "what's next for Premiership Pyramid?" and get back a prioritised list.
