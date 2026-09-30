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
  # Emitted LAST chain first, on purpose. Mermaid lays subgraphs out against
  # the flow direction, so under `flowchart LR` they stack vertically in
  # REVERSE declaration order: declared front-door-first, the diagram put the
  # front door at the bottom and the pivot at the top, which is the opposite of
  # the reading order the text output uses. Checked by rendering both with
  # mermaid-cli and comparing the images, not by reading the spec.
  #
  # The alternatives were worse. `flowchart TB` puts the chains side by side,
  # 784x87 for four of them, unreadable. Invisible links (`C0 ~~~ C1`) pin the
  # order but make mermaid treat the subgraphs as nodes in the LR flow, giving
  # the same flattened row. The subgraph ids stay tied to the chain index, so
  # C0 is still the front door whatever order it is printed in.
  local c s complete=0 prev
  for ((c=${#CH_NAME[@]}-1; c>=0; c--)); do
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

# ── the one-screen view ──────────────────────────────────────────────────────
# The default for one host. The detail view is 60 lines for three chains, which
# is the right depth for someone fixing a chain and the wrong first thing to
# meet: it buries the answer to "am I exposed, and what do I do about it". This
# prints the verdict, one pipeline per chain, and the link to cut. `--detail`
# gives the full stage-by-stage list. Both read the same definitions and the
# same statuses, so they cannot disagree about which chains are complete.

# Glyphs follow the locale, chosen up front like the banner: there is no way to
# un-print a line of boxes on a serial console or a rescue shell.
_paths_glyphs() {
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8*|*utf8*|*UTF8*) G_ON='●'; G_OFF='○'; G_ARROW='▸' ;;
    *)                     G_ON='*';  G_OFF='o'; G_ARROW='>' ;;
  esac
}

# Terminal width into PATHS_COLS: COLUMNS if set, else what the terminal
# reports, else 80. A pipe has no width, so it gets the conventional one. Sets a
# global instead of printing, because inside $(...) stdout is never a terminal
# and the test for one would always say no.
_paths_cols() {
  PATHS_COLS="${COLUMNS:-}"
  if [[ ! "$PATHS_COLS" =~ ^[0-9]+$ ]]; then
    PATHS_COLS=""; [[ -t 1 ]] && PATHS_COLS="$(tput cols 2>/dev/null || true)"
  fi
  [[ "$PATHS_COLS" =~ ^[0-9]+$ && "$PATHS_COLS" -ge 20 ]] || PATHS_COLS=80
}

# Fill the row arrays for chain $1 from ST: R_LBL, R_CNT, R_OPN (per stage, in
# order) and R_FIRST_CLOSED. Globals rather than a subshell, so the arrays live.
_paths_rows() {
  local c="$1" s o
  R_LBL=(); R_CNT=(); R_OPN=(); R_FIRST_CLOSED=""
  for ((s=0; s<${#SG_CHAIN[@]}; s++)); do
    [[ "${SG_CHAIN[$s]}" == "$c" ]] || continue
    o="$(_paths_stage_open ST "$s")"
    R_LBL+=("${SG_LABEL[$s]}"); R_OPN+=("$o")
    if [[ -n "$o" ]]; then R_CNT+=("$(wc -w <<<"$o" | tr -d ' ') open")
    else R_CNT+=("closed"); [[ -n "$R_FIRST_CLOSED" ]] || R_FIRST_CLOSED="${SG_LABEL[$s]}"; fi
  done
}

# Trim the report path to $2 columns, keeping the tail and marking the cut with
# a leading ellipsis: the file name is the identifying part. Only the strings
# that come from outside are trimmed. The fixed text of the view is bounded and
# soft-wraps at most once on a very narrow terminal, which is not worth four
# more branches; a path or a check name has no bound at all.
_paths_tail() {
  local s="$1" w="$2"
  if (( ${#s} <= w )); then printf '%s' "$s"
  elif (( w > 3 )); then printf '...%s' "${s: -$((w-3))}"
  else printf '%s' "$(basename -- "$s")"; fi
}

# Uses ST and CK from cmd_paths (dynamic scope). $1 is the host name, $2 the
# report it was read from.
_paths_compact() {
  local host="$1" report="$2"
  _paths_load_chains
  _paths_glyphs
  _paths_cols; local cols="$PATHS_COLS"

  local c s n_complete=0
  local -a is_whole=()
  for ((c=0; c<${#CH_NAME[@]}; c++)); do
    if _paths_chain_complete ST "$c"; then is_whole[c]=1; n_complete=$((n_complete+1)); else is_whole[c]=0; fi
  done

  printf '\n  %sAttack paths%s  %s\n' "$BOLD" "$RESET" "$host"
  # Where the answer came from, and the read-only claim. The detail view has
  # carried this line since the command existed, and the default view is the
  # one most people now see, so it carries it too. report_resolve picks a
  # report when none is named, so this is also the only place that choice is
  # visible.
  local claim="Nothing was scanned or changed."
  printf '  %sDerived from %s. %s%s\n' "$CYAN" \
    "$(_paths_tail "$report" $(( cols - 2 - 13 - 2 - ${#claim} )))" "$claim" "$RESET"
  if [[ $n_complete -eq 0 ]]; then
    printf '  %sNo attack chain is complete on this host.%s\n  Closing any one link keeps it that way.\n' "$GREEN" "$RESET"
  else
    printf '  %s%d of %d chains are complete.%s Cut one link in each.\n' \
      "$BOLD" "$n_complete" "${#CH_NAME[@]}" "$RESET"
  fi

  # One layout for the whole screen, decided before anything is printed. If any
  # complete chain does not fit as a pipeline at this width, all of them are
  # stacked; if any broken chain's note does not fit beside its name, all of
  # them are wrapped. Both decisions are global for the same reason: a screen
  # that mixes two shapes reads as a rendering accident, and the broken chains
  # are where that showed, because a fully hardened host is nothing but broken
  # chains and their names differ by ten characters.
  local sep=" ${G_ARROW} " pipeline=1 note_inline=1 i
  for ((c=0; c<${#CH_NAME[@]}; c++)); do
    _paths_rows "$c"
    if [[ "${is_whole[$c]}" -eq 1 ]]; then
      local t=4 a b
      for ((i=0; i<${#R_LBL[@]}; i++)); do
        a=${#R_LBL[i]}; b=${#R_CNT[i]}; t=$(( t + (a > b ? a : b) ))
      done
      t=$(( t + (${#R_LBL[@]} - 1) * 3 ))
      [[ $t -le $cols ]] || pipeline=0
    else
      local note="broken: \"$R_FIRST_CLOSED\" is closed"
      (( 5 + ${#CH_NAME[$c]} + 3 + ${#note} <= cols )) || note_inline=0
    fi
  done

  # Complete chains first, broken ones after: the order is the answer.
  local pass
  for pass in 1 0; do
  for ((c=0; c<${#CH_NAME[@]}; c++)); do
    [[ "${is_whole[$c]}" -eq "$pass" ]] || continue
    _paths_rows "$c"
    local -a lbl=("${R_LBL[@]}") cnt=("${R_CNT[@]}") opn=("${R_OPN[@]}")
    local first_closed="$R_FIRST_CLOSED"

    if [[ "${is_whole[$c]}" -eq 0 ]]; then
      local note="broken: \"$first_closed\" is closed"
      if [[ $note_inline -eq 1 ]]; then
        printf '\n  %s%s%s  %s%s%s   %s%s%s\n' "$GREEN" "$G_OFF" "$RESET" "$BOLD" "${CH_NAME[$c]}" "$RESET" "$GREEN" "$note" "$RESET"
      else
        printf '\n  %s%s%s  %s%s%s\n     %s%s%s\n' "$GREEN" "$G_OFF" "$RESET" "$BOLD" "${CH_NAME[$c]}" "$RESET" "$GREEN" "$note" "$RESET"
      fi
      continue
    fi

    printf '\n  %s%s COMPLETE%s  %s%s%s\n' "$RED" "$G_ON" "$RESET" "$BOLD" "${CH_NAME[$c]}" "$RESET"

    local n=${#lbl[@]}
    local -a colw=()
    for ((i=0; i<n; i++)); do
      local wa=${#lbl[i]} wb=${#cnt[i]}
      colw[i]=$(( wa > wb ? wa : wb ))
    done

    if [[ $pipeline -eq 1 ]]; then
      printf '    '
      for ((i=0; i<n; i++)); do
        [[ $i -gt 0 ]] && printf '%s' "$sep"
        printf '%s%-*s%s' "$RED" "${colw[i]}" "${lbl[i]}" "$RESET"
      done
      printf '\n    '
      for ((i=0; i<n; i++)); do
        [[ $i -gt 0 ]] && printf '   '
        # The last column is not padded: trailing spaces are invisible noise in
        # a copied screenshot and in a diff.
        if [[ $i -lt $((n-1)) ]]; then printf '%-*s' "${colw[i]}" "${cnt[i]}"; else printf '%s' "${cnt[i]}"; fi
      done
      printf '\n'
    else
      for ((i=0; i<n; i++)); do
        printf '    %s%s%s %s%s%s  (%s)\n' "$YELLOW" "$G_ARROW" "$RESET" "$RED" "${lbl[i]}" "$RESET" "${cnt[i]}"
      done
    fi

    # The first open finding that is safe to apply blind, in stage order.
    local cut="" y
    for ((i=0; i<n; i++)); do
      [[ -n "$cut" ]] && break
      for y in ${opn[i]}; do
        _advise_costly "$y" || { cut="$y"; break; }
      done
    done
    if [[ -n "$cut" ]]; then
      # Trim the check's name to the line: it comes from the report and can be
      # any length. Below the width where even an ellipsis does not pay for
      # itself the name is dropped rather than printed as three dots, because
      # the id beside it is the part you act on.
      local room=$(( cols - 4 - 3 - 2 - ${#cut} - 2 )) what="${CK[$cut]:-}"
      if (( ${#what} > room )); then
        if (( room > 6 )); then what="${what:0:room-3}..."; else what=""; fi
      fi
      if [[ -n "$what" ]]; then
        printf '    %scut%s  %s%s%s  %s\n' "$BOLD" "$RESET" "$YELLOW" "$cut" "$RESET" "$what"
      else
        printf '    %scut%s  %s%s%s\n' "$BOLD" "$RESET" "$YELLOW" "$cut" "$RESET"
      fi
    else
      printf '    %severy open link here needs a decision first%s  (aartool advise)\n' "$BOLD" "$RESET"
    fi
  done
  done

  printf '\n  %saartool explain <ID>%s  why a link matters\n' "$CYAN" "$RESET"
  printf '  %s--detail%s  every finding   %s--format mermaid%s  a diagram\n\n' "$CYAN" "$RESET" "$CYAN" "$RESET"
  [[ $n_complete -eq 0 ]] && return 0
  return 1
}
