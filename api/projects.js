// GET  /api/projects  — list all active projects
// POST /api/projects  — create a new project

import { Client } from "@notionhq/client";

const notion = new Client({ auth: process.env.NOTION_API_KEY });
const PROJECTS_DB_ID = process.env.NOTION_PROJECTS_DB_ID;

// Fetch all active projects from Notion
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

export default async function handler(req, res) {
  // ── GET /api/projects ────────────────────────────────────────────────────────
  if (req.method === "GET") {
    try {
      const projects = await getProjects();
      return res.status(200).json({ projects });
    } catch (err) {
      console.error("Error fetching projects:", err);
      return res
        .status(500)
        .json({ error: "Failed to fetch projects", detail: err.message });
    }
  }

  // ── POST /api/projects ───────────────────────────────────────────────────────
  if (req.method === "POST") {
    // Parse body — handle string or JSON (matches capture.js pattern)
    let body = req.body;
    if (typeof body === "string") {
      try {
        body = JSON.parse(body);
      } catch (e) {
        body = {};
      }
    }

    const name = body.name || body.Name;
    const description = body.description || body.Description || "";

    if (!name || typeof name !== "string" || !name.trim()) {
      return res.status(400).json({ error: "name is required" });
    }

    const trimmedName = name.trim();

    try {
      // Check for duplicate (case-insensitive) before writing
      const existing = await getProjects();
      const duplicate = existing.find(
        (p) => p.name.toLowerCase() === trimmedName.toLowerCase()
      );
      if (duplicate) {
        return res.status(409).json({
          error: "A project with that name already exists",
          id: duplicate.id,
          name: duplicate.name,
        });
      }

      // Create the new project in Notion
      const page = await notion.pages.create({
        parent: { database_id: PROJECTS_DB_ID },
        properties: {
          Name: {
            title: [{ text: { content: trimmedName } }],
          },
          Description: {
            rich_text: [{ text: { content: description } }],
          },
          Status: {
            select: { name: "Active" },
          },
        },
      });

      return res.status(201).json({ id: page.id, name: trimmedName });
    } catch (err) {
      console.error("Error creating project:", err);
      return res
        .status(500)
        .json({ error: "Failed to create project", detail: err.message });
    }
  }

  // ── Method not allowed ───────────────────────────────────────────────────────
  return res.status(405).json({ error: "Method not allowed" });
}
