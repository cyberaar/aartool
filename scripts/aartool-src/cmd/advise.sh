# ── advise ───────────────────────────────────────────────────────────────────
# inspect answers "what is wrong". advise answers the question an operator
# actually has, which is "what do I do on Monday morning".
#
# Forty findings in report order is not a plan. It has no ordering, so the
# cheapest item and the one an attacker is using right now look the same; and
# it does not separate the changes you can apply without a conversation from
# the ones that will break a workload. Both omissions have the same result: the
# report gets read once and nothing is applied.
#
# The ordering is by reachability, not by CVSS-style severity, because that is
# what determines what an attacker reaches first:
#
#   1  from the network      no account needed
#   2  account to root       what the next kernel LPE or a stolen key gets
#   3  you would not know    detection and forensics
#   4  hygiene and evidence  everything else
#
# Within a wave: FAIL before WARN, and inside that, changes that are safe to
# apply blind before changes that need a decision. The decision list is printed
# separately, because the fastest way to make someone stop using a hardening
# tool is to have it break their containers on the first run.

# Findings whose fix has a real operational cost. Applying these without
# knowing what the machine runs is how an estate goes down.
_advise_costly() {
  case "$1" in
    KRN-01|KRN-03|KRN-05|KRN-08) return 0 ;;  # containers, io_uring users, modprobe, boot
    SSH-02|SSH-13)               return 0 ;;  # locks out keyless users / old clients
    NET-01)                      return 0 ;;  # firewall default-deny locks you out
    NET-02)                      return 0 ;;  # ip_forward=0 kills container networking
    NET-13)                      return 0 ;;  # disabling IPv6 breaks IPv6-only estates
    FS-06|FS-09)                 return 0 ;;  # noexec /tmp breaks installers
    SYS-04)                      return 0 ;;  # MAC enforcing without a permissive pass
    AUTH-04|AUTH-09|AUTH-14)     return 0 ;;  # PAM edits, self-inflicted lockout
    AUTH-05|AUTH-11|FS-05)       return 0 ;;  # needs a human: what IS that account/binary
    # World-writable paths are overwhelmingly inside container storage on any
    # host that runs containers, and mass-chmodding a snapshot tree corrupts
    # image layers. Found on a real docs server where all 3622 hits were under
    # /var/lib/containerd: the finding was true and the remediation was wrong.
    FS-04|FS-07)                 return 0 ;;
    *) return 1 ;;
  esac
}

# Reachability wave. Everything gets one, including IDs added later, so a new
# check family never falls out of the plan silently.
_advise_wave() {
  case "$1" in
    SSH-*|NET-*)               printf 1 ;;
    KRN-*|AUTH-*|SYS-04|SYS-05|SYS-07|SYS-08|SYS-09|SYS-10|FS-01|FS-02|FS-03|FS-05|FS-06|FS-09)
                               printf 2 ;;
    LOG-*|INT-*|AUD-*)         printf 3 ;;
    SYS-02|SYS-03|SYS-11)      printf 1 ;;   # unpatched is reachable from the network
    *)                         printf 4 ;;
  esac
}

_advise_wave_name() {
  case "$1" in
    1) printf 'Reachable from the network: no account needed' ;;
    2) printf 'Account to root: what the next kernel LPE gets' ;;
    3) printf 'You would not know: detection and forensics' ;;
    *) printf 'Hygiene and audit evidence' ;;
  esac
}

_advise_usage() {
  cat <<'EOF'
aartool advise: turn an audit into an ordered plan

Usage:
  aartool advise [REPORT.json] [options]

With no argument it uses the most recent JSON report it can find in the
current directory, ./reports/ and /var/log/cyberaar/.

Options:
  --wave N          Only show wave N (1-4)
  --safe-only       Keep findings whose fix has a real operational cost out of
                    the waves. They are still listed under "Decide before you
                    apply": nothing disappears, it just stops being in the
                    sequence you are about to run.
  --target HOST     Write the commands against this host (default: HOST)
  --user USER       Write the commands with this SSH user (default: USER)
  -h, --help        This help

Examples:
  sudo aartool inspect                       # reports land in ./reports
  aartool advise                             # reads the newest one
  aartool advise --target web-01 --user ubuntu
  aartool advise --wave 1 --safe-only
EOF
}

# Only files inspect actually wrote. An earlier version matched any *.json in
# the working directory, which happily picked up a package-lock and then said
# it did not look like a report. Guessing is fine; guessing from the wrong pool
# is how a tool earns a reputation for being confused.
_advise_find_report() {
  local f
  f=$(find . ./reports /var/log/cyberaar -maxdepth 1 \( -name 'aartool-*.json' -o -name 'cyberaar-*.json' \) -type f -print0 2>/dev/null \
      | xargs -0 -r ls -t 2>/dev/null | head -1) || true
  [[ -n "$f" ]] && printf '%s' "$f"
  return 0
}

cmd_advise() {
  resolve_paths

  local report="" only_wave="" safe_only=0 tgt="HOST" usr="USER"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)   _advise_usage; return 0 ;;
      --wave)      only_wave="${2:-}"; [[ "$only_wave" =~ ^[1-4]$ ]] || die "--wave takes 1, 2, 3 or 4."; shift 2 ;;
      --safe-only) safe_only=1; shift ;;
      --target)    tgt="${2:-}"; [[ -n "$tgt" ]] || die "--target needs a value."; shift 2 ;;
      --user)      usr="${2:-}"; [[ -n "$usr" ]] || die "--user needs a value."; shift 2 ;;
      -*)          die "Unknown option for advise: $1. Try 'aartool advise --help'." ;;
      *)           report="$1"; shift ;;
    esac
  done

  if [[ -z "$report" ]]; then
    report="$(_advise_find_report || true)"
    [[ -n "$report" ]] || die "No audit report given, and none found in ., ./reports or /var/log/cyberaar.
        Produce one first:
          sudo aartool inspect                          this machine
          aartool inspect --host HOST --user USER       another machine
        Reports land in ./reports, and advise with no argument reads the newest."
    info "Using the most recent report found: $report"
  fi
  [[ -f "$report" ]] || die "No such report: $report"
  grep -qE '"(aartool|cyberaar_baseline)"' "$report" \
    || die "$report does not look like an aartool audit report.
        It must be the JSON that 'aartool inspect -o DIR' writes, not the HTML."

  vlog "parsing $report"

  # Extract id/status/check from the results array without requiring jq. The
  # renderer writes one flat object per result with no nested objects, so a
  # record-per-line split on '},{' is exact rather than hopeful.
  # The renderer writes the array on one line but pretty-prints the object
  # around it, so the closing bracket is followed by a newline and four spaces.
  # An earlier version of this pattern required "],\"ansible_remediation\"" with
  # nothing between, matched the hand-built test fixture perfectly, and matched
  # no real report at all. Hence \s* here, and a real report as the fixture.
  local records; records=$(tr -d '\n' < "$report" \
    | grep -oP '"results":\s*\[\K.*?(?=\]\s*,\s*"ansible_remediation")' \
    | sed 's/}[[:space:]]*,[[:space:]]*{/}\n{/g')
  [[ -n "$records" ]] || die "Could not read any results out of $report."

  local host score
  host=$(grep -oP '"host":\s*"\K[^"]*' "$report" | head -1 || true)
  score=$(grep -oP '"score":\s*\K[0-9]+' "$report" | head -1 || true)

  printf '\n%s%s%s\n' "$BOLD" "Plan for ${host:-this host}" "$RESET"
  printf '  from %s' "$report"
  [[ -n "$score" ]] && printf '  ·  score %s/100' "$score"
  printf '\n'

  # Bucket the actionable findings.
  local -a W1=() W2=() W3=() W4=() DECIDE=()
  local total_open=0
  while IFS= read -r rec; do
    [[ -n "$rec" ]] || continue
    local id st ck
    id=$(grep -oP '"id":\s*"\K[^"]*'     <<<"$rec" || true)
    st=$(grep -oP '"status":\s*"\K[^"]*' <<<"$rec" || true)
    ck=$(grep -oP '"check":\s*"\K[^"]*'  <<<"$rec" || true)
    [[ "$st" == "FAIL" || "$st" == "WARN" ]] || continue
    total_open=$((total_open+1))

    local costly=0
    _advise_costly "$id" && costly=1
    if [[ $costly -eq 1 ]]; then
      DECIDE+=("$st|$id|$ck")
      [[ $safe_only -eq 1 ]] && continue
    fi

    local line="$st|$id|$ck"
    case "$(_advise_wave "$id")" in
      1) W1+=("$line") ;;
      2) W2+=("$line") ;;
      3) W3+=("$line") ;;
      *) W4+=("$line") ;;
    esac
  done <<<"$records"

  if [[ $total_open -eq 0 ]]; then
    success "Nothing open in this report. Every check passed."
    printf '  Keep it that way: %saartool diff%s against this file after the next change.\n\n' "$CYAN" "$RESET"
    return 0
  fi

  local w
  for w in 1 2 3 4; do
    [[ -n "$only_wave" && "$only_wave" != "$w" ]] && continue
    local -n arr="W$w"
    [[ ${#arr[@]} -gt 0 ]] || continue

    printf '\n%s── Wave %s · %s%s\n' "$BOLD" "$w" "$(_advise_wave_name "$w")" "$RESET"

    # FAIL first, then WARN. sort -s keeps report order inside each group.
    local -a tags=()
    local entry
    while IFS= read -r entry; do
      local st id ck
      IFS='|' read -r st id ck <<<"$entry"
      local mark="${YELLOW}WARN${RESET}"; [[ "$st" == "FAIL" ]] && mark="${RED}FAIL${RESET}"
      local note=""
      _advise_costly "$id" && note="  ${YELLOW}[needs a decision]${RESET}"
      kb_has "$id" && note="$note  ${CYAN}explain${RESET}"
      printf '   %s  %-9s %s%s\n' "$mark" "$id" "$ck" "$note"
      local m; m="$(_explain_map_line "$id")"
      [[ -n "$m" ]] && tags+=("$(cut -d'|' -f1 <<<"$m" | cut -d',' -f1)")
    done < <(printf '%s\n' "${arr[@]}" | sort -s -t'|' -k1,1)

    if [[ ${#tags[@]} -gt 0 ]]; then
      local joined; joined=$(printf '%s\n' "${tags[@]}" | sort -u | paste -sd, -)
      printf '\n     %spreview%s  aartool plan  --target %s --user %s --only %s\n' \
        "$CYAN" "$RESET" "$tgt" "$usr" "$joined"
      printf '     %sapply%s    aartool apply --target %s --user %s --only %s\n' \
        "$CYAN" "$RESET" "$tgt" "$usr" "$joined"
    fi
  done

  if [[ ${#DECIDE[@]} -gt 0 && -z "$only_wave" ]]; then
    printf '\n%s── Decide before you apply%s\n' "$BOLD" "$RESET"
    printf '   These break something real for somebody. What they break, and whether\n'
    printf '   this machine is somebody, is in the explanation for each.\n\n'
    local entry
    for entry in "${DECIDE[@]}"; do
      local st id ck; IFS='|' read -r st id ck <<<"$entry"
      printf '   %-9s %s\n' "$id" "$ck"
      printf '             %saartool explain %s%s\n' "$CYAN" "$id" "$RESET"
    done
  fi

  printf '\n%s── Order of operations%s\n' "$BOLD" "$RESET"
  cat <<EOF
   1. Run the wave 1 preview and read the diff. Nothing is changed by a plan.
   2. Apply wave 1 to ONE host, keeping a second SSH session open the whole time.
   3. Re-audit ${tgt} and compare, so you know what actually moved. Audit it
      the same way you did the first time: this plan was built from a report of
      ${host:-that host}, and 'sudo aartool inspect' would audit the machine you
      are standing on instead.
        aartool diff $report ./reports/<the new one>.json
   4. Only then roll the wave to a group, and start again at wave 2.

   The decision list is not a wave. Each item there is a conversation with
   whoever owns the workload, and the answer is often "not on this machine".
EOF
  printf '\n'
}
