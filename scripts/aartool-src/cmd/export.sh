# ── export ───────────────────────────────────────────────────────────────────
# The audit in the formats other tools already read: SARIF, which GitHub code
# scanning and most CI security tabs ingest, and the Prometheus text format,
# which node_exporter's textfile collector scrapes.
#
# Parsed with python3's json module rather than grep. The report is
# attacker-influenced text (a hostname, a config value in a detail string), and
# hand-rolled JSON output is how a quote in a hostname becomes a broken upload.
# An unreadable or empty report is an error, never an empty export: a SARIF file
# with zero results reads as "clean", which is the comforting answer.

_export_usage() {
  cat <<'EOF'
aartool export: an audit in SARIF or Prometheus format. Changes nothing.

Usage:
  aartool export [REPORT.json] --format sarif|prometheus [--out FILE]

Options:
  --format FMT   sarif       SARIF 2.1.0, for GitHub code scanning and CI tabs
                 prometheus  text format, for node_exporter's textfile collector
  --out FILE     Write here instead of standard output
  -h, --help     This help

With no REPORT it uses the newest report `inspect` wrote.

Examples:
  aartool export --format sarif --out aartool.sarif
  aartool export --format prometheus --out /var/lib/node_exporter/aartool.prom
EOF
}

cmd_export() {
  local report="" fmt="" out=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) _export_usage; return 0 ;;
      --format)  fmt="${2:-}"; [[ -n "$fmt" ]] || die "--format needs sarif or prometheus."; shift 2 ;;
      --out)     out="${2:-}"; [[ -n "$out" ]] || die "--out needs a file."; shift 2 ;;
      -*)        die "Unknown option for export: $1. Try 'aartool export --help'." ;;
      *)         report="$1"; shift ;;
    esac
  done
  case "$fmt" in
    sarif|prometheus) ;;
    "") die "export needs --format sarif or --format prometheus." ;;
    *)  die "Unknown format: $fmt. Use sarif or prometheus." ;;
  esac
  command -v python3 >/dev/null 2>&1 \
    || die "export needs python3 to parse the report. It is present on any machine that can run Ansible."
  report="$(report_resolve "$report")"

  local tmp; tmp="$(mktemp)"
  if ! python3 - "$report" "$fmt" "$AARTOOL_VERSION" >"$tmp" <<'PY'
import json, sys

path, fmt, tool_version = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path, encoding="utf-8") as fh:
        doc = json.load(fh)
except (OSError, json.JSONDecodeError) as e:
    sys.stderr.write(f"[ERROR] Cannot read {path}: {e}\n"); sys.exit(2)

rep = doc.get("aartool") or doc.get("cyberaar_baseline")
results = rep.get("results") if isinstance(rep, dict) else None
if not isinstance(results, list) or not results:
    sys.stderr.write(f"[ERROR] {path} has no results to export. Refusing to write an export that reads as clean.\n")
    sys.exit(2)
for r in results:
    if not isinstance(r, dict) or r.get("status") not in ("PASS", "WARN", "FAIL") or not r.get("id"):
        sys.stderr.write(f"[ERROR] {path} has a result with no id or an unknown status: {r!r}\n"); sys.exit(2)

host = str(rep.get("host") or "unknown")

if fmt == "sarif":
    open_ = [r for r in results if r["status"] in ("WARN", "FAIL")]
    rules, seen = [], set()
    for r in results:
        if r["id"] in seen:
            continue
        seen.add(r["id"])
        rules.append({
            "id": r["id"],
            "name": r["id"].replace("-", ""),
            "shortDescription": {"text": str(r.get("check", r["id"]))},
            "helpUri": "https://github.com/cyberaar/aartool",
            "help": {"text": f"Run: aartool explain {r['id']}"},
        })
    sarif = {
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        "version": "2.1.0",
        "runs": [{
            "tool": {"driver": {
                "name": "aartool",
                "version": tool_version,
                "informationUri": "https://github.com/cyberaar/aartool",
                "rules": rules,
            }},
            "results": [{
                "ruleId": r["id"],
                "level": "error" if r["status"] == "FAIL" else "warning",
                "message": {"text": f"{r.get('check', r['id'])}: {r.get('detail', '')}".rstrip(": ")},
                "locations": [{
                    "physicalLocation": {"artifactLocation": {"uri": path.replace("\\", "/")}},
                    "logicalLocations": [{"name": host, "kind": "host"}],
                }],
            } for r in open_],
            "properties": {"host": host, "score": rep.get("score"), "checks": len(results)},
        }],
    }
    json.dump(sarif, sys.stdout, indent=2); sys.stdout.write("\n")
else:
    def esc(v):
        return str(v).replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')
    out = []
    out.append("# HELP aartool_score Hardening score, 0 to 100.")
    out.append("# TYPE aartool_score gauge")
    out.append(f'aartool_score{{host="{esc(host)}"}} {rep.get("score", 0)}')
    out.append("# HELP aartool_checks Number of checks by status.")
    out.append("# TYPE aartool_checks gauge")
    for st in ("PASS", "WARN", "FAIL"):
        n = sum(1 for r in results if r["status"] == st)
        out.append(f'aartool_checks{{host="{esc(host)}",status="{st.lower()}"}} {n}')
    out.append("# HELP aartool_check_open 1 for every check that is currently WARN or FAIL.")
    out.append("# TYPE aartool_check_open gauge")
    for r in results:
        if r["status"] in ("WARN", "FAIL"):
            out.append(f'aartool_check_open{{host="{esc(host)}",id="{esc(r["id"])}",status="{r["status"].lower()}"}} 1')
    sys.stdout.write("\n".join(out) + "\n")
PY
  then
    rm -f "$tmp"
    die "export failed; nothing was written."
  fi

  if [[ -n "$out" ]]; then
    mv "$tmp" "$out"
    success "Wrote $out ($fmt)"
  else
    cat "$tmp"; rm -f "$tmp"
  fi
}
