#!/usr/bin/env bash
# =============================================================================
#  aartool-baseline: the audit engine behind `aartool inspect`
#  aartool-baseline : moteur d'audit derrière `aartool inspect`
#
#  Version   : see SCRIPT_VERSION below, which is the only place it is written
#  Author    : CyberAar (https://github.com/cyberaar/aartool)
#  License   : GPL v3
#  Target    : RHEL/CentOS/Ubuntu/Debian (Linux Government Servers)
#
#  Usage:
#    sudo bash aartool-baseline.sh
#    sudo bash aartool-baseline.sh --html-out /tmp/report.html
#    sudo bash aartool-baseline.sh --json-out /tmp/report.json
#    sudo bash aartool-baseline.sh --html-out /tmp/report.html --json-out /tmp/report.json
#    sudo aartool-baseline [same options] (after --install)
# =============================================================================

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_VERSION="4.8.5"
SCRIPT_NAME="aartool-baseline"

_show_help() {
  cat <<HELPEOF
aartool-baseline v${SCRIPT_VERSION}   (audit engine; run 'aartool --version' for the toolkit)

Usage: aartool-baseline [OPTIONS]

  --html-out <file>      Write HTML report to <file>
  --json-out <file>      Write JSON report to <file>
  --output-dir <dir>     Auto-name + store HTML and JSON in <dir>

Remote / Fleet options:
  --host <ip|host>       Run against a single remote host via SSH
  --host-file <file>     Run against multiple hosts (one IP/host per line)
  --inventory <file>     Parse an Ansible inventory file for hosts
  --user <user>          SSH user for remote scan (default: root)
  --ssh-key <keyfile>    SSH private key for remote scan
  --jump <user@host[:port]>
                         Reach the target through this bastion. Builds the
                         ProxyCommand itself, carrying --ssh-key onto the jump
                         hop. Prefer this over --ssh-opt '-J ...', which does
                         NOT pass the key or the connection options to hop 1.
  --ssh-opt <opt>        Extra ssh option, repeatable
  --ansible-dir <dir>    Path to your Ansible repo (for playbook suggestions)

Install options:
  --install              Install to /usr/local/bin/aartool-baseline
  --uninstall            Remove from /usr/local/bin/aartool-baseline
  --version              Print version and exit
  --help, -h             Show this help

Examples:
  # Local scan
  sudo aartool-baseline --html-out /tmp/report.html
  sudo aartool-baseline --output-dir /var/log/cyberaar

  # Remote single host
  aartool-baseline --host 10.0.1.10 --user admin --html-out /tmp/report-10.0.1.10.html

  # Fleet scan from file
  aartool-baseline --host-file /etc/cyberaar/hosts.txt --user admin --output-dir /var/log/cyberaar

  # Fleet scan from Ansible inventory
  aartool-baseline --inventory inventory/hosts --user admin --output-dir /var/log/cyberaar

  # With Ansible remediation suggestions
  aartool-baseline --host 10.0.1.10 --ansible-dir ~/aartool/ansible-hardening

  # Install
  sudo bash aartool-baseline.sh --install
HELPEOF
}

# ─── CLI ARGS ────────────────────────────────────────────────────────────────
HTML_OUT=""
JSON_OUT=""
# Declared before the parse loop: += on an undeclared name is an error under
# set -u, which would make the flag unusable rather than merely wrong.
REMOTE_SSH_OPTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --html-out)       HTML_OUT="$2";        shift 2 ;;
    --host)           REMOTE_HOST="$2";     shift 2 ;;
    --host-file)      REMOTE_HOST_FILE="$2";shift 2 ;;
    --inventory)      ANSIBLE_INVENTORY="$2";shift 2 ;;
    --user)           REMOTE_USER="$2";     shift 2 ;;
    --ssh-key)        REMOTE_KEY="$2";      shift 2 ;;
    --jump)           REMOTE_JUMP="$2";     shift 2 ;;
    # Repeatable, and split explicitly so --ssh-opt '-J host' and
    # --ssh-opt -J --ssh-opt host behave the same. read -ra rather than bare
    # word splitting: it says what it means and needs no shellcheck directive,
    # which cannot legally sit in front of a single case branch anyway.
    --ssh-opt)        read -ra _ssh_opt_words <<< "$2"
                      REMOTE_SSH_OPTS+=("${_ssh_opt_words[@]}"); shift 2 ;;
    --ansible-dir)    ANSIBLE_DIR="$2";     shift 2 ;;
    --json-out)   JSON_OUT="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --install)    DO_INSTALL=true; shift ;;
    --uninstall)  DO_UNINSTALL=true; shift ;;
    --version)    echo "aartool-baseline v${SCRIPT_VERSION}"; exit 0 ;;
    --help|-h)    _show_help; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

OUTPUT_DIR="${OUTPUT_DIR:-}"
DO_INSTALL="${DO_INSTALL:-false}"
DO_UNINSTALL="${DO_UNINSTALL:-false}"
REMOTE_HOST="${REMOTE_HOST:-}"
REMOTE_HOST_FILE="${REMOTE_HOST_FILE:-}"
REMOTE_USER="${REMOTE_USER:-root}"
REMOTE_KEY="${REMOTE_KEY:-}"
REMOTE_JUMP="${REMOTE_JUMP:-}"
ANSIBLE_INVENTORY="${ANSIBLE_INVENTORY:-}"
ANSIBLE_DIR="${ANSIBLE_DIR:-}"

OUTPUT_DIR_CREATED=false
if [[ -n "$OUTPUT_DIR" ]]; then
  [[ -d "$OUTPUT_DIR" ]] || OUTPUT_DIR_CREATED=true
  mkdir -p "$OUTPUT_DIR"
  DATESTR=$(date '+%Y%m%d-%H%M%S')
  HOST_SLUG=$(hostname -s 2>/dev/null | tr -cd 'a-zA-Z0-9-')
  [[ -z "$HTML_OUT" ]] && HTML_OUT="${OUTPUT_DIR}/aartool-${HOST_SLUG}-${DATESTR}.html"
  [[ -z "$JSON_OUT" ]] && JSON_OUT="${OUTPUT_DIR}/aartool-${HOST_SLUG}-${DATESTR}.json"
fi

# ─── INSTALL ─────────────────────────────────────────────────────────────────
if [[ "$DO_INSTALL" == true ]]; then
  [[ $EUID -ne 0 ]] && { echo '❌  Root required: sudo bash aartool-baseline.sh --install'; exit 1; }
  INST_DEST="/usr/local/bin/${SCRIPT_NAME}"
  cp -f "$SCRIPT_PATH" "$INST_DEST"
  chmod 755 "$INST_DEST"
  chown root:root "$INST_DEST"
  echo "✅  Installed → $INST_DEST"
  echo "    Try: sudo aartool-baseline --help"
  exit 0
fi

# ─── UNINSTALL ───────────────────────────────────────────────────────────────
if [[ "$DO_UNINSTALL" == true ]]; then
  INST_DEST="/usr/local/bin/${SCRIPT_NAME}"
  [[ -f "$INST_DEST" ]] && rm -f "$INST_DEST" && echo "✅  Removed $INST_DEST" || echo "⚠️   Not found: $INST_DEST"
  exit 0
fi

