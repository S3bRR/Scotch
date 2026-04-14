#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

swift test >/dev/null

if rg -n "\| Required \| .*\| Deferred \|" Docs/parity_matrix.md >/dev/null; then
  echo "Release gate failed: parity matrix still has deferred required rows."
  exit 1
fi

if rg -n --pcre2 "^- \\[( |~)\\] (?!Not started$|In progress$)" Docs/implementation_plan_execution.md >/dev/null; then
  echo "Release gate failed: implementation tracker still has open/in-progress rows."
  exit 1
fi

echo "Release gate passed."
