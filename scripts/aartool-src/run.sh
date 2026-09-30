# ── Dispatch ─────────────────────────────────────────────────────────────────
main() {
  [[ $# -gt 0 ]] || { usage; exit 1; }

  # -v is global, so it works before or after the command name. Anything else
  # is left for the command to parse.
  local -a args=()
  local a
  for a in "$@"; do
    case "$a" in
      -v|--verbose) AARTOOL_VERBOSE=1 ;;
      *) args+=("$a") ;;
    esac
  done
  [[ ${#args[@]} -gt 0 ]] || { usage; exit 1; }
  set -- "${args[@]}"
  vlog "aartool $AARTOOL_VERSION, verbose on"

  case "$1" in
    inspect)        shift; cmd_inspect "$@" ;;
    plan)           shift; cmd_harden plan  "$@" ;;
    apply)          shift; cmd_harden apply "$@" ;;
    surface)        shift; cmd_surface "$@" ;;
    advise)         shift; cmd_advise "$@" ;;
    explain|why)    shift; cmd_explain "$@" ;;
    doctor)         shift; cmd_doctor "$@" ;;
    report)         shift; cmd_report "$@" ;;
    diff)           shift; cmd_diff "$@" ;;
    paths)          shift; cmd_paths "$@" ;;
    badge)          shift; cmd_badge "$@" ;;
    demo)           shift; cmd_demo "$@" ;;
    install)        shift; cmd_install "$@" ;;
    # `aartool uninstall` is what people type. It used to be an unknown command,
    # which is a poor answer when the thing they want exists behind a flag.
    uninstall)      shift; cmd_install --uninstall "$@" ;;
    -h|--help|help) usage ;;
    -V|--version|version) printf 'aartool %s\n' "$AARTOOL_VERSION" ;;
    # Named so the error can be specific rather than "unknown command".
    audit|scan)     die "There is no '$1' command. Auditing is 'aartool inspect'." ;;
    harden)         die "There is no 'harden' command. Preview with 'aartool plan', apply with 'aartool apply'." ;;
    fix|remediate)  die "There is no '$1' command. See the plan with 'aartool advise', apply it with 'aartool apply'." ;;
    -*)             die "Unknown option: $1. Try 'aartool --help'." ;;
    *)              die "Unknown command: $1. Try 'aartool --help'." ;;
  esac
}

main "$@"
