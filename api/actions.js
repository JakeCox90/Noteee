// PATCH /api/actions — update an action's status in Notion
// Body: { id: string, status: "To Do" | "In Progress" | "Done" }

import { Client } from "@notionhq/client";

const notion = new Client({ auth: process.env.NOTION_API_KEY });

export default async function handler(req, res) {
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

  const validStatuses = ["To Do", "In Progress", "Done"];
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
