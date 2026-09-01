#!/usr/bin/env node
// Renders Claude Code's stream-json output as a readable conversation log.
// Pipe the stream through here after tee-ing the raw JSONL — the artifact
// keeps every byte; this is only for humans reading the Actions log.
import readline from "node:readline";

const rl = readline.createInterface({ input: process.stdin, terminal: false });
const out = (s) => process.stdout.write(s + "\n");
const trunc = (s, n) => (s.length > n ? s.slice(0, n) + ` … [${s.length - n} more chars]` : s);

rl.on("line", (raw) => {
  let ev;
  try {
    ev = JSON.parse(raw);
  } catch {
    return; // non-JSON noise; the artifact still has it
  }

  if (ev.type === "system" && ev.subtype === "init") {
    out(`━━ session ${ev.session_id ?? "?"} · model ${ev.model ?? "?"} ━━`);
  } else if (ev.type === "assistant") {
    for (const block of ev.message?.content ?? []) {
      if (block.type === "thinking" && block.thinking) {
        out(`\n· thinking ·\n${block.thinking}`);
      } else if (block.type === "text" && block.text) {
        out(`\n${block.text}`);
      } else if (block.type === "tool_use") {
        out(`\n▶ ${block.name} ${trunc(JSON.stringify(block.input ?? {}), 300)}`);
      }
    }
  } else if (ev.type === "user") {
    for (const block of ev.message?.content ?? []) {
      if (block.type !== "tool_result") continue;
      const text =
        typeof block.content === "string"
          ? block.content
          : (block.content ?? []).map((p) => p.text ?? "").join("\n");
      if (text.trim()) out(`  ↳ ${trunc(text.trim(), 500).replace(/\n/g, "\n    ")}`);
    }
  } else if (ev.type === "result") {
    const cost = typeof ev.total_cost_usd === "number" ? ` · $${ev.total_cost_usd.toFixed(4)}` : "";
    out(`\n━━ ${ev.subtype ?? "result"} · ${ev.num_turns ?? "?"} turns${cost} ━━`);
    if (typeof ev.result === "string" && ev.result) out(ev.result);
  }
});
