# ── demo ─────────────────────────────────────────────────────────────────────
# The loop, on a bundled sample audit: no root, no SSH, no Ansible, nothing
# touched. It exists so someone can see what aartool is in thirty seconds
# before deciding whether to point it at a machine.

cmd_demo() {
  case "${1:-}" in
    -h|--help) printf 'aartool demo: tour the audit loop on a bundled sample. Changes nothing.\n'; return 0 ;;
  esac
  resolve_paths
  local sample; sample="$(dirname "$TOOLKIT_DASHBOARD")/demo-audit.json"
  [[ -f "$sample" ]] || die "Sample audit not found: $sample"

  banner
  printf '%sA sample audit of a made-up Ubuntu server. Nothing on this machine is read or changed.%s\n' "$BOLD" "$RESET"

  printf '\n%s$ aartool advise%s   # what to fix first, and what each fix costs\n' "$CYAN" "$RESET"
  cmd_advise "$sample" --wave 1 || true

  printf '\n%s$ aartool paths%s    # how the findings chain into an attack\n' "$CYAN" "$RESET"
  cmd_paths "$sample" || true

  printf '\n%s$ aartool explain KRN-01%s   # what closing it breaks\n' "$CYAN" "$RESET"
  cmd_explain KRN-01 || true

  printf '\n%sNow the real thing:%s  sudo aartool inspect   then   aartool advise   and   aartool paths\n\n' "$BOLD" "$RESET"
}
