#!/usr/bin/env bash
# Records the README loop: aartool paths on the bundled sample, then explain on
# the link it names. Produces docs/media/aartool-paths.cast, which
# docs/MEDIA.md turns into the GIF.
#
# The recording must be regenerated after any change to the paths or explain
# output. It is the first thing on the README and nobody re-checks it, the same
# reasoning that governs the help image.
#
# Needs: asciinema. Nothing else, and no root.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:-$REPO/docs/media/aartool-paths.cast}"

command -v asciinema >/dev/null || { echo "asciinema is not installed" >&2; exit 1; }

# A scratch directory holding only the sample, so the command reads
# 'aartool paths demo-audit.json' and the provenance line the view prints
# carries no home directory, user name or host name.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$REPO/dashboard/demo-audit.json" "$STAGE/demo-audit.json"

# The repo build, first on PATH, so the text typed on screen is exactly the
# command that runs. An installed aartool would otherwise shadow it and the
# recording would show a different version's output.
cat > "$STAGE/drive.sh" <<'DRIVE'
#!/usr/bin/env bash
type_out() {
  local s="$1" i
  for ((i = 0; i < ${#s}; i++)); do printf '%s' "${s:i:1}"; sleep 0.045; done
  printf '\n'
}
sleep 1.2
printf '$ '; type_out 'aartool paths demo-audit.json'
aartool paths demo-audit.json || true
sleep 8
printf '\n$ '; type_out 'aartool explain KRN-06'
aartool explain KRN-06 || true
# No trailing sleep: a cast records events, not silence, so idle after the last
# byte of output is lost. The closing hold comes from agg's
# --last-frame-duration instead. See docs/MEDIA.md.
DRIVE
chmod +x "$STAGE/drive.sh"

cd "$STAGE"
PATH="$REPO/scripts:$PATH" asciinema rec --overwrite -q \
  --cols 100 --rows 34 \
  -c "$STAGE/drive.sh" "$OUT"

# agg reads the colours out of the cast header, so the palette travels with the
# recording rather than living in a command line somebody has to remember. The
# values are the dashboard's, from dashboard/index.html :root.
python3 - "$OUT" <<'PY'
import json, sys
p = sys.argv[1]
lines = open(p).read().splitlines()
hdr = json.loads(lines[0])
hdr["theme"] = {
    "fg": "#e2e8f0",
    "bg": "#080d1a",
    # black, red, green, yellow, blue, magenta, cyan, white, then the brights.
    "palette": ":".join([
        "#0d1526", "#ef4444", "#00e5b0", "#f59e0b",
        "#3b82f6", "#a78bfa", "#7dd3fc", "#e2e8f0",
        "#94a3b8", "#f87171", "#34ffd0", "#fbbf24",
        "#60a5fa", "#c4b5fd", "#a5e9ff", "#ffffff",
    ]),
}
lines[0] = json.dumps(hdr)
open(p, "w").write("\n".join(lines) + "\n")
PY

printf 'wrote %s\n' "$OUT"
