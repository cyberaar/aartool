# ── paths ────────────────────────────────────────────────────────────────────
# A list of findings tells you what is wrong. An attacker does not exploit a
# list, they walk a chain: a way in, a way up, a way to stay, a way to not be
# seen. Each link alone is a "medium". Together they are the incident.
#
# `paths` reads an audit and shows which chains are actually complete on THIS
# host, and the cheapest link to cut in each. Everything is derived from the
# audit's own results; nothing is scanned or changed.
#
# A stage counts as OPEN when at least one of its findings is FAIL or WARN. A
# chain is COMPLETE when every stage is open: that is the one to read first.

# CHAIN|name|intro, then STAGE|label|why|ID,ID,... lines.
#
# Membership is a claim about cause, not about topic. A stage is only honest if
# every ID in it can, on its own, make that stage true. Two rules follow, and
# both were broken when these chains were first written:
#
#  - A finding that makes an EARLIER stage easier does not belong to a later
#    one. "No account lockout policy" and "password min length too short" sat
#    under "turn the account into root", where neither has any effect. On a
#    container with no passwordless sudo and no extra UID 0 account, that stage
#    still opened on those two and the tool declared internet-to-root COMPLETE.
#    A false COMPLETE is not a harmless over-warning: it is the number in the
#    exit code and the thing a CI gate fails on.
#  - A stage must not be a restatement of the chain's own premise. "Have a
#    local shell" in a chain whose intro already assumes any foothold cannot be
#    opened by findings that do not widen who gets one.
_paths_chains() {
  cat <<'CHAINS'
CHAIN|The front door: internet to root|An anonymous attacker, a wordlist and patience.
STAGE|Reach a login|The host answers the network and nothing filters who asks|NET-01,INT-04
STAGE|Guess without being stopped|Passwords are accepted, attempts are unlimited and nothing bans the source|SSH-02,SSH-03,INT-06,AUTH-09,AUTH-04,AUTH-14
STAGE|Land as root, or become it|The account reached is root, or becomes root without a password|SSH-01,AUTH-05,AUTH-11
CHAIN|The local climb: any shell to root|A stolen key, a web-app RCE, a compromised CI job. Any foothold.
STAGE|More ways to get that foothold|Password logins and dormant accounts widen who can land one|SSH-02,AUTH-06
STAGE|Find a kernel doorway|One unprivileged-only bug is enough, and these are the doors|KRN-01,KRN-02,KRN-03,KRN-04,KRN-12
STAGE|Nothing contains the exploit|No MAC policy, so root is root|SYS-04
CHAIN|The silent tenant: root to never found|What happens after root, and why you would not hear about it.
STAGE|Persist below the OS|Modules and kexec load code the OS never vouched for|KRN-05,KRN-06,KRN-08,SYS-08
STAGE|Nobody is recording|No audit trail, so nothing to replay|LOG-01,LOG-06,LOG-02
STAGE|Nobody would notice a change|No integrity baseline, and no copy of the logs off the box|INT-01,INT-07,INT-02,LOG-08
CHAIN|The pivot: one box to the next|How a compromised host becomes a stepping stone.
STAGE|Tunnel out through it|Forwarding lets the host relay for an attacker|SSH-04,NET-02
STAGE|Spoof or redirect on the wire|Redirects and router advertisements accepted, and unlogged|NET-07,NET-10,NET-13,NET-08
STAGE|No default-deny on the way out|Nothing constrains where the host may talk|NET-01
CHAINS
}

_paths_usage() {
  cat <<'EOF'
aartool paths: how an attacker would actually chain your findings

Usage:
  aartool paths [REPORT.json] [options]

Options:
  --all        Also show chains that are broken (some stage fully closed)
  -h, --help   This help

Exit codes:
  0   no complete attack chain
  1   at least one chain is complete end to end (useful as a CI gate)

With no argument it uses the newest report `inspect` wrote. Read-only.
EOF
}

# Print one chain. Globals from cmd_paths: ST, CK, show_all, complete.
_paths_render() {
  local name="$1" intro="$2"; shift 2
  local -n _lbl="$1" _why="$2" _ids="$3"
  local n=${#_lbl[@]} open_n=0 i x y
  local -a open_ids=()
  for ((i=0; i<n; i++)); do
    local hit=""
    for x in ${_ids[i]//,/ }; do
      [[ "${ST[$x]:-}" == "FAIL" || "${ST[$x]:-}" == "WARN" ]] && hit="$hit $x"
    done
    open_ids[i]="${hit# }"
    [[ -n "${open_ids[i]}" ]] && open_n=$((open_n+1))
  done
  local whole=0; [[ $open_n -eq $n ]] && whole=1
  [[ $whole -eq 0 && $show_all -eq 0 ]] && return 0
  [[ $whole -eq 1 ]] && complete=$((complete+1))

  if [[ $whole -eq 1 ]]; then
    printf '\n%s● COMPLETE%s  %s%s%s\n' "$RED" "$RESET" "$BOLD" "$name" "$RESET"
  else
    printf '\n%s○ broken (%d of %d stages open)%s  %s%s%s\n' "$GREEN" "$open_n" "$n" "$RESET" "$BOLD" "$name" "$RESET"
  fi
  printf '  %s%s%s\n\n' "$CYAN" "$intro" "$RESET"

  local cut=""
  for ((i=0; i<n; i++)); do
    if [[ -n "${open_ids[i]}" ]]; then
      printf '   %s[%d] %-32s open%s\n' "$RED" $((i+1)) "${_lbl[i]}" "$RESET"
      printf '       %s\n' "${_why[i]}"
      for y in ${open_ids[i]}; do
        printf '         %s%-8s%s %s\n' "$YELLOW" "$y" "$RESET" "${CK[$y]:-}"
      done
      if [[ -z "$cut" ]]; then
        for y in ${open_ids[i]}; do
          _advise_costly "$y" || { cut="$y"; break; }
        done
      fi
    else
      printf '   %s[%d] %-32s closed%s\n' "$GREEN" $((i+1)) "${_lbl[i]}" "$RESET"
    fi
  done
  if [[ $whole -eq 1 ]]; then
    if [[ -n "$cut" ]]; then
      printf '\n   %sA safe link to cut:%s %s  %s\n' "$BOLD" "$RESET" "$cut" "${CK[$cut]:-}"
      printf '   %saartool explain %s%s\n' "$CYAN" "$cut" "$RESET"
    else
      printf '\n   %sEvery open link here needs a decision first.%s  aartool advise\n' "$BOLD" "$RESET"
    fi
  fi
}

cmd_paths() {
  local report="" show_all=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) _paths_usage; return 0 ;;
      --all)     show_all=1; shift ;;
      -*)        die "Unknown option for paths: $1. Try 'aartool paths --help'." ;;
      *)         report="$1"; shift ;;
    esac
  done
  report="$(report_resolve "$report")"

  local -A ST=() CK=()
  local id st ck recs
  recs="$(report_records "$report")" || die "Could not read any results out of $report."
  while IFS='|' read -r id st ck; do
    ST["$id"]="$st"; CK["$id"]="$ck"
  done <<<"$recs"

  local host; host=$(grep -oP '"host":\s*"\K[^"]*' "$report" | head -1 || true)
  printf '\n%sAttack paths on %s%s\n' "$BOLD" "${host:-this host}" "$RESET"
  printf '  Derived from %s. Nothing was scanned or changed.\n' "$report"

  local complete=0 kind a b c name="" intro=""
  local -a lbl=() why=() ids=()
  while IFS='|' read -r kind a b c; do
    case "$kind" in
      CHAIN)
        [[ -n "$name" ]] && _paths_render "$name" "$intro" lbl why ids
        name="$a"; intro="$b"; lbl=(); why=(); ids=() ;;
      STAGE) lbl+=("$a"); why+=("$b"); ids+=("$c") ;;
    esac
  done < <(_paths_chains)
  [[ -n "$name" ]] && _paths_render "$name" "$intro" lbl why ids

  printf '\n'
  if [[ $complete -eq 0 ]]; then
    success "No attack chain is complete on this host. Closing any one link keeps it that way."
    return 0
  fi
  printf '%s%d complete chain(s).%s Breaking one link per chain is enough; you do not need to fix everything.\n\n' \
    "$BOLD" "$complete" "$RESET"
  return 1
}
