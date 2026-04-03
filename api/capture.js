import Anthropic from "@anthropic-ai/sdk";
import { Client } from "@notionhq/client";

const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
const notion = new Client({ auth: process.env.NOTION_API_KEY });

const PROJECTS_DB_ID = process.env.NOTION_PROJECTS_DB_ID;
const INBOX_DB_ID = process.env.NOTION_INBOX_DB_ID;
const ACTIONS_DB_ID = process.env.NOTION_ACTIONS_DB_ID;

// Fetch all projects from Notion so Claude knows what to route to
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

// Send transcription + project context to Claude
async function processWithClaude(transcription, projects) {
  const projectList = projects
    .map((p) => `- ${p.name}: ${p.description}`)
    .join("\n");

  const response = await anthropic.messages.create({
    model: "claude-sonnet-4-20250514",
    max_tokens: 1000,
    messages: [
      {
        role: "user",
        content: `You are an action extraction and organisation system for a personal project management tool.

The user has the following active projects:
${projectList}

Your job is to:
1. Match the note to the most relevant project based on content and project descriptions
2. Extract concrete, actionable to-do items
3. Normalise all to-dos so they are consistent, specific, and actionable (start with a verb, include enough context to act on)
4. Assign a priority: high, medium, or low
5. If you are confident about the project match (>80%), return it. If not, return a clarification question.

Always return valid JSON in this exact format:
{
  "confident": true,
  "project_name": "Project Name Here",
  "actions": [
    { "title": "Normalised action title", "priority": "high|medium|low" }
  ],
  "notes": "Any supporting context from the note that isn't an action"
}

If not confident, return:
{
  "confident": false,
  "question": "Was that note for [Project A] or [Project B]?",
  "options": ["Project A", "Project B"]
}

User's voice note:
"${transcription}"`,
      },
    ],
  });

  const text = response.content[0].text;
  const clean = text.replace(/```json|```/g, "").trim();
  return JSON.parse(clean);
}

// Write to Notion Inbox
async function writeToInbox(transcription, result, projectId) {
  await notion.pages.create({
    parent: { database_id: INBOX_DB_ID },
    properties: {
      Name: {
        title: [{ text: { content: transcription.slice(0, 100) } }],
      },
      "Raw Transcription": {
        rich_text: [{ text: { content: transcription } }],
      },
      Project: {
        relation: [{ id: projectId }],
      },
      Notes: {
        rich_text: [{ text: { content: result.notes || "" } }],
      },
      Status: {
        select: { name: "Processed" },
      },
    },
  });
}

// Write extracted actions to Notion Actions table
async function writeActions(actions, projectId) {
  for (const action of actions) {
    await notion.pages.create({
      parent: { database_id: ACTIONS_DB_ID },
      properties: {
        Name: {
          title: [{ text: { content: action.title } }],
        },
        Project: {
          relation: [{ id: projectId }],
        },
        Priority: {
          select: { name: action.priority },
        },
        Status: {
          select: { name: "To Do" },
        },
      },
    });
  }
}

// Main handler
export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const { transcription, confirmed_project } = req.body;

  if (!transcription) {
    return res.status(400).json({ error: "No transcription provided" });
  }

  try {
    const projects = await getProjects();

    // If user has confirmed a project after a clarification prompt
    if (confirmed_project) {
      const project = projects.find(
        (p) => p.name.toLowerCase() === confirmed_project.toLowerCase()
      );
      if (!project) {
        return res.status(404).json({ error: "Project not found" });
      }

      const result = await processWithClaude(transcription, projects);
      await writeToInbox(transcription, result, project.id);
      await writeActions(result.actions, project.id);

      return res.status(200).json({
        success: true,
        project: project.name,
        actions: result.actions,
      });
    }

    // First pass — let Claude decide
    const result = await processWithClaude(transcription, projects);

    if (!result.confident) {
      // Ask the user to clarify
      return res.status(200).json({
        success: false,
        needs_clarification: true,
        question: result.question,
        options: result.options,
        transcription, // pass back so Shortcut can resend with confirmed project
      });
    }

    // Claude is confident — find the project and write everything
    const project = projects.find(
      (p) => p.name.toLowerCase() === result.project_name.toLowerCase()
    );

    if (!project) {
      return res.status(404).json({ error: "Matched project not found in Notion" });
    }

    await writeToInbox(transcription, result, project.id);
    await writeActions(result.actions, project.id);

    return res.status(200).json({
      success: true,
      project: result.project_name,
      actions: result.actions,
    });
  } catch (err) {
    console.error("Error processing note:", err);
    return res.status(500).json({ error: "Failed to process note", detail: err.message });
  }
}
