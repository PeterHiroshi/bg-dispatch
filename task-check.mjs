#!/usr/bin/env node
/**
 * task-check.mjs — Heartbeat integration for bg-dispatch
 *
 * Checks task status and returns JSON with actions needed.
 * Designed for OpenClaw agents to call during heartbeat checks.
 *
 * Usage: node task-check.mjs [--data-dir <path>] [--projects-dir <path>]
 *
 * Output: JSON object with arrays of tasks needing attention:
 *   - unnotified: completed tasks not yet acknowledged
 *   - interrupted: tasks in data/tasks/ with no running process
 *   - stalled: running tasks with no recent file activity
 */

import { readdirSync, readFileSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { execSync } from "node:child_process";

// Parse args
const args = process.argv.slice(2);
let dataDir = process.env.BG_DISPATCH_DATA_DIR || join(process.env.HOME || "/root", ".bg-dispatch/data");
let projectsDir = "";

for (let i = 0; i < args.length; i++) {
  if (args[i] === "--data-dir" && args[i + 1]) dataDir = resolve(args[++i]);
  if (args[i] === "--projects-dir" && args[i + 1]) projectsDir = resolve(args[++i]);
}

const tasksDir = join(dataDir, "tasks");

function readJson(path) {
  try { return JSON.parse(readFileSync(path, "utf-8")); }
  catch { return null; }
}

function isAgentRunning() {
  try {
    const out = execSync("ps aux", { encoding: "utf-8" });
    return out.includes("claude") && !out.includes("grep claude");
  } catch { return false; }
}

// Check completed tasks
const unnotified = [];
const needsPr = [];

if (existsSync(tasksDir)) {
  for (const dir of readdirSync(tasksDir, { withFileTypes: true })) {
    if (!dir.isDirectory()) continue;
    const metaPath = join(tasksDir, dir.name, "meta.json");
    const meta = readJson(metaPath);
    if (!meta || meta.status !== "done") continue;

    const info = {
      task_name: meta.task_name || "unknown",
      adapter: meta.adapter || "",
      workdir: meta.workdir || "",
      meta_path: metaPath,
      agent_teams: meta.agent_teams || false,
      effective_model: meta.effective_model || "",
      completed_at: meta.completed_at || "",
    };

    if (meta.notified !== true) unnotified.push(info);
    if (meta.notified === true && meta.pr_created !== true) needsPr.push(info);
  }
}

// Check interrupted tasks (centralized in data/tasks/)
const interrupted = [];
const agentRunning = isAgentRunning();

if (!agentRunning && existsSync(tasksDir)) {
  for (const dir of readdirSync(tasksDir, { withFileTypes: true })) {
    if (!dir.isDirectory()) continue;
    const metaPath = join(tasksDir, dir.name, "meta.json");
    const meta = readJson(metaPath);
    if (!meta) continue;
    // A task is "interrupted" if it was running but the agent is no longer active
    if (meta.status !== "running") continue;

    interrupted.push({
      task_name: meta.task_name || "unknown",
      needs_review: meta.needs_review || false,
      meta_path: metaPath,
      workdir: meta.workdir || "",
    });
  }
}

// Check stalled tasks
const stalled = [];

if (agentRunning && existsSync(tasksDir)) {
  for (const dir of readdirSync(tasksDir, { withFileTypes: true })) {
    if (!dir.isDirectory()) continue;
    const metaPath = join(tasksDir, dir.name, "meta.json");
    const meta = readJson(metaPath);
    if (!meta || meta.status !== "running") continue;

    const workdir = meta.workdir;
    if (workdir && existsSync(workdir)) {
      try {
        const out = execSync(
          `find "${workdir}" -maxdepth 3 -newer /dev/null -mmin -15 -type f 2>/dev/null | head -1`,
          { encoding: "utf-8" }
        );
        if (!out.trim()) {
          stalled.push({
            task_name: meta.task_name || "unknown",
            workdir,
            meta_path: metaPath,
          });
        }
      } catch { /* ignore */ }
    }
  }
}

console.log(JSON.stringify({
  unnotified,
  needs_pr: needsPr,
  interrupted,
  stalled,
  agent_running: agentRunning,
  needs_attention: unnotified.length > 0 || needsPr.length > 0 || interrupted.length > 0 || stalled.length > 0,
  checked_at: new Date().toISOString(),
}, null, 2));
