#!/bin/sh
# The only way a worker-dispatched agent may push.
#
# Modeled on anthropics/claude-code-action's scripts/git-push.sh (see
# plans/claude-code-action-findings.md): `Bash(git push:*)` in an allowlist is
# an RCE grant via --receive-pack, so the allowlist grants this wrapper
# instead. Exactly two arguments, no flags, remote pinned to origin — and one
# rule of ours on top: a push to the default branch may only contain changes
# under plans/, which mechanically covers the two sanctioned cases (the busy
# claim flip and a fleshed-out draft) and nothing else.
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: git-push.sh origin <branch>" >&2
  exit 1
fi

remote="$1"
ref="$2"

if [ "$remote" != "origin" ]; then
  echo "git-push.sh: remote must be origin, got '$remote'" >&2
  exit 1
fi

case "$ref" in
  -*|*..*|*//*|*[!A-Za-z0-9._/-]*|"")
    echo "git-push.sh: invalid ref '$ref'" >&2
    exit 1
    ;;
esac

default_ref="$(git symbolic-ref --quiet refs/remotes/origin/HEAD || true)"
default_branch="${default_ref#refs/remotes/origin/}"

if [ -n "$default_branch" ] && [ "$ref" = "$default_branch" ]; then
  bad="$(git diff --name-only "origin/$default_branch...HEAD" | grep -v '^plans/.*\.md$' || true)"
  if [ -n "$bad" ]; then
    echo "git-push.sh: refusing to push non-plans changes to $default_branch:" >&2
    echo "$bad" >&2
    exit 1
  fi
fi

exec git push origin "$ref"
