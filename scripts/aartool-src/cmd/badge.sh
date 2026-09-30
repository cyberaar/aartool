# ── badge ────────────────────────────────────────────────────────────────────
# A self-contained SVG for a README or a wiki, no third-party service involved.
# Generated from the audit's score, so the number on the badge is one you can
# reproduce with `aartool inspect`.

_badge_usage() {
  cat <<'EOF'
aartool badge: an SVG hardening badge from an audit

Usage:
  aartool badge [REPORT.json] [--out FILE.svg] [--label TEXT]

Writes ./aartool-badge.svg by default and prints the Markdown to embed it.
EOF
}

# The backslashes before & are required, not stylistic. Bash 5.2 added
# patsub_replacement, on by default, which makes an unescaped & in the
# replacement expand to the matched text exactly as sed does. Without them
# "${s//</&lt;}" yields "<lt;" and the function silently stops escaping. The
# baseline has the same helper in src/lib/core.sh with the same comment; that
# one is not bundled into aartool, which is how this came back.
#
# Quotes matter here as much as angle brackets: the label lands inside a
# double-quoted XML attribute, so a label containing one closes the attribute
# and everything after it becomes markup. A label of  x" onload="alert(1)
# produced a VALID svg carrying an onload handler, which is worse than a broken
# one because nothing downstream complains.
_badge_xml_escape() {
  local s="$1"
  s="${s//&/\&amp;}"
  s="${s//</\&lt;}"
  s="${s//>/\&gt;}"
  s="${s//\"/\&quot;}"
  s="${s//\'/\&#39;}"
  printf '%s' "$s"
}

cmd_badge() {
  local report="" out="aartool-badge.svg" label="hardening"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) _badge_usage; return 0 ;;
      --out)     out="${2:-}"; [[ -n "$out" ]] || die "--out needs a file."; shift 2 ;;
      --label)   label="${2:-}"; [[ -n "$label" ]] || die "--label needs text."; shift 2 ;;
      -*)        die "Unknown option for badge: $1. Try 'aartool badge --help'." ;;
      *)         report="$1"; shift ;;
    esac
  done
  report="$(report_resolve "$report")"
  local score; score=$(grep -oP '"score":\s*\K[0-9]+' "$report" | head -1 || true)
  [[ -n "$score" ]] || die "No score in $report."
  # The label is user text going into XML, in both element content and a
  # double-quoted attribute. Escape once, for both positions.
  local lab_len=${#label}
  label="$(_badge_xml_escape "$label")"

  local color="#e05d44"
  (( score >= 50 )) && color="#dfb317"
  (( score >= 75 )) && color="#97ca00"
  (( score >= 90 )) && color="#4c1"
  local val="${score}/100"
  # Width comes from the length BEFORE escaping: "&" is one glyph on screen
  # but five characters once it is &amp;, and sizing on the escaped string
  # stretches the badge to fit markup nobody sees.
  local lw=$(( lab_len * 7 + 12 )) vw=$(( ${#val} * 7 + 12 ))
  local w=$((lw + vw))
  cat > "$out" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="20" role="img" aria-label="$label: $val">
  <title>$label: $val</title>
  <linearGradient id="s" x2="0" y2="100%"><stop offset="0" stop-color="#bbb" stop-opacity=".1"/><stop offset="1" stop-opacity=".1"/></linearGradient>
  <clipPath id="r"><rect width="$w" height="20" rx="3" fill="#fff"/></clipPath>
  <g clip-path="url(#r)"><rect width="$lw" height="20" fill="#555"/><rect x="$lw" width="$vw" height="20" fill="$color"/><rect width="$w" height="20" fill="url(#s)"/></g>
  <g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" font-size="11">
    <text x="$((lw/2))" y="14">$label</text><text x="$((lw + vw/2))" y="14">$val</text>
  </g>
</svg>
SVG
  success "Wrote $out  (score $score)"
  printf '  Embed:  ![%s](%s)\n' "$label" "$out"
}
