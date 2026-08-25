#!/usr/bin/env node
/**
 * The Action's gate: which units of work became `ready` in this push?
 *
 *   node scripts/detect-ready-units.mjs <before-sha> <after-sha>
 *
 * Prints a JSON array for a workflow matrix — one entry per unit:
 *
 *   [{ "unit": "plans/foo.md", "files": "plans/foo.md", "model": "opus", "effort": "high" }]
 *
 * Dispatching on the *transition* to ready (not on "ready exists") is what
 * makes the status flip the spend button: old ready plans are never
 * re-dispatched by unrelated pushes, and a push with no flip produces an
 * empty array, which the workflow's `if:` turns into a skip.
 *
 * Units follow skills/plans/SKILL.md: a lone plan, or a feature folder
 * (`plans/feature-name/`) whose plans share fate — any member flipping to
 * ready dispatches the folder once, at the highest `model`/`effort` any
 * member asks for. Invalid hint values warn (stderr) and degrade to the
 * defaults (env DEFAULT_MODEL / DEFAULT_EFFORT, else opus / medium) —
 * a typo in frontmatter must not fail the run.
 */
import { execFileSync } from "node:child_process";

const [before, after] = process.argv.slice(2);
if (!after) {
  console.error("usage: detect-ready-units.mjs <before-sha> <after-sha>");
  process.exit(1);
}

const git = (...a) => execFileSync("git", a, { encoding: "utf8" }).trim();
const exists = (sha) => {
  try { git("cat-file", "-e", `${sha}^{commit}`); return true; } catch { return false; }
};
// A forced push or branch creation sends all-zeros as `before`; the parent of
// `after` is the honest fallback, and an orphan first commit compares to nothing.
const base = before && !/^0+$/.test(before) && exists(before) ? before
  : exists(`${after}^`) ? `${after}^` : null;

const show = (sha, path) => {
  // A file new in this push has no base version; that is data, not an error.
  try {
    return execFileSync("git", ["show", `${sha}:${path}`], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
  } catch { return null; }
};
const frontmatter = (text) => {
  const m = text?.match(/^---\n([\s\S]*?)\n---/);
  const fm = {};
  if (m) for (const line of m[1].split("\n")) {
    const kv = line.match(/^(\w+):\s*(.+?)\s*$/);
    if (kv) fm[kv[1].toLowerCase()] = kv[2].toLowerCase();
  }
  return fm;
};

const MODELS = ["haiku", "sonnet", "opus"];
const EFFORTS = ["low", "medium", "high", "xhigh", "max"];
const DEFAULT_MODEL = process.env.DEFAULT_MODEL || "opus";
const DEFAULT_EFFORT = process.env.DEFAULT_EFFORT || "medium";
const highest = (rank, values, fallback) => {
  const bad = values.filter((v) => v && !rank.includes(v));
  for (const v of bad) console.error(`warning: ignoring invalid frontmatter hint '${v}' (valid: ${rank.join(", ")})`);
  const ok = values.filter((v) => rank.includes(v));
  return ok.length ? rank[Math.max(...ok.map((v) => rank.indexOf(v)))] : fallback;
};

const changed = (base
  ? git("diff", "--name-only", base, after, "--", "plans")
  : git("ls-tree", "-r", "--name-only", after, "plans"))
  .split("\n").filter((f) => f.endsWith(".md"));

const SPECIAL = ["drafts", "complete", "completed"];
const flipped = changed.filter((f) => {
  const now = frontmatter(show(after, f)).status;
  const was = base ? frontmatter(show(base, f) ?? "").status : null;
  return now === "ready" && was !== "ready";
});

const units = new Map();
for (const f of flipped) {
  const segs = f.split("/"); // ["plans", maybe-folder, file]
  const folder = segs.length > 2 && !SPECIAL.includes(segs[1]) ? `plans/${segs[1]}` : null;
  const key = folder ?? f;
  if (units.has(key)) continue;
  const files = folder
    ? git("ls-tree", "-r", "--name-only", after, folder).split("\n").filter((x) => x.endsWith(".md"))
    : [f];
  const fms = files.map((x) => frontmatter(show(after, x)));
  units.set(key, {
    unit: key,
    files: files.join(" "),
    model: highest(MODELS, fms.map((m) => m.model), DEFAULT_MODEL),
    effort: highest(EFFORTS, fms.map((m) => m.effort), DEFAULT_EFFORT),
  });
}

process.stdout.write(JSON.stringify([...units.values()]));
