#!/usr/bin/env node
/**
 * Post a structured review onto a pull request as inline comments.
 *
 *   node scripts/post-review.mjs <pr-number> <review.json>
 *
 * review.json is what the reviewing agent emits:
 *
 *   {
 *     "summary": "one-paragraph overall assessment",
 *     "findings": [
 *       { "path": "src/App.tsx", "line": 3384, "body": "what breaks and how",
 *         "suggestion": "the exact replacement for that one line (optional)" }
 *     ]
 *   }
 *
 * Findings become review comments anchored to their lines, suggestions
 * become GitHub ```suggestion``` blocks the human applies with one click.
 * The review event is COMMENT, never REQUEST_CHANGES: the poster and the
 * factory PR author are the same bot, and GitHub refuses request-changes on
 * your own PR — the merge gate is the workflow's verdict output, not the
 * review state.
 *
 * A comment the API rejects (line outside the diff, renamed file) must not
 * cost the finding: on any inline failure the whole review is reposted as a
 * single comment listing every finding. Failing closed loses information;
 * falling back loses only the anchoring.
 */
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const [pr, jsonPath] = process.argv.slice(2);
const repo = process.env.GITHUB_REPOSITORY;
if (!pr || !jsonPath || !repo) {
  console.error("usage: GITHUB_REPOSITORY=owner/repo post-review.mjs <pr-number> <review.json>");
  process.exit(1);
}

let review;
try {
  const text = readFileSync(jsonPath, "utf8");
  // The agent's last message should be pure JSON, but a stray fence is not
  // worth losing a review over.
  review = JSON.parse(text.replace(/^\s*```(?:json)?\s*|\s*```\s*$/g, ""));
} catch (e) {
  console.error(`review.json did not parse (${e.message}) — posting it raw.`);
  const raw = readFileSync(jsonPath, "utf8");
  execFileSync("gh", ["pr", "comment", pr, "--body", `### Factory review (Codex)\n\n${raw}`], { stdio: "inherit" });
  process.exit(0);
}

const findings = (review.findings ?? []).filter((f) => f && f.path && f.body);
const summary = review.summary ?? "";
const header = "### Factory review (Codex)";

const asMarkdown = () =>
  [
    header,
    "",
    summary,
    "",
    ...findings.map((f) => `- \`${f.path}:${f.line ?? "?"}\` — ${f.body}${f.suggestion ? `\n\n  Suggested: \`${f.suggestion.trim()}\`` : ""}`),
  ].join("\n");

const postReview = (payload) =>
  execFileSync("gh", ["api", `repos/${repo}/pulls/${pr}/reviews`, "--input", "-"], {
    input: JSON.stringify(payload),
    stdio: ["pipe", "ignore", "pipe"],
  });

// Real review states when the PR author is the machine account (a different
// actor from this posting bot); when the author IS this bot — no PAT
// configured — GitHub refuses APPROVE/REQUEST_CHANGES on your own PR, so
// each event degrades to the next thing that still carries the content.
if (findings.length === 0) {
  const body = `${header}\n\n${summary || "No findings."}\n\nVERDICT: CLEAN`;
  try {
    postReview({ event: "APPROVE", body });
    console.log("approved");
  } catch {
    execFileSync("gh", ["pr", "comment", pr, "--body", body], { stdio: "inherit" });
  }
  process.exit(0);
}

const payload = (event) => ({
  event,
  body: `${header}\n\n${summary}\n\nVERDICT: FINDINGS`,
  comments: findings.map((f) => ({
    path: f.path,
    line: Number(f.line) || 1,
    side: "RIGHT",
    body: f.suggestion ? `${f.body}\n\n\`\`\`suggestion\n${f.suggestion.replace(/\n+$/, "")}\n\`\`\`` : f.body,
  })),
});

try {
  postReview(payload("REQUEST_CHANGES"));
  console.log(`requested changes with ${findings.length} inline finding(s)`);
} catch {
  try {
    postReview(payload("COMMENT"));
    console.log(`posted ${findings.length} inline finding(s) as comments (own-PR fallback)`);
  } catch (e) {
    console.error(`inline review rejected (${e.message}) — falling back to a plain comment.`);
    execFileSync("gh", ["pr", "comment", pr, "--body", `${asMarkdown()}\n\nVERDICT: FINDINGS`], { stdio: "inherit" });
  }
}
