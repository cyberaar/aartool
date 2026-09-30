# ── paths: the estate view and the diagram ───────────────────────────────────
# Two more ways to read the same chains that `paths` evaluates for one host.
#
#   aartool paths a.json b.json c.json     which chains are complete where, and
#                                          the smallest change that breaks each
#   aartool paths REPORT --format mermaid  the chains as a diagram that GitHub,
#                                          GitLab and most wikis render natively
#
# The chain definitions stay in _paths_chains (paths.sh); nothing here restates
# them. This file only evaluates them per report and renders the result.

# Parse _paths_chains once into parallel arrays so every host is evaluated
# against the same definitions.
#   CH_NAME[c] CH_INTRO[c]                      one per chain
#   SG_CHAIN[s] SG_LABEL[s] SG_IDS[s]           one per stage, in order
_paths_load_chains() {
  CH_NAME=(); CH_INTRO=(); SG_CHAIN=(); SG_LABEL=(); SG_IDS=()
  local kind a b c
  while IFS='|' read -r kind a b c; do
    case "$kind" in
      CHAIN) CH_NAME+=("$a"); CH_INTRO+=("$b") ;;
      STAGE) SG_CHAIN+=("$(( ${#CH_NAME[@]} - 1 ))"); SG_LABEL+=("$a"); SG_IDS+=("$c") ;;
    esac
  done < <(_paths_chains)
  [[ ${#CH_NAME[@]} -gt 0 && ${#SG_IDS[@]} -gt 0 ]] || die "paths: no chain definitions were loaded."
}

# Space separated FAIL/WARN ids of stage $2, judged by the status map named $1.
_paths_stage_open() {
  local -n _map="$1"
  local x hit=""
  for x in ${SG_IDS[$2]//,/ }; do
    [[ "${_map[$x]:-}" == "FAIL" || "${_map[$x]:-}" == "WARN" ]] && hit="$hit $x"
  done
  printf '%s' "${hit# }"
}

# Read one report into the associative array named $2 (id to status) and set
# PATHS_HOST. Not called in a subshell, or the array would be lost. Fails loud on a report with no results: an unreadable report
# must never read as "no chain is complete".
_paths_read_report() {
  local report="$1"; local -n _out="$2"
  # Locals are underscored: a nameref resolves against the innermost scope, so a
  # local named like the caller's array silently captures the writes.
  local _recs _id _st _ck
  _recs="$(report_records "$report")" || die "Could not read any results out of $report."
  while IFS='|' read -r _id _st _ck; do
    [[ -n "$_id" ]] && _out["$_id"]="$_st"
  done <<<"$_recs"
  [[ ${#_out[@]} -gt 0 ]] || die "Could not read any results out of $report."
  local host; host=$(grep -oP '"host":\s*"\K[^"]*' "$report" | head -1 || true)
  PATHS_HOST="${host:-$(basename "$report")}"
}

# Is chain $2 complete under the status map named $1?
_paths_chain_complete() {
  local s
  for ((s=0; s<${#SG_CHAIN[@]}; s++)); do
    [[ "${SG_CHAIN[$s]}" == "$2" ]] || continue
    [[ -n "$(_paths_stage_open "$1" "$s")" ]] || return 1
  done
  return 0
}

# ── estate ───────────────────────────────────────────────────────────────────
_paths_estate() {
  local -a reports=("$@")
  _paths_load_chains

  local -a hosts=() ; local -a maps=()
  local r i host
  for r in "${reports[@]}"; do
    report_resolve "$r" >/dev/null
    local -A _m=()
    _paths_read_report "$r" _m; host="$PATHS_HOST"
    for i in "${hosts[@]:-}"; do
      [[ "$i" == "$host" ]] && die "Two reports are for the same host '$host'.
        A before and after pair would count that machine twice. Pass the newest
        report per host, or use 'aartool diff' to compare two audits."
    done
    hosts+=("$host")
    # Serialise the map into one string; bash cannot nest associative arrays.
    local ser="" k
    for k in "${!_m[@]}"; do ser+="$k=${_m[$k]} "; done
    maps+=("$ser")
    unset _m
  done

  printf '\n%sEstate attack paths%s  %d hosts\n' "$BOLD" "$RESET" "${#hosts[@]}"
  printf '  Derived from the audits alone. Nothing was scanned or changed.\n'

  local any=0 c s h
  for ((c=0; c<${#CH_NAME[@]}; c++)); do
    local -a done_hosts=()
    local -A union=() # stage index -> space separated open ids across complete hosts
    for ((h=0; h<${#hosts[@]}; h++)); do
      local -A hm=()
      local pair
      # hm is read through a nameref in _paths_chain_complete and _paths_stage_open.
      # shellcheck disable=SC2034
      for pair in ${maps[$h]}; do hm["${pair%%=*}"]="${pair#*=}"; done
      if _paths_chain_complete hm "$c"; then
        done_hosts+=("${hosts[$h]}")
        for ((s=0; s<${#SG_CHAIN[@]}; s++)); do
          [[ "${SG_CHAIN[$s]}" == "$c" ]] || continue
          union[$s]="${union[$s]:-} $(_paths_stage_open hm "$s")"
        done
      fi
      unset hm
    done
    [[ ${#done_hosts[@]} -gt 0 ]] || { unset union; continue; }
    any=1

    printf '\n%s● COMPLETE on %d of %d%s  %s%s%s\n' "$RED" "${#done_hosts[@]}" "${#hosts[@]}" "$RESET" "$BOLD" "${CH_NAME[$c]}" "$RESET"
    printf '  %s%s%s\n' "$CYAN" "${CH_INTRO[$c]}" "$RESET"
    printf '  hosts: %s\n' "$(printf '%s\n' "${done_hosts[@]}" | paste -sd, - | sed 's/,/, /g')"

    # The smallest set of findings that breaks this chain on every affected
    # host: closing every open id of ONE stage does it. Fewest distinct ids wins,
    # earliest stage on a tie.
    local best="" best_n=999999 bl=""
    for ((s=0; s<${#SG_CHAIN[@]}; s++)); do
      [[ "${SG_CHAIN[$s]}" == "$c" ]] || continue
      local u; u="$(tr ' ' '\n' <<<"${union[$s]:-}" | sed '/^$/d' | sort -u | paste -sd' ' -)"
      local n; n=$(wc -w <<<"$u")
      if [[ $n -lt $best_n ]]; then best_n=$n; best="$u"; bl="${SG_LABEL[$s]}"; fi
    done
    printf '\n   %sSmallest change that breaks it on all %d:%s close %s\n' "$BOLD" "${#done_hosts[@]}" "$RESET" "$best"
    local costly="" y
    for y in $best; do _advise_costly "$y" && costly="$costly $y"; done
    [[ -n "$costly" ]] && printf '   %sneeds a decision first:%s%s  (aartool explain <ID>)\n' "$YELLOW" "$RESET" "$costly"
    printf '   %s(stage: %s)%s\n' "$CYAN" "$bl" "$RESET"
    unset union done_hosts
  done

  printf '\n'
  if [[ $any -eq 0 ]]; then
    success "No attack chain is complete on any of the ${#hosts[@]} hosts."
    return 0
  fi
  printf 'Per host detail: %saartool paths <report>%s\n\n' "$CYAN" "$RESET"
  return 1
}

# ── mermaid ──────────────────────────────────────────────────────────────────
# Only static labels and check ids go into the diagram. The host name is the one
# attacker-influenced string, and it is reduced to a safe character set.
_paths_mermaid() {
  local report="$1"
  _paths_load_chains
  local -A st=()
  local host; _paths_read_report "$report" st; host="$PATHS_HOST"
  host="$(tr -cd 'A-Za-z0-9._-' <<<"$host")"

  printf '%%%% aartool paths, host: %s\n' "${host:-unknown}"
  printf 'flowchart LR\n'
  local c s complete=0 prev
  for ((c=0; c<${#CH_NAME[@]}; c++)); do
    local whole=0; _paths_chain_complete st "$c" && whole=1
    [[ $whole -eq 1 ]] && complete=$((complete+1))
    local tag="broken"; [[ $whole -eq 1 ]] && tag="COMPLETE"
    printf '  subgraph C%d["%s (%s)"]\n    direction LR\n' "$c" "${CH_NAME[$c]//\"/}" "$tag"
    prev=""
    for ((s=0; s<${#SG_CHAIN[@]}; s++)); do
      [[ "${SG_CHAIN[$s]}" == "$c" ]] || continue
      local open; open="$(_paths_stage_open st "$s")"
      local cls="closed" text="${SG_LABEL[$s]//\"/}"
      if [[ -n "$open" ]]; then
        cls="open"; text="$text<br/>${open// /, }"
      else
        text="$text<br/>closed"
      fi
      printf '    C%dS%d["%s"]:::%s\n' "$c" "$s" "$text" "$cls"
      [[ -n "$prev" ]] && printf '    %s --> C%dS%d\n' "$prev" "$c" "$s"
      prev="C${c}S${s}"
    done
    printf '  end\n'
  done
  # Named colours, not hex: the one palette rule applies to every renderer.
  printf '  classDef open stroke:red,stroke-width:2px\n'
  printf '  classDef closed stroke:green,stroke-dasharray:4 3\n'
  [[ $complete -eq 0 ]] && return 0
  return 1
}
