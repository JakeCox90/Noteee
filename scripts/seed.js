import { Client } from "@notionhq/client";
import dotenv from "dotenv";
dotenv.config({ path: ".env.local" });

const notion = new Client({ auth: process.env.NOTION_API_KEY });

const PROJECTS_DB_ID = process.env.NOTION_PROJECTS_DB_ID;
const ACTIONS_DB_ID = process.env.NOTION_ACTIONS_DB_ID;

// ─── Project Definitions ───────────────────────────────────────────────────────
const PROJECTS = [
  {
    name: "Design Systems",
    description:
      "Multi-brand token governance and component library work across The Sun, New York Post, and NCA. Covers token architecture, documentation, native mobile (Swift/Kotlin), and Figma tooling.",
    status: "Active",
  },
  {
    name: "Token Drift",
    description:
      "Figma plugin for detecting token drift across federated multi-brand design system files. Snapshot-based schema diffing with GitHub as storage layer.",
    status: "Active",
  },
  {
    name: "DJ Booth Build",
    description:
      "Bespoke DJ booth and record storage unit built from 18mm marine ply. Features hydraulic lid, two Technics 1210 MK2 turntables, rotary mixer, and integrated lighting.",
    status: "Active",
  },
  {
    name: "Premiership Pyramid",
    description:
      "Web product focused on football league visualisation. Involves homepage and league page design, Figma-to-code pipeline, and MCP integration.",
    status: "Active",
  },
  {
    name: "Personal Admin",
    description:
      "Personal tasks and life admin not related to any specific project.",
    status: "Active",
  },
];

// ─── Seed Actions ──────────────────────────────────────────────────────────────
const ACTIONS = [
  // Design Systems
  {
    project: "Design Systems",
    title: "Create 2-page design specification for Chris documenting agentic workflow patterns and proposed implementation approach",
    priority: "High",
  },
  {
    project: "Design Systems",
    title: "Document token restriction rules at each inheritance level, specifying what flexibility is permitted and what is locked",
    priority: "High",
  },
  {
    project: "Design Systems",
    title: "Clarify typography extension rules — define what can and cannot be modified at the typography token level",
    priority: "Medium",
  },
  {
    project: "Design Systems",
    title: "Refine and update the Ways of Working documentation to reflect current team processes",
    priority: "Medium",
  },
  {
    project: "Design Systems",
    title: "Finalise Sun feedback documentation and circulate to stakeholders",
    priority: "High",
  },
  {
    project: "Design Systems",
    title: "Write design system rationale documentation covering architectural decisions and governance principles",
    priority: "Medium",
  },
  {
    project: "Design Systems",
    title: "Review and refine the contribution guidelines document for completeness and clarity",
    priority: "Medium",
  },
  {
    project: "Design Systems",
    title: "Add Text v1.1 token configuration to the design system library",
    priority: "High",
  },
  {
    project: "Design Systems",
    title: "Transfer all outstanding design system tickets from current tracking system into JIRA",
    priority: "Medium",
  },
  {
    project: "Design Systems",
    title: "Complete Icon Stack animation implementation and verify across breakpoints",
    priority: "Medium",
  },
  {
    project: "Design Systems",
    title: "Set up and complete spike in MCC library for IH Site integration",
    priority: "Medium",
  },
  {
    project: "Design Systems",
    title: "Research Figma's native token finder capabilities and write spec plan for a custom token finder plugin if gaps exist",
    priority: "Low",
  },

  // DJ Booth
  {
    project: "DJ Booth Build",
    title: "Update 3D model to reflect current build specifications and dimensions",
    priority: "High",
  },
  {
    project: "DJ Booth Build",
    title: "Break down full build into individual components with materials list and quantities",
    priority: "High",
  },
  {
    project: "DJ Booth Build",
    title: "Build 1520mm square record storage section according to updated plans",
    priority: "Medium",
  },
  {
    project: "DJ Booth Build",
    title: "Apply Osmo Polyx-Oil finish to all completed surfaces",
    priority: "Low",
  },

  // Premiership Pyramid
  {
    project: "Premiership Pyramid",
    title: "Test Figma MCP integration to validate design-to-code translation pipeline",
    priority: "High",
  },
  {
    project: "Premiership Pyramid",
    title: "Review homepage design and identify changes required for V1",
    priority: "High",
  },
  {
    project: "Premiership Pyramid",
    title: "Review league page design and identify changes required for V1",
    priority: "High",
  },
  {
    project: "Premiership Pyramid",
    title: "Update homepage layout to include all correct modules as per V1 specification",
    priority: "High",
  },
  {
    project: "Premiership Pyramid",
    title: "Finalise homepage design, confirm sign-off, and mark as ready for V1 development",
    priority: "High",
  },
  {
    project: "Premiership Pyramid",
    title: "Update league page UI to reflect latest design decisions",
    priority: "Medium",
  },

  // Personal Admin
  {
    project: "Personal Admin",
    title: "Apply for new passport",
    priority: "Medium",
  },
];

// ─── Seed Functions ────────────────────────────────────────────────────────────
async function seedProjects() {
  console.log("Seeding projects...");
  const projectIds = {};

  for (const project of PROJECTS) {
    const response = await notion.pages.create({
      parent: { database_id: PROJECTS_DB_ID },
      properties: {
        Name: { title: [{ text: { content: project.name } }] },
        Description: { rich_text: [{ text: { content: project.description } }] },
        Status: { select: { name: project.status } },
      },
    });

    projectIds[project.name] = response.id;
    console.log(`  ✓ Created project: ${project.name}`);
  }

  return projectIds;
}

async function seedActions(projectIds) {
  console.log("\nSeeding actions...");

  for (const action of ACTIONS) {
    const projectId = projectIds[action.project];
    if (!projectId) {
      console.warn(`  ✗ Project not found: ${action.project}`);
      continue;
    }

    await notion.pages.create({
      parent: { database_id: ACTIONS_DB_ID },
      properties: {
        Name: { title: [{ text: { content: action.title } }] },
        Project: { relation: [{ id: projectId }] },
        Priority: { select: { name: action.priority } },
        Status: { select: { name: "To Do" } },
      },
    });

    console.log(`  ✓ ${action.project}: ${action.title.slice(0, 60)}...`);
  }
}

async function run() {
  try {
    const projectIds = await seedProjects();
    await seedActions(projectIds);
    console.log("\n✅ Seed complete.");
  } catch (err) {
    console.error("Seed failed:", err.message);
    process.exit(1);
  }
}

run();
