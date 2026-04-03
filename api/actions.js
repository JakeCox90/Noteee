// GET  /api/actions — fetch all actions from Notion
// PATCH /api/actions — update an action's status in Notion
// Body: { id: string, status: "To Do" | "In Progress" | "Done" }

import { Client } from "@notionhq/client";

const notion = new Client({ auth: process.env.NOTION_API_KEY });
const ACTIONS_DB_ID = process.env.NOTION_ACTIONS_DB_ID;
const PROJECTS_DB_ID = process.env.NOTION_PROJECTS_DB_ID;

export default async function handler(req, res) {
  if (req.method === "GET") {
    return handleGet(req, res);
  }
  if (req.method !== "PATCH") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  let body = req.body;
  if (typeof body === "string") {
    try { body = JSON.parse(body); } catch (e) { body = {}; }
  }

  const { id, status } = body;

  if (!id || !status) {
    return res.status(400).json({ error: "id and status are required" });
  }

  const validStatuses = ["To Do", "In Progress", "Done", "Archived"];
  if (!validStatuses.includes(status)) {
    return res.status(400).json({ error: `status must be one of: ${validStatuses.join(", ")}` });
  }

  try {
    await notion.pages.update({
      page_id: id,
      properties: {
        Status: {
          select: { name: status },
        },
      },
    });

    return res.status(200).json({ success: true, id, status });
  } catch (err) {
    console.error("Error updating action:", err);
    return res.status(500).json({ error: "Failed to update action", detail: err.message });
  }
}

async function handleGet(req, res) {
  try {
    // Fetch all non-archived actions and active projects in parallel
    const [actionsRes, projectsRes] = await Promise.all([
      notion.databases.query({
        database_id: ACTIONS_DB_ID,
        filter: {
          property: "Status",
          select: { does_not_equal: "Archived" },
        },
        sorts: [{ timestamp: "created_time", direction: "descending" }],
      }),
      notion.databases.query({
        database_id: PROJECTS_DB_ID,
      }),
    ]);

    // Build project ID → name lookup
    const projectMap = {};
    for (const p of projectsRes.results) {
      projectMap[p.id] = p.properties.Name?.title?.[0]?.plain_text || "";
    }

    const actions = actionsRes.results.map((page) => {
      const props = page.properties;
      const projectRelation = props.Project?.relation?.[0]?.id;
      return {
        id: page.id,
        title: props.Name?.title?.[0]?.plain_text || "",
        priority: props.Priority?.select?.name || "medium",
        status: props.Status?.select?.name || "To Do",
        projectName: projectRelation ? (projectMap[projectRelation] || "") : "",
        createdAt: page.created_time,
      };
    });

    return res.status(200).json({ actions });
  } catch (err) {
    console.error("Error fetching actions:", err);
    return res.status(500).json({ error: "Failed to fetch actions", detail: err.message });
  }
}
