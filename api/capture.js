import Anthropic from "@anthropic-ai/sdk";
import { Client } from "@notionhq/client";

const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
const notion = new Client({ auth: process.env.NOTION_API_KEY });

const PROJECTS_DB_ID = process.env.NOTION_PROJECTS_DB_ID;
const INBOX_DB_ID = process.env.NOTION_INBOX_DB_ID;
const ACTIONS_DB_ID = process.env.NOTION_ACTIONS_DB_ID;

async function getProjects() {
  const response = await notion.databases.query({
    database_id: PROJECTS_DB_ID,
    filter: { property: "Status", select: { equals: "Active" } },
  });

  return response.results.map((page) => ({
    id: page.id,
    name: page.properties.Name.title[0]?.plain_text || "",
    description: page.properties.Description?.rich_text[0]?.plain_text || "",
  }));
}

// Route + extract: used on first pass when project is unknown
async function routeAndExtract(transcription, projects) {
  const projectList = projects
    .map((p) => `- ${p.name}: ${p.description}`)
    .join("\n");

  const response = await anthropic.messages.create({
    model: "claude-haiku-4-5-20251001",
    max_tokens: 1000,
    messages: [
      {
        role: "user",
        content: `You are an action extraction system for a personal project tool.

Active projects:
${projectList}

1. Match the note to the best project (>80% confidence) or ask for clarification.
2. Extract concrete actions (verb-first, specific, one per item).
3. Assign priority: high, medium, or low.

Confident match — return JSON:
{"confident":true,"project_name":"...","actions":[{"title":"...","priority":"high|medium|low"}],"notes":"..."}

Not confident — return JSON:
{"confident":false,"question":"...","options":["Project A","Project B"]}

IMPORTANT: "options" must contain EXACT project names from the list above. No descriptions, no extra text — just the project name as written.

Return ONLY the JSON object. No other text.

Voice note: "${transcription}"`,
      },
    ],
  });

  return parseJSON(response.content[0].text);
}

// Extract only: used when project is already confirmed
async function extractActions(transcription, projectName) {
  const response = await anthropic.messages.create({
    model: "claude-haiku-4-5-20251001",
    max_tokens: 1000,
    messages: [
      {
        role: "user",
        content: `Extract concrete actions from this voice note. The project is "${projectName}".

Rules: verb-first, specific, one action per item. Assign priority: high, medium, or low.

Return ONLY this JSON object, no other text:
{"actions":[{"title":"...","priority":"high|medium|low"}],"notes":"..."}

Voice note: "${transcription}"`,
      },
    ],
  });

  return parseJSON(response.content[0].text);
}

// Robust JSON extraction — handles markdown fences and trailing text
function parseJSON(text) {
  let clean = text.replace(/```json|```/g, "").trim();
  // Extract the first complete JSON object
  const start = clean.indexOf("{");
  if (start === -1) throw new Error("No JSON found in response");
  let depth = 0;
  for (let i = start; i < clean.length; i++) {
    if (clean[i] === "{") depth++;
    else if (clean[i] === "}") depth--;
    if (depth === 0) {
      return JSON.parse(clean.slice(start, i + 1));
    }
  }
  // Fallback
  return JSON.parse(clean);
}

// Write inbox + actions in parallel
async function writeToNotion(transcription, result, projectId) {
  const actions = result.actions || [];

  const writes = [
    // Inbox record
    notion.pages.create({
      parent: { database_id: INBOX_DB_ID },
      properties: {
        Name: { title: [{ text: { content: transcription.slice(0, 100) } }] },
        "Raw Transcription": { rich_text: [{ text: { content: transcription } }] },
        Project: { relation: [{ id: projectId }] },
        Notes: { rich_text: [{ text: { content: result.notes || "" } }] },
        Status: { select: { name: "Processed" } },
      },
    }),
    // All action records
    ...actions.map((action) =>
      notion.pages.create({
        parent: { database_id: ACTIONS_DB_ID },
        properties: {
          Name: { title: [{ text: { content: action.title } }] },
          Project: { relation: [{ id: projectId }] },
          Priority: { select: { name: action.priority } },
          Status: { select: { name: "To Do" } },
        },
      })
    ),
  ];

  await Promise.all(writes);
  return actions;
}

export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  let body = req.body;
  if (typeof body === "string") {
    try { body = JSON.parse(body); } catch (e) { body = {}; }
  }

  const transcription = body.transcription || body.Transcription;
  const confirmed_project = body.confirmed_project || body.Confirmed_project;

  if (!transcription) {
    return res.status(400).json({ error: "No transcription provided", received: body });
  }

  try {
    const projects = await getProjects();

    // Confirmed project — skip routing, just extract actions
    if (confirmed_project) {
      const project = projects.find(
        (p) => p.name.toLowerCase() === confirmed_project.toLowerCase()
      );
      if (!project) {
        return res.status(404).json({ error: "Project not found" });
      }

      const result = await extractActions(transcription, project.name);
      const actions = await writeToNotion(transcription, result, project.id);

      return res.status(200).json({ success: true, project: project.name, actions });
    }

    // First pass — route and extract
    const result = await routeAndExtract(transcription, projects);

    if (!result.confident) {
      return res.status(200).json({
        success: false,
        needs_clarification: true,
        question: result.question,
        options: result.options,
        transcription,
      });
    }

    const project = projects.find(
      (p) => p.name.toLowerCase() === result.project_name.toLowerCase()
    );
    if (!project) {
      return res.status(404).json({ error: "Matched project not found in Notion" });
    }

    const actions = await writeToNotion(transcription, result, project.id);
    return res.status(200).json({ success: true, project: result.project_name, actions });
  } catch (err) {
    console.error("Error processing note:", err);
    return res.status(500).json({ error: "Failed to process note", detail: err.message });
  }
}
