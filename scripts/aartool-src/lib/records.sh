# ── Reading an audit report without jq ───────────────────────────────────────
# Shared by paths, badge and demo. advise carries its own copy of this parse for
# historical reasons; the format is the same one it documents.

# Print "ID|STATUS|CHECK" for every result in a report.
report_records() {
  local report="$1" recs
  # The split tolerates whitespace between records. It used to be a literal
  # '},{', which only matches what aartool-baseline.sh happens to emit: a
  # report that had been through jq, or any other JSON tool, came back as ONE
  # record whose "id" grep returned every id at once. paths then asked bash for
  # ST["<many lines>"] and got 'bad array subscript', printed nothing, and
  # exited 0. Exit 0 is documented as "no complete attack chain", so a CI gate
  # went green on a report the tool had failed to read.
  recs=$(tr -d '\n' < "$report" \
    | grep -oP '"results":\s*\[\K.*?(?=\]\s*,\s*"ansible_remediation")' \
    | sed 's/}[[:space:]]*,[[:space:]]*{/}\n{/g') || true
  [[ -n "$recs" ]] || return 1
  local rec id st ck n=0
  while IFS= read -r rec; do
    [[ -n "$rec" ]] || continue
    id=$(grep -oP '"id":\s*"\K[^"]*'     <<<"$rec" | head -1 || true)
    st=$(grep -oP '"status":\s*"\K[^"]*' <<<"$rec" | head -1 || true)
    ck=$(grep -oP '"check":\s*"\K[^"]*'  <<<"$rec" | head -1 || true)
    # A record with no id is not a record. Emitting it puts an empty key into
    # the caller's associative array, which is a fatal bash error, and dropping
    # it silently would under-report. Refuse the whole parse instead.
    [[ -n "$id" ]] || return 1
    n=$((n+1))
    printf '%s|%s|%s\n' "$id" "$st" "$ck"
  done <<<"$recs"
  # One record out of a real audit means the split did not split. Better to say
  # so than to report on a single finding as if it were the whole machine.
  [[ $n -ge 2 ]] || return 1
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
