---
name: plans
description: Conventions for writing plan files that the Plans app reads — frontmatter, the four-status lifecycle (draft, ready, busy, done), and an agent's part in it. Use when creating or updating markdown files in a plans/ folder, or when asked to flesh out, pick up, or finish a plan.
---

# Writing plans the Plans app can read

The markdown files in `plans/` pass between a human and agents. The human
writes a seed — a problem, an intent, a rough shape. An agent fleshes it out
into something buildable. A session implements it. The Plans app is where the
human reads all of this: it renders each file as a page, shows the frontmatter
as a panel, and colours the `status` key so the tree reads as a board. Your job
when touching these files is to keep that board truthful.

## Frontmatter

Every plan starts with a YAML frontmatter block holding at least a status:

```markdown
---
status: draft
---
# The Plan's Title
```

Rules the app relies on:

- Exactly one frontmatter block, at the very top. Never add a second.
- Keys are simple `key: value` lines. Keep existing keys and their spelling;
  edit values in place.
- `status` is lowercase by convention. The app matches it case-insensitively
  and renders it as written.

Two optional keys route a dispatched implementation run:

```yaml
---
status: ready
model: opus
effort: high
---
```

- `model` and `effort` say which model tier picks the plan up and how long it
  may think. The vocabulary is the agent's own (the values pass straight
  through to the invocation, e.g. `claude -p --model opus`), not this app's.
  The vocabulary belongs to whichever agent dispatches the plan — one
  agent's `opus` is another's `gpt-5.6-sol`. The bundled Claude Code
  dispatchers recognise, ranked lowest to highest, `model: haiku | sonnet |
  opus` and `effort: low | medium | high | xhigh | max`; a value a
  dispatcher does not recognise is treated as absent — it warns and falls
  back to its default rather than failing the run.
- A key that is present is respected; a key that is missing falls back to the
  dispatcher's configured default. No heuristics about what the plan "looks
  like it needs".
- The keys bind a dispatcher, not the lifecycle — in a hand-driven session
  you choose your own model, and that is fine.

## The four statuses

Each status marks a handoff: whose move it is next.

| status | means | next move belongs to |
| ------ | ----- | -------------------- |
| draft  | The human wrote something down. It needs an agent to flesh it out into a real plan. | an agent (flesh it out) |
| ready  | The fleshing out is done. Implementation can start. | a session (implement it) |
| busy   | A session is implementing it right now. | whoever set it (finish) |
| done   | Implemented. The plan is a record now. | the human (archive it) |

Any other status renders neutral in the app — it reads conventions, it does
not own a vocabulary — but these four are the shared language; don't invent
others unless the human does.

## The lifecycle, and your part in it

```
human writes → draft → agent fleshes out → ready → session implements → busy → done
```

- **Fleshing out?** That is what `draft` is asking for. Work the human's seed
  into a plan a session could build from — approach, the files involved,
  what's out of scope — keeping their intent and their words where they
  survive. When it would hold up to being implemented, set `ready`. Fleshing
  out is writing, not building: do not start implementation from a draft.
- **Implementing?** Pick a `ready` plan. Set it to `busy` *before* you start —
  it is a claim, how the human and other sessions know the file is being
  worked. One `busy` plan per session. If you stop before finishing, say so in
  the plan and leave it `busy` so the claim is visible, or set it back to
  `ready` if you did not really begin.
- **Stuck?** There is no blocked status. Write what you are waiting on into
  the plan itself, loudly, at the top — a reader should not have to diff to
  find out why nothing is moving.
- **Finished?** Set `done`. Moving the file to `plans/completed/` is the
  human's call unless they've asked.
- **Never demote a status you didn't set.** A `busy` plan that isn't yours is
  someone else's session, mid-flight. Leave it alone.

## Feature folders

Related plans that describe one feature can live in a folder named for it:
`plans/feature-name/*.md`. The folder means the plans were split for
readability but describe **one unit of work** — one implementation run, one
branch, one PR — and its plans share fate. When a run needs one `model` or
`effort` for the whole folder, the highest requested value in the folder
wins, because the unit was priced by its hardest member. The only other
folders with meaning are `completed/` (archived plans) and `drafts/`.

## Editing etiquette

The app's buffer is the file on disk and it watches for outside writes, so
plain writes are safe — but keep them whole: write the full file, don't leave
partial frontmatter or a truncated document on disk between steps.
