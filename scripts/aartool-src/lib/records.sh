# ── Reading an audit report without jq ───────────────────────────────────────
# Shared by paths, badge and demo. advise carries its own copy of this parse for
# historical reasons; the format is the same one it documents.

# Print "ID|STATUS|CHECK" for every result in a report.
report_records() {
  local report="$1" recs
  recs=$(tr -d '\n' < "$report" \
    | grep -oP '"results":\s*\[\K.*?(?=\]\s*,\s*"ansible_remediation")' \
    | sed 's/},{/}\n{/g') || true
  [[ -n "$recs" ]] || return 1
  local rec id st ck
  while IFS= read -r rec; do
    [[ -n "$rec" ]] || continue
    id=$(grep -oP '"id":"\K[^"]*'     <<<"$rec" || true)
    st=$(grep -oP '"status":"\K[^"]*' <<<"$rec" || true)
    ck=$(grep -oP '"check":"\K[^"]*'  <<<"$rec" || true)
    printf '%s|%s|%s\n' "$id" "$st" "$ck"
  done <<<"$recs"
}

# Newest report aartool inspect wrote, from the same pool advise searches.
report_newest() {
  local f
  f=$(find . ./reports /var/log/cyberaar -maxdepth 1 \( -name 'aartool-*.json' -o -name 'cyberaar-*.json' \) -type f -print0 2>/dev/null \
      | xargs -0 -r ls -t 2>/dev/null | head -1) || true
  [[ -n "$f" ]] && printf '%s' "$f"
  return 0
}

# Resolve an optional report argument to a readable, plausible report path.
report_resolve() {
  local report="${1:-}"
  if [[ -z "$report" ]]; then
    report="$(report_newest)"
    [[ -n "$report" ]] || die "No audit report given, and none found in ., ./reports or /var/log/cyberaar.
        Produce one first:   sudo aartool inspect
        Or see it work first: aartool demo"
    info "Using the most recent report found: $report" >&2
  fi
  [[ -f "$report" ]] || die "No such report: $report"
  grep -qE '"(aartool|cyberaar_baseline)"' "$report" \
    || die "$report does not look like an aartool audit report (it must be the JSON, not the HTML)."
  printf '%s' "$report"
}
