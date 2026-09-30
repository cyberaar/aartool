#!/usr/bin/env bash
# =============================================================================
#  aartool — Build Script
#  Concatenates aartool-src/ files in order to produce scripts/aartool.
#
#  Usage: bash scripts/build-aartool.sh
#  Output: scripts/aartool (do not edit directly)
#
#  Mirrors scripts/build.sh, which builds aartool-baseline.sh the same way.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${SCRIPT_DIR}/aartool"

# Order matters: the shebang must come first and run.sh, which calls main, last.
PARTS=(
  aartool-src/main.sh
  aartool-src/lib/paths.sh
  aartool-src/lib/surface.sh
  aartool-src/lib/kb.sh
  aartool-src/lib/records.sh
  aartool-src/cmd/inspect.sh
  aartool-src/cmd/harden.sh
  aartool-src/cmd/surface.sh
  aartool-src/cmd/advise.sh
  aartool-src/cmd/explain.sh
  aartool-src/cmd/doctor.sh
  aartool-src/cmd/report.sh
  aartool-src/cmd/diff.sh
  aartool-src/cmd/paths.sh
  aartool-src/cmd/badge.sh
  aartool-src/cmd/demo.sh
  aartool-src/cmd/install.sh
  aartool-src/run.sh
)

cat "${SCRIPT_DIR}/${PARTS[0]}" > "$OUT"
for f in "${PARTS[@]:1}"; do
  printf '\n' >> "$OUT"
  cat "${SCRIPT_DIR}/${f}" >> "$OUT"
done
chmod +x "$OUT"

if bash -n "$OUT"; then
  printf "✅  Bundle OK: %s (%d lines)\n" "$OUT" "$(wc -l < "$OUT")"
else
  printf "❌  Syntax error in bundle — check aartool-src/\n"
  exit 1
fi
