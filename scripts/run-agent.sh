#!/usr/bin/env bash
# The factory's provider shim: one interface, three coding agents. Every
# workflow step that used to hard-code `claude` or `codex` goes through
# here instead, so each workflow (implement, revise, review) can pick its
# agent independently via the AGENT env var:
#
#   AGENT=claude   Claude Code        (Anthropic; CLAUDE_CODE_OAUTH_TOKEN)
#   AGENT=codex    Codex CLI          (OpenAI; OPENAI_API_KEY or CODEX_AUTH_JSON)
#   AGENT=muse     Muse Code          (Meta; MUSE_API_KEY -> META_API_KEY)
#
# Commands:
#   run-agent.sh install   install the CLI and set up its auth
#   run-agent.sh run       implement-style run: PROMPT, MODEL, EFFORT,
#                          MAX_TURNS, TRANSCRIPT, FACTORY_DIR, ALLOWED_TOOLS
#   run-agent.sh review    review-style run: PROMPT, MODEL, EFFORT, OUT —
#                          the agent's final message (pure JSON) lands in OUT
#
# MODEL may be empty: each agent has a sensible default. EFFORT uses the
# factory's scale (low|medium|high|xhigh|max) and is mapped per provider.
#
# Honest note on guard rails: only Claude Code has a tool allowlist, so only
# there is the git-push.sh-only rule *enforced*. Codex and Muse run with
# their sandboxes off (the runner VM is the sandbox — it is ephemeral and
# discarded), so for them the push rule is prompt-level, backed by the
# push wrapper refusing bad pushes when it is used.
set -euo pipefail

AGENT="${AGENT:-claude}"
cmd="${1:?usage: run-agent.sh install|run|review}"

default_model() {
  case "$AGENT" in
    claude) echo "opus" ;;
    codex)  echo "gpt-5.6-luna" ;;
    muse)   echo "muse-spark-1.2" ;;
  esac
}

# Factory effort scale -> provider scale. Claude takes it verbatim; Codex
# tops out at xhigh; Muse calls its top tier "ultra".
codex_effort() { case "$1" in max) echo xhigh ;; *) echo "$1" ;; esac; }
muse_effort()  { case "$1" in max) echo ultra ;; *) echo "$1" ;; esac; }

require_env() {
  eval "v=\${$1:-}"
  [ -n "$v" ] || { echo "::error::$2"; exit 1; }
}

codex_auth() {
  mkdir -p ~/.codex
  if [ -n "${OPENAI_API_KEY:-}" ]; then
    printf '{"OPENAI_API_KEY": "%s"}' "$OPENAI_API_KEY" > ~/.codex/auth.json
  elif [ -n "${CODEX_AUTH_JSON:-}" ]; then
    printf '%s' "$CODEX_AUTH_JSON" > ~/.codex/auth.json
  else
    echo "::error::Set OPENAI_API_KEY (preferred) or CODEX_AUTH_JSON so Codex can sign in."
    exit 1
  fi
}

codex_ensure_platform_package() {
  # @openai/codex ships its binary in a per-platform optionalDependency
  # (e.g. @openai/codex-linux-x64). npm silently skips an optional dep it
  # cannot fetch — registry propagation lag right after a release, a flaky
  # mirror — and the launcher then dies with "Missing optional dependency".
  # Verify, and if the binary is absent install the platform package
  # explicitly at the exact version of the launcher we just installed.
  if codex --version >/dev/null 2>&1; then return 0; fi
  local version arch pkg
  version=$(npm ls -g @openai/codex --json 2>/dev/null | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).dependencies["@openai/codex"].version')
  case "$(uname -m)" in
    x86_64|amd64) arch=x64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) echo "::error::Unsupported architecture $(uname -m) for Codex."; exit 1 ;;
  esac
  case "$(uname -s)" in
    Linux)  pkg="@openai/codex-linux-$arch" ;;
    Darwin) pkg="@openai/codex-darwin-$arch" ;;
    *) echo "::error::Unsupported OS $(uname -s) for Codex."; exit 1 ;;
  esac
  echo "::warning::$pkg was not installed alongside @openai/codex@$version; installing it explicitly."
  npm install -g "$pkg@npm:@openai/codex@${version}-${pkg#@openai/codex-}"
  codex --version >/dev/null || { echo "::error::Codex still cannot find its binary after installing $pkg."; exit 1; }
}

muse_auth() {
  require_env MUSE_API_KEY "Set the MUSE_API_KEY secret (a Meta Model API key) so Muse can sign in."
  # The docs have shipped both names; export both so either CLI build works.
  export META_API_KEY="$MUSE_API_KEY"
  export MODEL_API_KEY="$MUSE_API_KEY"
}

muse_path() {
  # install.sh drops a static binary under the home dir; surface it for this
  # process and (in Actions) for later steps.
  for d in "$HOME/.local/bin" "$HOME/.muse/bin"; do
    if [ -d "$d" ]; then
      PATH="$d:$PATH"
      [ -n "${GITHUB_PATH:-}" ] && echo "$d" >> "$GITHUB_PATH"
    fi
  done
}

case "$cmd" in
  install)
    case "$AGENT" in
      claude) npm install -g @anthropic-ai/claude-code ;;
      codex)
        npm install -g @openai/codex@latest
        codex_ensure_platform_package
        ;;
      muse)
        curl -fsSL https://dev.meta.ai/install.sh | bash
        muse_path
        command -v muse >/dev/null || { echo "::error::muse installed but is not on PATH."; exit 1; }
        ;;
      *) echo "::error::Unknown AGENT '$AGENT' (expected claude, codex or muse)."; exit 1 ;;
    esac
    ;;

  run)
    MODEL="${MODEL:-$(default_model)}"
    EFFORT="${EFFORT:-medium}"
    MAX_TURNS="${MAX_TURNS:-250}"
    TRANSCRIPT="${TRANSCRIPT:?TRANSCRIPT path required}"
    set -o pipefail
    case "$AGENT" in
      claude)
        require_env CLAUDE_CODE_OAUTH_TOKEN "Set the CLAUDE_CODE_OAUTH_TOKEN secret (from \`claude setup-token\`) to run the claude agent."
        claude -p "$PROMPT" \
          --model "$MODEL" \
          --effort "$EFFORT" \
          --output-format stream-json --verbose \
          --max-turns "$MAX_TURNS" \
          --permission-mode acceptEdits \
          --allowedTools "$ALLOWED_TOOLS" \
          --disallowedTools "WebSearch,WebFetch" \
          | tee "$TRANSCRIPT" \
          | node "${FACTORY_DIR:-.factory}/scripts/render-stream.mjs"
        ;;
      codex)
        codex_auth
        codex exec \
          --model "$MODEL" \
          -c model_reasoning_effort="$(codex_effort "$EFFORT")" \
          --sandbox danger-full-access \
          "$PROMPT" | tee "$TRANSCRIPT"
        ;;
      muse)
        muse_auth; muse_path
        muse exec --yolo \
          --model "$MODEL" \
          --reasoning-effort "$(muse_effort "$EFFORT")" \
          --max-model-steps "$MAX_TURNS" \
          --json \
          "$PROMPT" | tee "$TRANSCRIPT"
        ;;
      *) echo "::error::Unknown AGENT '$AGENT'."; exit 1 ;;
    esac
    ;;

  review)
    MODEL="${MODEL:-$(default_model)}"
    OUT="${OUT:?OUT path required}"
    set -o pipefail
    case "$AGENT" in
      claude)
        require_env CLAUDE_CODE_OAUTH_TOKEN "Set the CLAUDE_CODE_OAUTH_TOKEN secret to run the claude reviewer."
        # -p prints the final message to stdout; the prompt makes that pure
        # JSON. Read-only tools: a reviewer changes nothing.
        claude -p "$PROMPT" \
          --model "$MODEL" \
          ${EFFORT:+--effort "$EFFORT"} \
          --max-turns "${MAX_TURNS:-150}" \
          --allowedTools "Glob,Grep,LS,Read,Bash(git diff:*),Bash(git log:*),Bash(git show:*),Bash(git status:*),Bash(cat:*)" \
          --disallowedTools "WebSearch,WebFetch" \
          > "$OUT"
        ;;
      codex)
        codex_auth
        codex exec \
          --model "$MODEL" \
          ${EFFORT:+-c model_reasoning_effort="$(codex_effort "$EFFORT")"} \
          --sandbox danger-full-access \
          --output-last-message "$OUT" \
          "$PROMPT"
        ;;
      muse)
        muse_auth; muse_path
        # Muse has no --output-last-message; it writes the verdict file
        # itself (it has write access under --yolo) and we verify it did.
        muse exec --yolo \
          --model "$MODEL" \
          ${EFFORT:+--reasoning-effort "$(muse_effort "$EFFORT")"} \
          --max-model-steps "${MAX_TURNS:-150}" \
          "$PROMPT Before finishing, write that exact JSON (and nothing else) to the file $OUT."
        [ -s "$OUT" ] || { echo "::error::Muse finished without writing its verdict to $OUT."; exit 1; }
        ;;
      *) echo "::error::Unknown AGENT '$AGENT'."; exit 1 ;;
    esac
    ;;

  *) echo "::error::Unknown command '$cmd' (install|run|review)."; exit 1 ;;
esac
