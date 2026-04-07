import { config } from "dotenv";
import { Client } from "@notionhq/client";

config({ path: ".env.local" });

const notion = new Client({ auth: process.env.NOTION_API_KEY });
const PROJECTS_DB = process.env.NOTION_PROJECTS_DB_ID;
const ACTIONS_DB = process.env.NOTION_ACTIONS_DB_ID;

if (!PROJECTS_DB || !ACTIONS_DB) {
  console.error(
    "Missing NOTION_PROJECTS_DB_ID or NOTION_ACTIONS_DB_ID in .env.local"
  );
  process.exit(1);
}

// Small delay helper to avoid Notion rate limits
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Fetch all pages from a Notion database, handling pagination.
 */
async function fetchAllPages(databaseId, filter) {
  const pages = [];
  let startCursor = undefined;
  let hasMore = true;

  while (hasMore) {
    const query = { database_id: databaseId, page_size: 100 };
    if (startCursor) query.start_cursor = startCursor;
    if (filter) query.filter = filter;

    const response = await notion.databases.query(query);
    pages.push(...response.results);
    hasMore = response.has_more;
    startCursor = response.next_cursor;
  }

  return pages;
}

async function main() {
  console.log("Fetching projects...");
  const projects = await fetchAllPages(PROJECTS_DB);

  const projectMap = projects.map((p) => {
    const prefixProp = p.properties["Prefix"];
    const prefix =
      prefixProp?.rich_text?.[0]?.plain_text ?? "(no prefix)";
    return { id: p.id, prefix };
  });

  console.log(`Found ${projectMap.length} projects.\n`);

  console.log("Fetching all actions...");
  const allActions = await fetchAllPages(ACTIONS_DB);
  console.log(`Found ${allActions.length} total actions.\n`);

  for (const project of projectMap) {
    // Filter actions belonging to this project
    const projectActions = allActions.filter((action) => {
      const relation = action.properties["Project"]?.relation ?? [];
      return relation.some((r) => r.id === project.id);
    });

    if (projectActions.length === 0) {
      console.log(
        `Project ${project.prefix}: no actions, skipping.`
      );
      continue;
    }

    // Sort by created_time ascending (oldest first)
    projectActions.sort(
      (a, b) => new Date(a.created_time) - new Date(b.created_time)
    );

    // Filter out actions that already have a Task Number
    const needsNumber = projectActions.filter((action) => {
      const taskNum = action.properties["Task Number"]?.number;
      return taskNum === null || taskNum === undefined;
    });

    if (needsNumber.length === 0) {
      console.log(
        `Project ${project.prefix}: all ${projectActions.length} actions already numbered, skipping.`
      );
      continue;
    }

    // Determine the next number to assign.
    // Find the highest existing Task Number in this project's actions.
    let maxExisting = 0;
    for (const action of projectActions) {
      const num = action.properties["Task Number"]?.number;
      if (num != null && num > maxExisting) {
        maxExisting = num;
      }
    }

    let nextNumber = maxExisting + 1;
    let assigned = 0;

    for (const action of needsNumber) {
      await notion.pages.update({
        page_id: action.id,
        properties: {
          "Task Number": { number: nextNumber },
        },
      });

      assigned++;
      nextNumber++;

      // Throttle: small delay every 3 updates to respect rate limits
      if (assigned % 3 === 0) {
        await sleep(350);
      }
    }

    console.log(
      `Project ${project.prefix}: assigned ${maxExisting + 1}..${nextNumber - 1} to ${assigned} actions.`
    );
  }

  console.log("\nDone.");
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
