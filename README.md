# factory

A software factory for any repository with a `plans/` folder: flip a plan's
frontmatter to `status: ready`, push, and an agent implements it into a pull
request. A second agent — a different vendor, on purpose — reviews the PR
with line-anchored findings, and a clean verdict plus green CI merges it.
Your job contracts to writing intent at one end and reading what merged at
the other.

Built for and alongside [plans](https://github.com/RatulMaharaj/plans), the
app that renders the `plans/` folder as a board — but callers only need the
folder and its frontmatter conventions, not the app.

## How it works

- **Dispatch is the status flip.** The gate diffs each push and dispatches
  only units whose status *became* `ready` — old ready plans never
  re-dispatch, and a push with no flip costs nothing.
- **Two modes.** A plan flipped on its own branch is implemented directly on
  that branch (the branch is the workbench and the claim) and PRs into the
  default branch: one branch, one PR, per feature. A plan flipped on the
  default branch builds in a worktree on an `impl/` branch.
- **Routing in frontmatter.** `model: haiku|sonnet|opus` and
  `effort: low|medium|high|xhigh|max` on the plan route its run; a feature
  folder (`plans/feature-name/`) is one unit at the highest values any
  member asks for. Invalid values degrade to the defaults with a warning.
- **Builder and reviewer are different vendors.** Claude Code implements
  (billed to a Claude subscription via OAuth token); Codex reviews (billed
  to a Codex subscription). Findings post as a Request-changes review with
  one-click suggestion blocks; `CLEAN` + green CI squash-merges.
- **Bounded and recorded.** Every run has a turn budget and wall-clock
  timeout, streams its transcript into the live log, and keeps it as an
  artifact for two weeks.
- **Guard-railed.** No permission bypass — a scoped allowlist plus
  `acceptEdits`. Pushes only through `git-push.sh`: origin only, no flags,
  and the default branch accepts nothing outside `plans/`.

## Install (three files, three secrets)

1. Copy the files from [`templates/`](templates/) into your repo's
   `.github/workflows/`, and adjust `runner`, `setup`, `verify_tools`, and
   `ci_workflow` to your repo's own CI.
2. Add secrets:
   - `CLAUDE_CODE_OAUTH_TOKEN` — run `claude setup-token` locally.
   - `CODEX_AUTH_JSON` — run `codex login` locally, save `~/.codex/auth.json`.
   - `FACTORY_PAT` (optional but recommended) — a machine account's
     fine-grained PAT (this repo; Contents + Pull requests read/write; the
     account a collaborator with write access). With it, factory PRs run
     workflows without approval clicks and reviews carry real
     Request-changes/Approve states. Without it, everything still works:
     bot-authored PRs, one approval click each, comment-style reviews.
3. In repo Settings → Actions → General, allow GitHub Actions to create and
   approve pull requests.

No scripts or skills are copied into your repo: every job checks this
repository out at `.factory/` and uses the canonical copies, so updates
here reach every caller on its next run. Pin `@main` to a tag if you'd
rather update deliberately.

## Use

- **Board flow:** flip a plan to `ready` on the default branch, push.
- **Branch flow:** push a branch carrying a plan flipped to `ready`.
- **From an issue:** comment `/factory implement` (optionally
  `/factory implement opus high`) — the run writes the issue into a plan
  file, implements it, and opens a PR that closes the issue.
- **Review any PR:** comment `/factory review` — verdict posts to the PR;
  on-demand reviews never auto-merge.

Comment commands only count from users with write access: a comment is a
spend button.

## The conventions

The plan lifecycle, feature folders, and routing keys are defined in
[`skills/plans/SKILL.md`](skills/plans/SKILL.md); how a run turns a plan
into a PR is [`skills/pr/SKILL.md`](skills/pr/SKILL.md). The dispatched
agent reads these from `.factory/` at run time — they are the contract, and
prose is the interface.

## Honest costs

Every dispatch is a paid agent run — the flip (or comment) is the spend
button, and concurrent matrix jobs share the subscription's usage limits
with your interactive sessions. The merge gate is advisory, not
adversarial: a wrong `CLEAN` merges, so oversight means reading what
merged. And merges performed by the workflow don't retrigger workflows on
the base branch (GitHub's recursion guard) — CI ran on the PR, not on the
merge commit.
