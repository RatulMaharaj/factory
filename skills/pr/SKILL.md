---
name: pr
description: How an agent turns a ready plan into a pull request — pick one unit of work, claim it with a pushed busy flip, build in a worktree from the default branch's tip, open a PR, and fail loudly back to ready. Use when asked to pick up, implement, or work a ready plan in a repository with a plans/ folder.
---
# Turning a plan into a PR

The plans skill teaches an agent to *write* the board; this one teaches an
agent to *work* it. A run of this skill starts from a `ready` plan and ends in
exactly one of two states: a pull request into the default branch that
implements the plan, or the plan back on the board marked `ready` with a note
saying why not. Nothing in between — no half-done PRs, no silent stalls.

## Pick one unit of work

A unit is either **one `ready` plan** or **one feature folder** — a folder of
related plans named after a feature (`plans/feature-name/*.md`), taken
together, because plans that were split for readability still describe one
change and one PR. A feature folder is always one run: its plans share fate.

Never two units in one run. A run maps to a branch maps to a PR, and a PR
that implements two unrelated plans is unreviewable.

If a dispatcher handed you a specific plan or folder, that is the unit. If
you are picking for yourself, pick one `ready` unit from the default branch's
plans folder and stop there.

## Claim it first — and push the claim

When the unit lives on its own branch, the branch is the claim: flip the
plan to `busy` in your first commit *on that branch* and push it there —
nothing touches the default branch. The rest of this section is for units
picked from the default branch.

The very first act of the run, before any implementation:

1. Flip the unit's status to `busy` — every plan in a feature folder.
2. Commit that flip and nothing else. The commit is the claim, and it must
   stay auditable as exactly that: one frontmatter change, no other edits.
3. Push it to the default branch.

Pushed, the claim is the mutual-exclusion lock between workers, and git's own
push rejection is the arbiter: a non-fast-forward on the claim means another
worker won the race. Do not force, do not retry — pick a different unit or
stop.

Read the rejection before concluding. A *policy* rejection — branch
protection requiring pull requests — is not a lost race: no other worker won
anything, the branch just refuses direct pushes. In that case continue the
run **without** the pushed claim, relying on your dispatcher's own mutual
exclusion (a dispatched run is one run per flip), and say in the PR body
that the unit ran unclaimed so a human reading the board knows why the plan
never showed `busy`.

This is the one deliberate exception to "never push to the default branch."
Nothing else in the run touches it.

## Where the work happens: the plan's branch, or a worktree

Two modes, decided by where the unit's `ready` flip lives:

- **The plan is on its own branch** (not the default branch): that branch is
  the workbench. Implement directly on it — the plan travels with its code,
  the branch's existence is the claim, and no flip is pushed anywhere else.
  The PR at the end goes from this branch into the default branch: one
  branch, one PR, per feature.
- **The plan is on the default branch**: you cannot commit to the base, so
  `git worktree add` from the *latest commit of the default branch*, on a
  fresh branch named `impl/<plan-name>` (or `impl/<folder-name>` for a
  feature folder) — the prefix is load-bearing: automated review and merge
  key on it. The worktree keeps the human's checkout clean, parallel units
  apart, and a failed run discardable by deleting a directory.

## Finish into a PR

- **Verify** with the smallest relevant check the repository offers — its
  test command, its lint, its build; whatever CI would run first. If the
  repository has no checks at all, verify by exercising the change directly
  and say in the PR body what you did.
- Set the unit's status to `done` — this flip travels in the branch, not the
  default branch.
- Push the branch and open a PR into the default branch with `gh pr create`.
  The PR body links the plan file(s) it implements.
- **Never merge.** The PR is the human's review boundary. And never push to
  the default branch beyond the claim flip above.

## Fail loudly, not creatively

A plan that turns out underspecified, contradictory, or blocked goes back to
`ready` with a note at the top of the plan saying what was missing — the
plans skill's "no blocked status, write it in the file" rule, applied from
the implementation side. Commit and push that flip to the default branch
(releasing the claim), delete the worktree, and do not open a PR. A half-done
PR is worse than no PR.

Never ask questions mid-run. If the run cannot proceed without an answer,
that is a fail-loudly: write the question into the plan and put it back to
`ready`.
