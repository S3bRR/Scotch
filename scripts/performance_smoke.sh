#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT="$ROOT_DIR/Docs/performance_smoke_report.md"

cd "$ROOT_DIR"

measure_ms() {
  local start end
  start=$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)
  "$@" >/dev/null 2>&1 || true
  end=$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)
  echo $((end - start))
}

build_ms=$(measure_ms swift build --product ScotchCmd)
list_ms=$(measure_ms swift run ScotchCmd list)
help_ms=$(measure_ms swift run ScotchCmd help)

echo "# Performance Smoke Report" > "$REPORT"
echo "" >> "$REPORT"
echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$REPORT"
echo "" >> "$REPORT"
echo "| Check | Duration (ms) |" >> "$REPORT"
echo "|---|---:|" >> "$REPORT"
echo "| Build ScotchCmd | $build_ms |" >> "$REPORT"
echo "| ScotchCmd list | $list_ms |" >> "$REPORT"
echo "| ScotchCmd help | $help_ms |" >> "$REPORT"

echo "Wrote $REPORT"
