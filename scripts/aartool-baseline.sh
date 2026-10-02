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


# =============================================================================
#  DISTRIBUTION DETECTION
#
#  Two different questions, kept apart on purpose, because answering them as one
#  is what made the old message useless.
#
#    Can this machine be AUDITED?      Almost always yes. The checks read
#                                      sysctls, /proc, /etc and systemd. None of
#                                      that is distribution specific.
#
#    Are HARDENING ROLES available?    Currently only for the RHEL 9 family and
#                                      Ubuntu/Debian. That is a real limit and
#                                      pretending otherwise wastes people's time.
#
#  The old check matched six names and told everyone else to "use RHEL, Ubuntu or
#  Debian for official security support". Someone running openSUSE or Alpine does
#  not need to be told to change distribution; they need to know the audit will
#  still work and which part will not.
#
#  ID_LIKE is used before ID, so derivatives inherit correctly: Pop!_OS, Mint and
#  Zorin declare ID_LIKE=ubuntu; Rocky, Alma and Oracle declare ID_LIKE="rhel
#  centos fedora". A derivative nobody has heard of still lands in the right
#  family without this file being updated.
# =============================================================================

# Overridable so the mapping can be tested against every distribution rather
# than only the one the test happens to run on, and so a mounted image can be
# identified without booting it.
OS_RELEASE_PATH="${OS_RELEASE_PATH:-/etc/os-release}"

_DISTRO_ID=""; _DISTRO_LIKE=""; _DISTRO_PRETTY=""; _DISTRO_VERSION=""
# The path is deliberately a variable so tests can point at a fixture and a
# mounted image can be identified; shellcheck cannot follow that statically.
# shellcheck source=/dev/null
if [[ -r "$OS_RELEASE_PATH" ]]; then
  _DISTRO_ID="$(       . "$OS_RELEASE_PATH" 2>/dev/null; printf '%s' "${ID:-}" )"
  _DISTRO_LIKE="$(     . "$OS_RELEASE_PATH" 2>/dev/null; printf '%s' "${ID_LIKE:-}" )"
  _DISTRO_PRETTY="$(   . "$OS_RELEASE_PATH" 2>/dev/null; printf '%s' "${PRETTY_NAME:-}" )"
  _DISTRO_VERSION="$(  . "$OS_RELEASE_PATH" 2>/dev/null; printf '%s' "${VERSION_ID:-}" )"
fi

distro_id()      { printf '%s' "${_DISTRO_ID:-unknown}"; }
distro_pretty()  { printf '%s' "${_DISTRO_PRETTY:-${_DISTRO_ID:-unknown}} ${_DISTRO_VERSION}"; }

# rhel | debian | suse | arch | alpine | gentoo | unknown
distro_family() {
  local id="$_DISTRO_ID" like=" $_DISTRO_LIKE "
  case "$id" in
    rhel|centos|almalinux|rocky|fedora|ol|oracle|amzn|scientific|cloudlinux) printf 'rhel'; return ;;
    ubuntu|debian|linuxmint|pop|raspbian|kali|zorin|elementary|devuan)       printf 'debian'; return ;;
    opensuse*|sles|sled|suse)                                               printf 'suse'; return ;;
    arch|manjaro|endeavouros|garuda)                                        printf 'arch'; return ;;
    alpine)                                                                 printf 'alpine'; return ;;
    gentoo)                                                                 printf 'gentoo'; return ;;
    # Azure Linux is RPM-based but uses tdnf and a different layout. Close to
    # the RHEL family is not the same as tested on it, so it gets its own name
    # and no role claim.
    mariner|azurelinux)                                                     printf 'azure'; return ;;
  esac
  # Unrecognised name: fall back to what the distribution says it resembles.
  case "$like" in
    *" rhel "*|*" centos "*|*" fedora "*) printf 'rhel' ;;
    *" debian "*|*" ubuntu "*)            printf 'debian' ;;
    *" suse "*|*" opensuse "*)            printf 'suse' ;;
    *" arch "*)                           printf 'arch' ;;
    *" alpine "*)                         printf 'alpine' ;;
    *)                                    printf 'unknown' ;;
  esac
}

# The package manager actually present, which is the thing the update check
# needs. Asking the binary beats inferring it from the family: Fedora has dnf5,
# some minimal images have neither.
distro_pkg_mgr() {
  local m
  for m in dnf5 dnf yum apt-get zypper pacman apk xbps-install emerge; do
    command -v "$m" >/dev/null 2>&1 && { printf '%s' "$m"; return; }
  done
  printf 'none'
}

# Do we ship Ansible hardening roles for this family?
#
# rhel and debian only. Everything else can still be audited: the checks read
# sysctls, /proc, /etc and systemd, none of which is distribution specific.
# Saying "audit works, hardening does not" is useful. Telling someone on
# openSUSE to switch to RHEL is not, and that is what the old message did.
distro_roles_available() {
  case "$(distro_family)" in
    rhel|debian) return 0 ;;
    *)           return 1 ;;
  esac
}

# What CI actually proves, as opposed to what the roles are written for. Molecule
# runs every role against these two images and nothing else, so this is the only
# claim that is backed by evidence.
distro_roles_tested() { printf 'Rocky Linux 9, Ubuntu 22.04'; }

# =============================================================================
#  ANSIBLE REMEDIATION MAP
#  Maps each check ID → ansible tags + role names for RHEL9 and Ubuntu/Debian
#  Used to generate targeted remediation commands after the scan.
# =============================================================================
declare -A ANSIBLE_MAP=(
  # SYS-01: OS detection — informational, no Ansible remediation
  # SYS-02: kernel version — remediation is applying updates, not sysctl tuning
  ["SYS-02"]="updates,patching|linux_dnf_automatic_rhel9|linux_unattended_upgrades_ubuntu|Apply pending kernel updates"
  ["SYS-03"]="updates,patching|linux_dnf_automatic_rhel9|linux_unattended_upgrades_ubuntu|Automatic security updates"
  ["SYS-04"]="mac|linux_selinux_rhel9|linux_apparmor_ubuntu|SELinux/AppArmor enforcement"
  ["SYS-05"]="kernel,coredump|linux_core_dumps_rhel9|linux_core_dumps_ubuntu|Core dump restriction"
  ["SYS-06"]="time,ntp|linux_chrony_rhel9|linux_chrony_ubuntu|Time synchronization (chrony)"
  ["SYS-07"]="boot,grub|linux_bootloader_password_rhel9|linux_bootloader_password_ubuntu|GRUB config permissions"
  ["SYS-08"]="secureboot|linux_secure_boot_rhel9|linux_secure_boot_ubuntu|Secure Boot verification"
  ["SYS-09"]="filesystem,mounts|linux_tmp_mounts_rhel9|linux_tmp_mounts_ubuntu|/dev/shm mount hardening"
  ["SYS-10"]="system|linux_ctrl_alt_del_rhel9|linux_ctrl_alt_del_ubuntu|Ctrl-Alt-Delete disabled"
  # SYS-11: no role can fix this one. The remediation is a reboot, and on a quorum
  # cluster a reboot is an orchestration problem, not a configuration one. The roles
  # named here only decide who owns the reboot from now on (their *_reboot variable);
  # they do not activate the kernel already sitting in /boot.
  ["SYS-11"]="updates,patching|linux_dnf_automatic_rhel9|linux_unattended_upgrades_ubuntu|Reboot policy (does NOT activate the installed kernel)"
  ["AUTH-01"]="auth,users|linux_user_management_rhel9|linux_user_management_ubuntu|User management hardening"
  ["AUTH-02"]="auth,users|linux_user_management_rhel9|linux_user_management_ubuntu|User management hardening"
  # AUTH-03: PASS_MAX_DAYS in /etc/login.defs is set by user_management, not authselect
  ["AUTH-03"]="auth,users|linux_user_management_rhel9|linux_user_management_ubuntu|Password expiry policy (login.defs)"
  ["AUTH-04"]="auth,pam|linux_authselect_rhel9|linux_authselect_ubuntu|PAM / password complexity"
  ["AUTH-05"]="auth,users|linux_user_management_rhel9|linux_user_management_ubuntu|Sudo / user access controls"
  ["AUTH-06"]="auth,users|linux_user_management_rhel9|linux_user_management_ubuntu|Inactive account cleanup"
  ["AUTH-07"]="auth,users|linux_user_management_rhel9|linux_user_management_ubuntu|Password minimum age (login.defs)"
  ["AUTH-08"]="auth,users|linux_user_management_rhel9|linux_user_management_ubuntu|Password warning age (login.defs)"
  ["AUTH-09"]="auth,pam|linux_authselect_rhel9|linux_authselect_ubuntu|Account lockout (faillock)"
  ["AUTH-10"]="auth,users|linux_user_management_rhel9|linux_user_management_ubuntu|Shell timeout (TMOUT)"
  ["AUTH-11"]="auth,users|linux_user_management_rhel9|linux_user_management_ubuntu|UID 0 account audit"
  ["AUTH-12"]="filesystem,permissions|linux_file_permissions_rhel9|linux_file_permissions_ubuntu|/etc/group permissions"
  ["AUTH-13"]="filesystem,permissions|linux_file_permissions_rhel9|linux_file_permissions_ubuntu|/etc/gshadow permissions"
  ["AUTH-14"]="auth,pam|linux_authselect_rhel9|linux_authselect_ubuntu|Password complexity (pwquality)"
  ["AUTH-15"]="sudo|linux_sudo_hardening_rhel9|linux_sudo_hardening_ubuntu|sudo use_pty enforcement"
  ["AUTH-16"]="sudo|linux_sudo_hardening_rhel9|linux_sudo_hardening_ubuntu|sudo logfile configuration"
  ["SSH-01"]="ssh|linux_ssh_hardening_rhel9|linux_ssh_hardening_ubuntu|SSH server hardening"
  ["SSH-02"]="ssh|linux_ssh_hardening_rhel9|linux_ssh_hardening_ubuntu|SSH server hardening"
  ["SSH-03"]="ssh|linux_ssh_hardening_rhel9|linux_ssh_hardening_ubuntu|SSH server hardening"
  ["SSH-04"]="ssh|linux_ssh_hardening_rhel9|linux_ssh_hardening_ubuntu|SSH server hardening"
  ["SSH-05"]="ssh|linux_ssh_hardening_rhel9|linux_ssh_hardening_ubuntu|SSH server hardening"
  ["SSH-06"]="ssh|linux_ssh_hardening_rhel9|linux_ssh_hardening_ubuntu|SSH server hardening"
  ["SSH-07"]="ssh|linux_ssh_hardening_rhel9|linux_ssh_hardening_ubuntu|SSH server hardening"
  ["SSH-08"]="ssh|linux_ssh_hardening_rhel9|linux_ssh_hardening_ubuntu|SSH server hardening"
  ["SSH-09"]="ssh|linux_ssh_hardening_rhel9|linux_ssh_hardening_ubuntu|SSH server hardening"
  ["SSH-10"]="ssh,banner|linux_ssh_hardening_rhel9|linux_ssh_hardening_ubuntu|SSH legal banner"
  ["SSH-11"]="ssh|linux_ssh_hardening_rhel9|linux_ssh_hardening_ubuntu|SSH session timeout"
  ["SSH-12"]="ssh|linux_ssh_hardening_rhel9|linux_ssh_hardening_ubuntu|SSH server hardening"
  ["SSH-13"]="ssh,crypto|linux_ssh_hardening_rhel9|linux_ssh_hardening_ubuntu|SSH cipher hardening"
  ["SSH-14"]="ssh,filesystem|linux_ssh_hardening_rhel9|linux_ssh_hardening_ubuntu|sshd_config permissions"
  ["SSH-15"]="ssh|linux_ssh_hardening_rhel9|linux_ssh_hardening_ubuntu|SSH server hardening"
  ["FS-01"]="filesystem,permissions|linux_file_permissions_rhel9|linux_file_permissions_ubuntu|File permissions hardening"
  ["FS-02"]="filesystem,permissions|linux_file_permissions_rhel9|linux_file_permissions_ubuntu|File permissions hardening"
  ["FS-03"]="filesystem,permissions|linux_file_permissions_rhel9|linux_file_permissions_ubuntu|File permissions hardening"
  ["FS-04"]="filesystem,permissions|linux_file_permissions_rhel9|linux_file_permissions_ubuntu|File permissions hardening"
  ["FS-05"]="filesystem,permissions|linux_file_permissions_rhel9|linux_file_permissions_ubuntu|SUID binary audit"
  ["FS-06"]="filesystem,mounts|linux_tmp_mounts_rhel9|linux_tmp_mounts_ubuntu|/tmp mount hardening"
  ["FS-07"]="filesystem,permissions|linux_file_permissions_rhel9|linux_file_permissions_ubuntu|Sticky bit on world-writable dirs"
  ["FS-08"]="filesystem,permissions|linux_file_permissions_rhel9|linux_file_permissions_ubuntu|/etc/crontab permissions"
  ["FS-09"]="filesystem,mounts|linux_tmp_mounts_rhel9|linux_tmp_mounts_ubuntu|/var/tmp mount hardening"
  ["FS-10"]="filesystem,permissions|linux_file_permissions_rhel9|linux_file_permissions_ubuntu|Unowned files audit"
  ["FS-11"]="filesystem,permissions|linux_file_permissions_rhel9|linux_file_permissions_ubuntu|/var/log permissions"
  ["FS-12"]="ssh|linux_ssh_hardening_rhel9|linux_ssh_hardening_ubuntu|SSH host key permissions"
  ["NET-01"]="firewall|linux_firewalld_rhel9|linux_firewall_ubuntu|Firewall configuration"
  ["NET-02"]="network,sysctl|linux_ip_forwarding_rhel9|linux_ip_forwarding_ubuntu|IP forwarding restriction"
  # NET-03: accept_redirects is set by ip_forwarding role, not kernel_hardening
  ["NET-03"]="network,sysctl|linux_ip_forwarding_rhel9|linux_ip_forwarding_ubuntu|ICMP redirect hardening"
  ["NET-04"]="network,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|TCP SYN cookie hardening"
  ["NET-05"]="services|linux_disable_unnecessary_services_rhel9|linux_disable_unnecessary_services_ubuntu|Disable dangerous services"
  ["NET-06"]="network,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|Source routing disabled"
  ["NET-07"]="network,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|Send redirects disabled"
  ["NET-08"]="network,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|Martian packet logging"
  ["NET-09"]="network,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|Reverse path filtering"
  ["NET-10"]="network,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|IPv6 RA disabled"
  ["NET-11"]="network,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|ICMP broadcast protection"
  ["NET-12"]="network,wireless|linux_wireless_rhel9|linux_wireless_ubuntu|Wireless interfaces disabled"
  ["NET-13"]="network,ipv6|linux_ipv6_rhel9|linux_ipv6_ubuntu|IPv6 disabled (CIS 3.3.1)"
  ["LOG-01"]="audit,logging|linux_auditing_rhel9|linux_auditing_ubuntu|auditd configuration"
  ["LOG-02"]="audit,logging|linux_auditing_rhel9|linux_auditing_ubuntu|System logging (rsyslog)"
  # LOG-03: logrotate is not managed by any hardening role — no Ansible remediation
  ["LOG-04"]="audit,logging|linux_auditing_rhel9|linux_auditing_ubuntu|Audit rules configuration"
  ["LOG-05"]="audit,logging|linux_auditing_rhel9|linux_auditing_ubuntu|Audit log size configuration"
  ["LOG-06"]="audit,logging|linux_auditing_rhel9|linux_auditing_ubuntu|Kernel audit boot parameter"
  ["LOG-07"]="audit,logging,journald|linux_journald_rhel9|linux_journald_ubuntu|journald persistent storage (/var/log/journal)"
  # LOG-08: remote syslog not managed by any hardening role — no Ansible remediation
  ["LOG-09"]="audit,logging,journald|linux_journald_rhel9|linux_journald_ubuntu|journald Storage=persistent config"
  ["LOG-10"]="audit,logging,journald|linux_journald_rhel9|linux_journald_ubuntu|journald rate limiting config"
  ["INT-01"]="integrity,aide|linux_aide_rhel9|linux_aide_ubuntu|AIDE file integrity monitor"
  # INT-02: rkhunter/chkrootkit not managed by any role — no Ansible remediation
  # INT-03: suspicious cron requires manual investigation — no Ansible remediation
  # INT-04: open port count is informational / always WARN — no Ansible remediation
  ["INT-05"]="updates,patching|linux_dnf_automatic_rhel9|linux_unattended_upgrades_ubuntu|Package GPG signature check"
  ["INT-06"]="fail2ban|linux_fail2ban_rhel9|linux_fail2ban_ubuntu|Brute-force protection (fail2ban)"
  ["INT-07"]="integrity,aide|linux_aide_rhel9|linux_aide_ubuntu|AIDE database initialization"
  ["INT-08"]="filesystem,permissions|linux_file_permissions_rhel9|linux_file_permissions_ubuntu|Cron directory permissions"
  ["COMP-01"]="banner|linux_login_banner_rhel9|linux_login_banner_ubuntu|Legal login banner"
  ["COMP-02"]="filesystem,mounts|linux_tmp_mounts_rhel9|linux_tmp_mounts_ubuntu|/tmp dedicated partition"
  # COMP-03: /home partition layout — cannot be changed by Ansible post-install
  # COMP-04: /var partition layout — cannot be changed by Ansible post-install
  ["COMP-05"]="auth,users|linux_user_management_rhel9|linux_user_management_ubuntu|System umask hardening"
  ["COMP-06"]="kernel,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|ASLR kernel hardening"
  ["COMP-07"]="kernel,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|Kernel pointer restriction"
  ["COMP-08"]="kernel,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|dmesg restriction"
  ["COMP-09"]="kernel,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|ptrace scope restriction"
  ["COMP-10"]="kernel,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|USB storage module blacklist"
  ["COMP-11"]="cron|linux_cron_hardening_rhel9|linux_cron_hardening_ubuntu|Cron service enabled"
  ["COMP-12"]="cron|linux_cron_hardening_rhel9|linux_cron_hardening_ubuntu|cron/at allow-list enforcement"

  # ── Kernel attack surface (KRN-01..KRN-12) ─────────────────────────────────
  # All served by the same role and the same tag, because they are all sysctls
  # in one drop-in file. Without these entries a KRN warning appeared in the
  # report with no way into the remediation plan: the renderer skips any id it
  # cannot map, silently.
  #
  # The role applies the safe tier by default. KRN-01, KRN-03 and KRN-05 break
  # real workloads, so their toggles default to false and the operator opts in
  # deliberately; the description says so rather than leaving them to find out.
  ["KRN-01"]="kernel,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|Unprivileged user namespaces (opt-in: linux_kernel_restrict_userns=true, breaks rootless containers)"
  ["KRN-02"]="kernel,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|Unprivileged eBPF disabled"
  ["KRN-03"]="kernel,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|io_uring restricted (opt-in: linux_kernel_restrict_io_uring=true)"
  ["KRN-04"]="kernel,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|Unprivileged userfaultfd disabled"
  ["KRN-05"]="kernel,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|Module loading lockdown (opt-in: linux_kernel_lock_modules=true, irreversible until reboot)"
  ["KRN-06"]="kernel,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|kexec disabled"
  ["KRN-07"]="kernel,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|TTY line discipline autoload disabled"
  # KRN-08 lockdown is a boot parameter or Secure Boot, not a sysctl. No role.
  ["KRN-09"]="kernel,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|BPF JIT hardening"
  ["KRN-10"]="kernel,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|SysRq restricted"
  ["KRN-11"]="kernel,sysctl|linux_kernel_hardening_rhel9|linux_kernel_hardening_ubuntu|Exotic filesystem modules blacklisted"
  # KRN-12 is the summary of the four above it, not a setting of its own.
)

# ── Reachability wave ────────────────────────────────────────────────────────
# Which question a finding answers: what an attacker reaches with no account,
# what turns an account into root, what would have stopped you noticing, and
# hygiene. This is the ordering `aartool advise` prints and the thing that makes
# the tool different from a flat severity list.
#
# It is emitted into the JSON for the same reason remediation_tags is: a
# consumer that wants the ordering should not have to reimplement it. The
# dashboard kept its own copy in JS and advise has one in shell; that is two
# places that must agree, which is the drift that has bitten this repository
# three times. scripts/tests/test_waves.sh asserts this function and
# _advise_wave give the same answer for every ID the baseline can emit, so a new
# check family cannot be classified differently by the two of them.
_wave_of() {
  case "$1" in
    SSH-*|NET-*)               printf 1 ;;
    KRN-*|AUTH-*|SYS-04|SYS-05|SYS-07|SYS-08|SYS-09|SYS-10|FS-01|FS-02|FS-03|FS-05|FS-06|FS-09)
                               printf 2 ;;
    LOG-*|INT-*|AUD-*)         printf 3 ;;
    SYS-02|SYS-03|SYS-11)      printf 1 ;;   # unpatched is reachable from the network
    *)                         printf 4 ;;
  esac
}

# =============================================================================
#  REMOTE SCAN ENGINE
#  When --host / --host-file / --inventory is given, SSH into each target,
#  copy the script, run it, collect HTML/JSON, then remove it.
# =============================================================================

# ── Parse Ansible INI/YAML inventory into a plain IP/host list ───────────────
_parse_inventory() {
  local inv="$1"
  # Strip comments, blank lines, group headers, vars lines, [*:vars] sections
  # Works for simple INI inventories (the common case)
  grep -vE '^\s*(#|$|\[.*:vars\]|\[.*:children\])' "$inv" 2>/dev/null \
    | grep -vE '^\s*\[' \
    | grep -vE '^\s*[a-zA-Z_]+=.*' \
    | awk '{print $1}' \
    | grep -vE '^$' \
    | sort -u
}

# ── Build the host list from all sources ─────────────────────────────────────
_build_host_list() {
  local -a hosts=()
  [[ -n "$REMOTE_HOST" ]] && hosts+=("$REMOTE_HOST")
  if [[ -n "$REMOTE_HOST_FILE" ]]; then
    while IFS= read -r line; do
      line="${line%%#*}"; line="${line// /}"   # strip comments and spaces
      [[ -n "$line" ]] && hosts+=("$line")
    done < "$REMOTE_HOST_FILE"
  fi
  if [[ -n "$ANSIBLE_INVENTORY" ]]; then
    while IFS= read -r h; do
      [[ -n "$h" ]] && hosts+=("$h")
    done < <(_parse_inventory "$ANSIBLE_INVENTORY")
  fi
  # deduplicate preserving order
  local seen=(); local out=()
  for h in "${hosts[@]}"; do
    [[ " ${seen[*]} " == *" $h "* ]] && continue
    seen+=("$h"); out+=("$h")
  done
  printf '%s\n' "${out[@]}"
}

# Shared directory for the ssh control sockets, private to this run. Removed on
# exit along with any master connections still persisting, so a scan leaves no
# open sessions behind on the operator's machine.
_CYBERAAR_SSH_CTL_DIR=""
_cyberaar_ssh_ctl_init() {
  _CYBERAAR_SSH_CTL_DIR="$(mktemp -d -t aartool-ssh-XXXXXX 2>/dev/null)" || _CYBERAAR_SSH_CTL_DIR=""
  [[ -n "$_CYBERAAR_SSH_CTL_DIR" ]] && chmod 700 "$_CYBERAAR_SSH_CTL_DIR" 2>/dev/null || true
}
_cyberaar_ssh_ctl_cleanup() {
  [[ -n "$_CYBERAAR_SSH_CTL_DIR" && -d "$_CYBERAAR_SSH_CTL_DIR" ]] || return 0
  local sock
  for sock in "$_CYBERAAR_SSH_CTL_DIR"/*; do
    [[ -S "$sock" ]] && ssh -o ControlPath="$sock" -O exit placeholder &>/dev/null || true
  done
  rm -rf "$_CYBERAAR_SSH_CTL_DIR"
  _CYBERAAR_SSH_CTL_DIR=""
}
trap _cyberaar_ssh_ctl_cleanup EXIT INT TERM

# ── Run scan on a single remote host via SSH ──────────────────────────────────
#
# TRANSPORT: ssh with the file on stdin, not scp.
#
# scp in OpenSSH 9 and later speaks the SFTP protocol by default, and a hardened
# host frequently has no sftp subsystem at all: removing it is a normal CIS and
# STIG hardening step, and this toolkit's own ssh role is the kind of thing that
# does it. The result was that the remote scan failed on exactly the hosts most
# likely to be running a security tool, with
#
#     scp: Connection closed
#
# swallowed by 2>/dev/null, then "bash: /tmp/.aartool-baseline-xxx.sh: No such
# file or directory" from the run that followed, and a cheerful "1 succeeded" at
# the end. Found on a live bastion, not in review.
#
# Piping over an ssh session needs no subsystem, no scp binary and no sftp, so it
# works wherever an interactive command works. `cat > file` is also the only
# transport available when a host allows command execution but no file transfer.
#
# EVERY STEP IS CHECKED. The previous version returned success unless the initial
# connectivity probe failed, so a scan that copied nothing, ran nothing and
# fetched nothing still counted as a success in the fleet summary. A scanner that
# cannot tell you it failed is worse than one that is simply absent.
_remote_scan() {
  local host="$1"
  local html_out="$2"
  local json_out="$3"

  local ssh_opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes)
  if [[ -n "$REMOTE_KEY" ]]; then
    # IdentitiesOnly matters more than it looks. Without it ssh offers every key
    # in the agent before the one that was named, each offer counts against
    # sshd's MaxAuthTries, and on a host running fail2ban a fleet scan from a
    # workstation with several keys loaded gets that workstation banned across
    # the estate. If the operator named a key, use that key and nothing else.
    ssh_opts+=(-i "$REMOTE_KEY" -o IdentitiesOnly=yes)
  fi

  # ── Bastion ────────────────────────────────────────────────────────────────
  # -J looks like the obvious way to do this and quietly does not work here.
  # ssh does NOT pass the outer connection's options to the jump hop: not -i,
  # not StrictHostKeyChecking, not BatchMode. So `--ssh-opt '-J admin@bastion'`
  # alongside `--ssh-key ~/.ssh/estate` authenticates hop 2 with the named key
  # and hop 1 with whatever the defaults happen to be, which on a machine with
  # no agent and no known_hosts entry fails as
  #
  #     ssh_askpass: exec(/usr/bin/ssh-askpass): No such file or directory
  #     Host key verification failed.
  #
  # ...a message about the bastion that never names the bastion. This is the
  # normal shape of a real estate, not an edge case: private nodes with no
  # public address, reached through one jump host, with a dedicated key.
  #
  # --jump therefore builds the ProxyCommand explicitly and carries the same
  # key and the same connection options onto hop 1.
  if [[ -n "${REMOTE_JUMP:-}" ]]; then
    local _jhost="$REMOTE_JUMP" _jport=22
    if [[ "$_jhost" == *:* ]]; then _jport="${_jhost##*:}"; _jhost="${_jhost%:*}"; fi
    local _pc="ssh -W %h:%p -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes -p ${_jport}"
    [[ -n "$REMOTE_KEY" ]] && _pc+=" -o IdentitiesOnly=yes -i $(printf '%q' "$REMOTE_KEY")"
    _pc+=" $(printf '%q' "$_jhost")"
    ssh_opts+=(-o "ProxyCommand=${_pc}")
  fi

  # One TCP connection per host, reused for all seven operations below.
  #
  # A scan opens a connection to probe, to push the script, to check it landed,
  # to run it, to fetch each report and to clean up. Without multiplexing that is
  # seven full handshakes per host, so a fifty-host fleet performs three hundred
  # and fifty. That is slow, it pushes against sshd's MaxStartups (10:30:100 by
  # default, past which it refuses roughly a third of new connections at random),
  # and on a host running fail2ban it looks like exactly the thing fail2ban is
  # there to stop.
  #
  # Found the hard way: scanning one host repeatedly during development got this
  # workstation banned by the estate's own fail2ban.
  #
  # %C hashes host, port, user and local host into a short filename, which keeps
  # the socket path under the 104-byte sun_path limit that longer schemes hit.
  if [[ -n "$_CYBERAAR_SSH_CTL_DIR" ]]; then
    ssh_opts+=(-o ControlMaster=auto -o "ControlPath=${_CYBERAAR_SSH_CTL_DIR}/%C" -o ControlPersist=30s)
  fi
  # Anything the operator passed with --ssh-opt, most usefully -J for a bastion.
  # Estates that matter put their hosts behind a jump host, and without this the
  # scanner could only reach machines that were already reachable directly.
  local _o
  for _o in ${REMOTE_SSH_OPTS[@]+"${REMOTE_SSH_OPTS[@]}"}; do ssh_opts+=("$_o"); done

  local target="${REMOTE_USER}@${host}"
  local _rand
  _rand=$(openssl rand -hex 8 2>/dev/null || tr -dc 'a-f0-9' < /dev/urandom 2>/dev/null | head -c 16)
  local remote_script="/tmp/.aartool-baseline-${_rand}.sh"
  local remote_html="/tmp/.aartool-report-${_rand}.html"
  local remote_json="/tmp/.aartool-report-${_rand}.json"

  printf "\n${BOLD}${CYAN}━━━  Remote scan: %s  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n" "$host"

  # ── 1. Reachability ────────────────────────────────────────────────────────
  local _probe
  if ! _probe=$(ssh "${ssh_opts[@]}" "$target" "echo ok" 2>&1); then
    printf "  ${RED}❌  SSH connection failed: %s@%s${NC}\n" "$REMOTE_USER" "$host"
    printf "     %s\n" "${_probe%%$'\n'*}"
    printf "     Check: host reachable, user exists, key auth works without a passphrase.\n"
    printf "     Behind a bastion? Pass it through: --ssh-opt '-J user@bastion'\n"
    return 1
  fi

  # ── 2. Push the script ─────────────────────────────────────────────────────
  local _err
  if ! _err=$(ssh "${ssh_opts[@]}" "$target" \
        "cat > '${remote_script}' && chmod 700 '${remote_script}'" < "$SCRIPT_PATH" 2>&1); then
    printf "  ${RED}❌  Could not copy the audit script to %s${NC}\n" "$host"
    printf "     %s\n" "${_err%%$'\n'*}"
    printf "     The remote /tmp may be full, noexec, or read-only.\n"
    return 1
  fi

  # Landed and non-empty. A truncated copy runs and produces nonsense.
  local _size
  _size=$(ssh "${ssh_opts[@]}" "$target" "wc -c < '${remote_script}' 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')
  if [[ -z "$_size" || "$_size" -lt 1000 ]]; then
    printf "  ${RED}❌  The audit script did not arrive intact on %s (%s bytes)${NC}\n" "$host" "${_size:-0}"
    ssh "${ssh_opts[@]}" "$target" "rm -f '${remote_script}'" &>/dev/null || true
    return 1
  fi

  # ── 3. Run it ──────────────────────────────────────────────────────────────
  local rflags=""
  [[ -n "$html_out" ]] && rflags="$rflags --html-out ${remote_html}"
  [[ -n "$json_out" ]] && rflags="$rflags --json-out ${remote_json}"

  local _rc=0
  if [[ "$REMOTE_USER" == "root" ]]; then
    ssh "${ssh_opts[@]}" "$target" "bash '${remote_script}'${rflags:+ $rflags}" || _rc=$?
  else
    # -n so the remote sudo cannot silently wait for a password nobody can type.
    ssh "${ssh_opts[@]}" "$target" "sudo -n bash '${remote_script}'${rflags:+ $rflags}" || _rc=$?
  fi
  if [[ "$_rc" -ne 0 ]]; then
    printf "  ${RED}❌  The audit did not complete on %s (exit %d)${NC}\n" "$host" "$_rc"
    printf "     If this is a sudo prompt: %s needs passwordless sudo, or scan as root.\n" "$REMOTE_USER"
    ssh "${ssh_opts[@]}" "$target" "rm -f '${remote_script}' '${remote_html}' '${remote_json}'" &>/dev/null || true
    return 1
  fi

  # ── 4. Fetch the reports ───────────────────────────────────────────────────
  # Same reasoning as the push: cat over ssh needs no sftp. An empty file counts
  # as a failure, because a zero-byte report reads as a successful scan of a
  # machine with no findings.
  #
  # Read back through sudo when the scan ran through sudo. The audit runs as root
  # and writes its reports as root, so an unprivileged login cannot read the
  # files it just asked for. That failed silently on a live host: the audit
  # completed, printed its findings to the terminal, and then could not retrieve
  # a single one of them.
  local _cat="cat"
  [[ "$REMOTE_USER" != "root" ]] && _cat="sudo -n cat"
  local fetch_failed=0
  if [[ -n "$html_out" ]]; then
    if ssh "${ssh_opts[@]}" "$target" "$_cat '${remote_html}'" > "$html_out" 2>/dev/null && [[ -s "$html_out" ]]; then
      printf "  🌐 HTML fetched → %s\n" "$html_out"
    else
      rm -f "$html_out"
      printf "  ${YELLOW}⚠️   Could not fetch the HTML report from %s${NC}\n" "$host"
      fetch_failed=1
    fi
  fi
  if [[ -n "$json_out" ]]; then
    if ssh "${ssh_opts[@]}" "$target" "$_cat '${remote_json}'" > "$json_out" 2>/dev/null && [[ -s "$json_out" ]]; then
      printf "  📄 JSON fetched → %s\n" "$json_out"
    else
      rm -f "$json_out"
      printf "  ${YELLOW}⚠️   Could not fetch the JSON report from %s${NC}\n" "$host"
      fetch_failed=1
    fi
  fi

  # ── 5. Clean up after ourselves ────────────────────────────────────────────
  # Root-owned reports need root to remove. Leaving an audit of the machine in
  # world-readable /tmp is not acceptable housekeeping for a security tool.
  local _rm="rm -f"
  [[ "$REMOTE_USER" != "root" ]] && _rm="sudo -n rm -f"
  ssh "${ssh_opts[@]}" "$target" "$_rm '${remote_script}' '${remote_html}' '${remote_json}'" &>/dev/null || true

  [[ "$fetch_failed" -eq 0 ]] || return 1
  return 0
}

# ── Fleet scan dispatcher ─────────────────────────────────────────────────────
FLEET_HOSTS=()
if [[ -n "$REMOTE_HOST" || -n "$REMOTE_HOST_FILE" || -n "$ANSIBLE_INVENTORY" ]]; then
  while IFS= read -r h; do
    [[ -n "$h" ]] && FLEET_HOSTS+=("$h")
  done < <(_build_host_list)

  if [[ ${#FLEET_HOSTS[@]} -eq 0 ]]; then
    printf "${RED}❌  No hosts found from the specified source(s).${NC}\n"
    exit 1
  fi

  printf "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}\n"
  printf "${BOLD}${CYAN}║  aartool fleet scan: %d host(s)%-28s║${NC}\n" "${#FLEET_HOSTS[@]}" ""
  printf "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"

  _cyberaar_ssh_ctl_init
  FLEET_OK=0; FLEET_FAIL=0
  for host in "${FLEET_HOSTS[@]}"; do
    # Build output paths for this host
    local_html=""; local_json=""
    HOST_SLUG=$(echo "$host" | tr -cd 'a-zA-Z0-9.-')
    DATESTR=$(date '+%Y%m%d-%H%M%S')

    if [[ -n "$OUTPUT_DIR" ]]; then
      local_html="${OUTPUT_DIR}/aartool-${HOST_SLUG}-${DATESTR}.html"
      local_json="${OUTPUT_DIR}/aartool-${HOST_SLUG}-${DATESTR}.json"
    elif [[ -n "$HTML_OUT" ]]; then
      local_html="${HTML_OUT%.html}-${HOST_SLUG}.html"
    elif [[ -n "$JSON_OUT" ]]; then
      local_json="${JSON_OUT%.json}-${HOST_SLUG}.json"
    fi

    if _remote_scan "$host" "$local_html" "$local_json"; then
      ((FLEET_OK++))
    else
      ((FLEET_FAIL++))
    fi
  done

  printf "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  printf "${BOLD}  Fleet scan complete:${NC} ✅ %d succeeded   ❌ %d failed   (Total: %d)\n" \
    "$FLEET_OK" "$FLEET_FAIL" "${#FLEET_HOSTS[@]}"
  printf "  📁 Reports in: %s\n" "${OUTPUT_DIR:-current directory}"
  printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  printf "  aartool  https://github.com/cyberaar/aartool\n\n"
  exit 0
fi

# ─── COLORS ──────────────────────────────────────────────────────────────────
# Only when stdout is a terminal. These used to be unconditional, so
# `aartool inspect > audit.txt` wrote 134 lines of raw \033[ escapes into the
# file, and the `aartool diff ... || mail` pattern the README suggests mailed
# escape sequences to whoever was on call.
#
# NO_COLOR is honoured because it is the convention every other CLI follows
# (no-color.org): set to anything, colour is off. FORCE_COLOR overrides in the
# other direction, for piping into `less -R` on purpose.
if [[ -n "${FORCE_COLOR:-}" ]] || { [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; }; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
  DIM='\033[2m'   # column headers and IDs: present, but not competing with the result
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''; DIM=''
fi

# ─── GLOBALS ─────────────────────────────────────────────────────────────────
PASS=0; WARN=0; FAIL=0

# Parallel result arrays — populated by add_result(), consumed by renderers
RESULT_CATEGORY=()
RESULT_STATUS=()
RESULT_ID=()
RESULT_NAME_EN=()
RESULT_NAME_FR=()
RESULT_DETAIL=()
RESULT_REMEDIATION=()

# Tracks check IDs that need remediation (for Ansible plan)
FAIL_IDS=()
WARN_IDS=()

# ─── HELPERS ─────────────────────────────────────────────────────────────────

# A fixed-width rule with a column header, so a section reads as a table rather
# than as a stream. The old version appended a fixed-length bar to a
# variable-length title, so every section ended at a different column.
# The table has to fit the terminal it is printed in. This was a hard-coded 86,
# which is wider than the 80 columns a default terminal gives you, so every row
# wrapped and the table stopped being a table. Worse, the section rules were
# drawn at 86 while rows ran to 156 characters, because the DETAIL column had no
# bound at all: the rules ended 70 columns short of the content they were meant
# to be ruling off.
#
# tput needs a terminal; when there is none (a pipe, a file, CI) 100 is a
# sensible fixed width for a file someone will open later.
if [[ -t 1 ]]; then
  REPORT_WIDTH=$(tput cols 2>/dev/null || echo 86)
else
  REPORT_WIDTH=100
fi
[[ "$REPORT_WIDTH" =~ ^[0-9]+$ ]] || REPORT_WIDTH=86
(( REPORT_WIDTH < 60 ))  && REPORT_WIDTH=60    # below this nothing helps
(( REPORT_WIDTH > 140 )) && REPORT_WIDTH=140   # long lines are hard to track back

# Column widths derived from it once, so the header rule and the rows cannot
# disagree. 2 indent + 6 status + 1 + 9 id + 1 + name + 1 + detail.
COL_NAME=42
COL_DETAIL=$(( REPORT_WIDTH - 2 - 6 - 1 - 9 - 1 - COL_NAME - 1 ))
if (( COL_DETAIL < 18 )); then                 # narrow terminal: give up name width first
  COL_NAME=$(( COL_NAME - (18 - COL_DETAIL) ))
  (( COL_NAME < 20 )) && COL_NAME=20
  COL_DETAIL=$(( REPORT_WIDTH - 2 - 6 - 1 - 9 - 1 - COL_NAME - 1 ))
  (( COL_DETAIL < 8 )) && COL_DETAIL=8
fi
# A horizontal rule at the current table width. Every renderer that wants one
# calls this; literal runs of ━ were baked at 61 characters while the table was
# 86 and the rows were 156, so nothing lined up with anything.
rule() {
  local ch="${1:-━}" n="${2:-$REPORT_WIDTH}" pad
  # NOT `tr`. tr translates BYTES, and ━ is three of them (e2 94 81), so
  # `tr ' ' '━'` mapped every space to 0xe2 and produced a run of invalid UTF-8
  # where the summary rule should be. On a terminal that is a line of replacement
  # characters, which is how the score box lost its banner in 3.5.0.
  #
  # Bash parameter substitution replaces strings, not bytes, so it is correct for
  # any character passed in here.
  printf -v pad '%*s' "$n" ''
  printf '%s' "${pad// /$ch}"
}

section() {
  local title="$1" pad
  # Section titles used to be "1. SYSTEM & OS / Systeme et OS" and this stripped
  # the half after the slash. No caller passes one any more: the output is
  # English throughout. Kept because it costs nothing and a bilingual title
  # would otherwise print raw, but it is no longer doing any work.
  title="${title%% / *}"
  pad=$(( REPORT_WIDTH - ${#title} - 6 ))
  (( pad < 3 )) && pad=3
  printf "\n${BOLD}${CYAN}── %s %s${NC}\n" "$title" "$(printf '─%.0s' $(seq 1 "$pad"))"
  printf "${DIM}  %-6s %-9s %-*s %s${NC}\n" "STATUS" "ID" "$COL_NAME" "CHECK" "DETAIL"
}

# Encode special HTML characters to prevent XSS in report output
json_escape() {
  # Backslash first, then the quote, then control characters that would make the
  # document invalid. No & involved, so patsub_replacement does not apply here,
  # but this lives next to html_escape so both are found and reviewed together.
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  s="${s//$'\t'/ }"
  printf '%s' "$s"
}

html_escape() {
  # The backslashes before & are required, not stylistic. Bash 5.2 added the
  # patsub_replacement option, on by default, which makes an unescaped & in the
  # replacement expand to the matched text exactly as sed does. Without them
  # "${s//</&lt;}" yields "<lt;" and the function silently stops escaping:
  # every value taken from the audited machine then lands raw in the report.
  # \& is literal in every bash version, so this stays correct on both sides of
  # 5.2. Covered by tests/test_html_escape.sh.
  local s="$1"
  s="${s//&/\&amp;}"
  s="${s//</\&lt;}"
  s="${s//>/\&gt;}"
  s="${s//\"/\&quot;}"
  s="${s//\'/\&#39;}"
  printf '%s' "$s"
}

# add_result CATEGORY STATUS ID NAME_EN NAME_FR DETAIL REMEDIATION
#
# NAME_FR is carried and rendered nowhere. That is deliberate, not an oversight:
# every output surface (terminal, HTML, JSON, dashboard) is English, and the
# report used to declare lang="fr" while printing English names either side of a
# French score label, which read as a bug rather than as a translation.
#
# The French names are kept because they are complete and correct, one for every
# branch of every check, properly accented. That is the expensive half of a
# French mode and it already exists; deleting it to save a bash array would mean
# rebuilding it later. scripts/tests/test_french_names.sh keeps it complete, so
# a French mode stays a switch rather than a project.
#
# The last parameter was documented as REMEDIATION_FR and has not been French
# for a long time; remediation text is English like everything else.
add_result() {
  local category="$1" status="$2" id="$3" name_en="$4" name_fr="$5"
  local detail="${6:-}" remediation="${7:-}"

  local color
  case "$status" in
    PASS) ((PASS++)); color=$GREEN ;;
    WARN) ((WARN++)); color=$YELLOW; WARN_IDS+=("$id") ;;
    FAIL) ((FAIL++)); color=$RED;    FAIL_IDS+=("$id") ;;
  esac

  # Terminal: one aligned row per check, streamed as it runs.
  #
  # No emoji in this column. ✅ is one cell wide, ⚠️ is two plus a variation
  # selector, and ❌ is two: mixing them means no two rows line up, which is
  # most of why 109 results read as a wall. The status word carries the colour
  # and aligns.
  #
  # The ID is printed because `aartool explain SSH-01` needs it, and until now
  # the only place to find it was the JSON report.
  # Truncate to the derived widths rather than letting DETAIL run to whatever
  # length the machine happened to produce. An ellipsis is honest: the full text
  # is in the JSON and the HTML, and `aartool explain <ID>` prints all of it.
  local _n="$name_en" _d="$detail"
  (( ${#_n} > COL_NAME ))   && _n="${_n:0:$((COL_NAME-1))}…"
  (( ${#_d} > COL_DETAIL )) && _d="${_d:0:$((COL_DETAIL-1))}…"
  printf "  ${color}%-6s${NC} ${DIM}%-9s${NC} %-*s %s\n" \
    "$status" "$id" "$COL_NAME" "$_n" "$_d"

  # Per-check hints are off by default: they doubled the length of every run,
  # and `aartool explain <ID>` gives the same thing in full, plus what closing
  # the finding costs. AARTOOL_HINTS=1, or `aartool inspect --hints`.
  if [[ "${AARTOOL_HINTS:-0}" == "1" && "$status" != "PASS" && -n "$remediation" ]]; then
    printf "         ${CYAN}hint: %s${NC}\n" "$remediation"
  fi

  # Append to parallel result arrays (renderers iterate these at end of run)
  RESULT_CATEGORY+=("$category")
  RESULT_STATUS+=("$status")
  RESULT_ID+=("$id")
  RESULT_NAME_EN+=("$name_en")
  RESULT_NAME_FR+=("$name_fr")
  RESULT_DETAIL+=("$detail")
  RESULT_REMEDIATION+=("$remediation")
}

cmd_exists() { command -v "$1" &>/dev/null; }
svc_active() { systemctl is-active --quiet "$1" 2>/dev/null; }
get_ssh()    { grep -iE "^\s*${1}\s" /etc/ssh/sshd_config 2>/dev/null | head -1 | awk '{print $2}'; }

_checks_system() {
# =============================================================================
#  1. SYSTEM & OS
# =============================================================================
section "1. SYSTEM & OS"

# SYS-01 Distribution and what is available for it
#
# Two claims, kept apart. The audit reads sysctls, /proc, /etc and systemd, so it
# runs on anything with a Linux kernel. The Ansible hardening roles are written
# for two families and CI-tested on two images. The old check conflated them and
# told anyone outside six names to change distribution, which helps nobody.
_SYS_FAM="$(distro_family)"
if distro_roles_available; then
  add_result "System" "PASS" "SYS-01" "Distribution supported" "Distribution supportée" \
    "$(distro_pretty), family: $_SYS_FAM, hardening roles available" ""
elif [[ "$_SYS_FAM" == "unknown" ]]; then
  add_result "System" "WARN" "SYS-01" "Distribution not identified" "Distribution non identifiée" \
    "$(distro_pretty): audit still valid, hardening roles unavailable" \
    "The audit still holds: it reads /proc, /etc and systemd, which do not depend on the distribution. The hardening roles cover the RHEL and Debian families (tested on $(distro_roles_tested))."
else
  add_result "System" "WARN" "SYS-01" "Audit-only distribution" "Distribution en audit seul" \
    "$(distro_pretty), family: $_SYS_FAM, audit valid, no hardening roles" \
    "The audit and 'aartool surface' work normally. The Ansible roles do not cover the $_SYS_FAM family yet: the recommendation on each check still applies by hand."
fi

# SYS-02 Kernel (informational, always WARN to prompt version review)
add_result "System" "WARN" "SYS-02" "Kernel version" "Version noyau" "$(uname -r)" \
  "Check for kernel updates: 'dnf check-update kernel' or 'apt list --upgradable | grep linux-image'."

# SYS-03 Pending updates
#
# Every branch ends in a result. The previous version handled dnf and apt-get
# and nothing else, so on SUSE, Arch or Alpine the check emitted NOTHING: the
# report simply had one fewer line and the operator had no way to know an update
# check had been skipped. A check that disappears silently is worse than one
# that says it cannot tell.
PENDING=0
_SYS_PKG="$(distro_pkg_mgr)"
case "$_SYS_PKG" in
  dnf|dnf5|yum)
    PENDING=$("$_SYS_PKG" check-update --security -q 2>/dev/null | grep -cE '\.' || true)
    if [[ "$PENDING" -eq 0 ]]; then
      add_result "System" "PASS" "SYS-03" "No pending security updates" "Système à jour" "0 packages" ""
    else
      add_result "System" "FAIL" "SYS-03" "Pending security updates" "Mises à jour en attente" "$PENDING package(s)" \
        "Apply: '$_SYS_PKG update --security -y'"
    fi ;;
  apt-get)
    # Scoped to SECURITY updates, like the dnf and zypper branches above it.
    #
    # This counted every upgradable package, so the same check ID meant
    # "unpatched CVEs" on RHEL and "any package is not the newest" on Debian.
    # A docs server with unattended-upgrades running correctly, zero security
    # updates outstanding and twenty routine ones reported exactly the same
    # FAIL as a RHEL host with twenty unpatched CVEs. Anyone comparing an
    # Ubuntu fleet against a RHEL fleet was reading two different questions.
    #
    # apt marks the origin in the simulated Inst line:
    #   Inst libfoo [1.2] (1.3 Ubuntu:24.04/noble-security [amd64])
    apt-get update -qq 2>/dev/null || true
    _SYS_APT_SIM=$(apt-get -s upgrade 2>/dev/null | grep "^Inst" || true)
    PENDING=$(printf '%s\n' "$_SYS_APT_SIM" | grep -c -- '-security' || true)
    _SYS_APT_TOTAL=$(printf '%s\n' "$_SYS_APT_SIM" | grep -c . || true)
    if [[ "$PENDING" -eq 0 ]]; then
      add_result "System" "PASS" "SYS-03" "No pending security updates" "Système à jour" \
        "0 security (${_SYS_APT_TOTAL} total pending)" ""
    else
      add_result "System" "FAIL" "SYS-03" "Pending security updates" "Mises à jour de sécurité en attente" \
        "${PENDING} security (${_SYS_APT_TOTAL} total pending)" \
        "Apply: 'apt-get upgrade -y', or let unattended-upgrades do it"
    fi ;;
  zypper)
    # list-patches --category security is the SUSE equivalent of --security.
    PENDING=$(zypper --non-interactive list-patches --category security 2>/dev/null | grep -cE '^[a-zA-Z]' || true)
    PENDING=$(( PENDING > 0 ? PENDING - 1 : 0 ))   # drop the header row
    if [[ "$PENDING" -eq 0 ]]; then
      add_result "System" "PASS" "SYS-03" "No pending security patches" "Système à jour" "0 patches" ""
    else
      add_result "System" "FAIL" "SYS-03" "Pending security patches" "Correctifs en attente" "$PENDING patch(es)" \
        "Apply: 'zypper patch --category security'"
    fi ;;
  pacman)
    # Rolling release: there is no security-only channel, so this is all updates.
    PENDING=$(pacman -Qu 2>/dev/null | grep -c . || true)
    if [[ "$PENDING" -eq 0 ]]; then
      add_result "System" "PASS" "SYS-03" "No pending updates" "Système à jour" "0 packages" ""
    else
      add_result "System" "WARN" "SYS-03" "Pending updates" "Mises à jour en attente" "$PENDING package(s), rolling release" \
        "Apply: 'pacman -Syu'. A rolling-release distribution does not separate security fixes from the rest."
    fi ;;
  apk)
    PENDING=$(apk version -l '<' 2>/dev/null | grep -c '^[a-zA-Z]' || true)
    PENDING=$(( PENDING > 0 ? PENDING - 1 : 0 ))
    if [[ "$PENDING" -eq 0 ]]; then
      add_result "System" "PASS" "SYS-03" "No pending updates" "Système à jour" "0 packages" ""
    else
      add_result "System" "WARN" "SYS-03" "Pending updates" "Mises à jour en attente" "$PENDING package(s)" \
        "Apply: 'apk upgrade'"
    fi ;;
  none)
    add_result "System" "WARN" "SYS-03" "No package manager found" "Aucun gestionnaire de paquets" \
      "checked: dnf, apt-get, zypper, pacman, apk" \
      "Minimal image or immutable distribution. Check for updates through whatever mechanism that image provides." ;;
  *)
    add_result "System" "WARN" "SYS-03" "Update status not determined" "État des mises à jour indéterminé" \
      "package manager: $_SYS_PKG (unsupported by this check)" \
      "Ce gestionnaire de paquets n'est pas encore couvert. Le reste de l'audit reste valable." ;;
esac

# SYS-11 Running kernel is the newest one installed
#
# Placed here rather than at the end of the section because it completes the
# patching story SYS-03 starts; the ID is out of sequence so existing report
# comparisons keep working.
#
# A kernel fix only takes effect once the machine boots into it. unattended-upgrades
# installs the package and, with Automatic-Reboot "false" (the default), never
# activates it. The host then reads as fully patched on disk while still executing
# the vulnerable image, and SYS-03 cannot see it: there is nothing left pending to
# count. Found on a 13-node estate where every host had a newer kernel in /boot and
# seven had been running the old one for 108 days.
KRUN=$(uname -r)
KNEW=$(ls -1 /boot/vmlinuz-* 2>/dev/null | sed 's|.*/vmlinuz-||' | grep -vE '\.(sig|efi|signed|old)$' | sort -V | tail -1)
KUP=$(awk '{printf "%d", $1/86400}' /proc/uptime 2>/dev/null || echo "?")
if [[ -z "$KNEW" ]]; then
  add_result "System" "WARN" "SYS-11" "Cannot determine installed kernels" "Noyaux installés indéterminés" \
    "no /boot/vmlinuz-* found" \
    "Compare 'uname -r' by hand against the newest installed kernel."
elif [[ "$KNEW" == "$KRUN" ]]; then
  add_result "System" "PASS" "SYS-11" "Running the newest installed kernel" "Noyau le plus récent actif" \
    "$KRUN (uptime ${KUP}j)" ""
elif [[ "$(printf '%s\n%s\n' "$KRUN" "$KNEW" | sort -V | tail -1)" == "$KRUN" ]]; then
  # Running kernel outranks everything in /boot. Not a missing reboot: usually a
  # custom or vendor kernel whose image lives outside /boot.
  add_result "System" "WARN" "SYS-11" "Running kernel not found in /boot" "Noyau actif absent de /boot" \
    "running $KRUN, newest in /boot $KNEW" \
    "Kernel from outside the repositories, or an image outside /boot. Check that its source actually ships security fixes."
else
  add_result "System" "FAIL" "SYS-11" "Newer kernel installed but not running" "Noyau plus récent installé mais inactif" \
    "running $KRUN, installed $KNEW, uptime ${KUP}j" \
    "The fix is installed but not running. Reboot to activate $KNEW. On a quorum cluster (OpenSearch, Kafka, etcd), one node at a time, checking health between each."
fi

# SYS-04 SELinux / AppArmor
if cmd_exists getenforce; then
  SEMODE=$(getenforce 2>/dev/null || echo "Unknown")
  case "$SEMODE" in
    Enforcing) add_result "System" "PASS" "SYS-04" "SELinux Enforcing" "SELinux Enforcing" "$SEMODE" "" ;;
    Permissive) add_result "System" "WARN" "SYS-04" "SELinux Permissive" "SELinux Permissive" "$SEMODE" \
      "Set Enforcing: 'setenforce 1' and update /etc/selinux/config." ;;
    *) add_result "System" "FAIL" "SYS-04" "SELinux Disabled" "SELinux désactivé" "$SEMODE" \
      "Enable SELinux in /etc/selinux/config: SELINUX=enforcing" ;;
  esac
elif cmd_exists apparmor_status; then
  AA=$(apparmor_status 2>/dev/null | head -1 || echo "present")
  add_result "System" "PASS" "SYS-04" "AppArmor present" "AppArmor présent" "$AA" ""
else
  add_result "System" "FAIL" "SYS-04" "No MAC framework" "Pas de contrôle d'accès MAC" "SELinux/AppArmor absent" \
    "Install and enable SELinux or AppArmor."
fi

# SYS-05 Core dumps
CORE_RESTRICTED=false
grep -qsE '^\s*\*\s+hard\s+core\s+0' /etc/security/limits.conf /etc/security/limits.d/*.conf 2>/dev/null && CORE_RESTRICTED=true
[[ "$(sysctl -n fs.suid_dumpable 2>/dev/null)" == "0" ]] && CORE_RESTRICTED=true
if $CORE_RESTRICTED; then
  add_result "System" "PASS" "SYS-05" "Core dumps restricted" "Core dumps restreints" "Restricted" ""
else
  add_result "System" "WARN" "SYS-05" "Core dumps not restricted" "Core dumps non restreints" "May expose memory" \
    "Add '* hard core 0' to /etc/security/limits.conf"
fi

# SYS-06 Time synchronization
_TSVC=""
svc_active chronyd         && _TSVC="chronyd"
svc_active chrony          && _TSVC="chrony"
svc_active ntpd            && _TSVC="ntpd"
svc_active systemd-timesyncd && _TSVC="systemd-timesyncd"
if [[ -n "$_TSVC" ]]; then
  add_result "System" "PASS" "SYS-06" "Time synchronization active" "Synchronisation temps active" "$_TSVC: running" ""
else
  add_result "System" "FAIL" "SYS-06" "No time sync daemon running" "Pas de synchronisation temps" "chronyd/ntpd/timesyncd inactive" \
    "Install and enable: 'dnf install chrony && systemctl enable --now chronyd'"
fi

# SYS-07 GRUB config permissions
GRUB_CFG=""
[[ -f /boot/grub2/grub.cfg ]] && GRUB_CFG="/boot/grub2/grub.cfg"
[[ -f /boot/grub/grub.cfg  ]] && GRUB_CFG="/boot/grub/grub.cfg"
if [[ -n "$GRUB_CFG" ]]; then
  GRUB_PERMS=$(stat -c "%a" "$GRUB_CFG" 2>/dev/null || echo "")
  if [[ "$GRUB_PERMS" =~ ^(600|400|000)$ ]]; then
    add_result "System" "PASS" "SYS-07" "GRUB config permissions OK" "Perms GRUB correctes" "Mode: $GRUB_PERMS ($GRUB_CFG)" ""
  else
    add_result "System" "FAIL" "SYS-07" "GRUB config perms too open" "Perms GRUB trop permissives" "Mode: ${GRUB_PERMS:-?} ($GRUB_CFG)" \
      "Fix: 'chmod 600 $GRUB_CFG && chown root:root $GRUB_CFG'"
  fi
else
  add_result "System" "WARN" "SYS-07" "GRUB config not found" "GRUB config introuvable" "No grub.cfg at standard paths" \
    "Check where your GRUB configuration lives."
fi

# SYS-08 Secure Boot
if cmd_exists mokutil; then
  SB_STATE=$(mokutil --sb-state 2>/dev/null | tr -d '\n' || echo "unknown")
  if echo "$SB_STATE" | grep -qi "enabled"; then
    add_result "System" "PASS" "SYS-08" "Secure Boot enabled" "Secure Boot activé" "$SB_STATE" ""
  else
    add_result "System" "WARN" "SYS-08" "Secure Boot not enabled" "Secure Boot désactivé" "${SB_STATE:-not determined}" \
      "Enable Secure Boot in the UEFI/BIOS. Cannot be configured by Ansible."
  fi
else
  add_result "System" "WARN" "SYS-08" "Cannot check Secure Boot" "Vérif Secure Boot impossible" "mokutil absent" \
    "Install mokutil ('dnf install mokutil') or check in the UEFI/BIOS."
fi

# SYS-09 /dev/shm mount hardening
SHM_OPTS=$(grep -E '\s/dev/shm\s' /proc/mounts 2>/dev/null | awk '{print $4}' | head -1 || echo "")
SHM_OK=true
[[ -z "$SHM_OPTS" ]] && SHM_OK=false
echo "$SHM_OPTS" | grep -q "noexec" || SHM_OK=false
echo "$SHM_OPTS" | grep -q "nosuid" || SHM_OK=false
echo "$SHM_OPTS" | grep -q "nodev"  || SHM_OK=false
if $SHM_OK; then
  add_result "System" "PASS" "SYS-09" "/dev/shm hardened" "/dev/shm sécurisé" "noexec,nosuid,nodev" ""
else
  add_result "System" "WARN" "SYS-09" "/dev/shm missing hardening" "/dev/shm non sécurisé" "${SHM_OPTS:-not mounted or options missing}" \
    "Add to /etc/fstab: 'tmpfs /dev/shm tmpfs defaults,noexec,nosuid,nodev 0 0'"
fi

# SYS-10 Ctrl-Alt-Delete disabled
#
# `systemctl is-masked` is not a systemd verb. It never has been: systemd
# answers "Unknown command verb 'is-masked', did you mean 'is-failed'?" and
# exits non-zero, so this check reported FAIL on every host ever scanned,
# including hosts where the target was correctly masked. Confirmed across a
# 15-node estate: 15 FAIL, 0 PASS, every one of them masked.
#
# `is-enabled` is the verb that reports masking, and it prints "masked" for a
# unit symlinked to /dev/null. Accept both "masked" and "masked-runtime".
CAD_STATE=$(systemctl is-enabled ctrl-alt-del.target 2>/dev/null || true)
if [[ "$CAD_STATE" == masked* ]]; then
  add_result "System" "PASS" "SYS-10" "Ctrl-Alt-Del masked" "Ctrl-Alt-Suppr désactivé" "ctrl-alt-del.target: ${CAD_STATE}" ""
else
  add_result "System" "FAIL" "SYS-10" "Ctrl-Alt-Del not masked" "Ctrl-Alt-Suppr actif" "ctrl-alt-del.target: ${CAD_STATE:-unknown}" \
    "Mask it: 'systemctl mask ctrl-alt-del.target && systemctl daemon-reload'"
fi
}

# =============================================================================
#  KERNEL ATTACK SURFACE  (KRN-01 .. KRN-12)
#
#  WHY THIS FAMILY EXISTS
#  Every other family here asks "is this configured correctly". This one asks a
#  different question: "when the next local privilege escalation lands, does it
#  reach you".
#
#  Red Hat and Debian ship the patch. Nobody helps with the window before the
#  patch exists, or with the machine you cannot reboot this quarter. That window
#  is the whole point of these checks: each one closes a class of exploit rather
#  than a single CVE, and each takes effect without a reboot.
#
#  A worked example, so the framing is not marketing. Unprivileged user
#  namespaces are the entry point for a large share of published Linux LPEs:
#  they hand an unprivileged process CAP_SYS_ADMIN inside its own namespace,
#  which is what turns a bug in nftables, io_uring, OverlayFS or a network
#  protocol into root. Turning them off does not fix any of those bugs. It
#  removes the doorway they all walk through.
#
#  These are WARN, not FAIL, and deliberately. Several of them break real
#  workloads: containers need user namespaces, some databases want io_uring,
#  debuggers want ptrace. A tool that fails a build over a setting the workload
#  requires teaches people to ignore it. Each check says what it costs.
# =============================================================================

_krn_sysctl() { sysctl -n "$1" 2>/dev/null || printf '?'; }

# The summary at KRN-12 counts these rather than re-testing the values. An
# earlier version evaluated the sysctls a second time and disagreed with itself:
# KRN-02 passed on unprivileged_bpf_disabled=2 while the summary, matching only
# "1", counted the same setting as an open door. A summary derived from anything
# other than the verdicts it summarises will drift from them.
_KRN_DOORS_OPEN=0
_KRN_DOORS_KNOWN=0
_krn_door() {           # _krn_door open|closed|na
  case "$1" in
    open)   _KRN_DOORS_OPEN=$((_KRN_DOORS_OPEN+1)); _KRN_DOORS_KNOWN=$((_KRN_DOORS_KNOWN+1)) ;;
    closed) _KRN_DOORS_KNOWN=$((_KRN_DOORS_KNOWN+1)) ;;
  esac
}
_checks_kernel() {
# =============================================================================
#  1b. KERNEL ATTACK SURFACE
# =============================================================================
section "1b. KERNEL ATTACK SURFACE"

  # ── KRN-01  Unprivileged user namespaces ─────────────────────────────────────
  # The single highest-value setting in this family.
  _KRN_USERNS="?"
  if [[ -r /proc/sys/kernel/unprivileged_userns_clone ]]; then
    _KRN_USERNS="$(_krn_sysctl kernel.unprivileged_userns_clone)"   # Debian/Ubuntu
    if [[ "$_KRN_USERNS" == "0" ]]; then
      add_result "Kernel" "PASS" "KRN-01" "Unprivileged user namespaces disabled" \
        "Espaces de noms utilisateur non privilégiés désactivés" "unprivileged_userns_clone=0" ""
      _krn_door closed
    else
      add_result "Kernel" "WARN" "KRN-01" "Unprivileged user namespaces allowed" \
        "Espaces de noms utilisateur non privilégiés autorisés" "unprivileged_userns_clone=$_KRN_USERNS" \
        "A doorway for many local privilege escalations. 'sysctl -w kernel.unprivileged_userns_clone=0'. Breaks rootless Docker/Podman and the Chrome sandbox."
      _krn_door open
    fi
  else
    _KRN_USERNS="$(_krn_sysctl user.max_user_namespaces)"            # RHEL family
    if [[ "$_KRN_USERNS" == "0" ]]; then
      add_result "Kernel" "PASS" "KRN-01" "Unprivileged user namespaces disabled" \
        "Espaces de noms utilisateur non privilégiés désactivés" "user.max_user_namespaces=0" ""
      _krn_door closed
    elif [[ "$_KRN_USERNS" == "?" ]]; then
      add_result "Kernel" "WARN" "KRN-01" "Cannot determine user namespace policy" \
        "Politique des espaces de noms indéterminée" "no unprivileged_userns_clone or max_user_namespaces" ""
      _krn_door na
    else
      add_result "Kernel" "WARN" "KRN-01" "Unprivileged user namespaces allowed" \
        "Espaces de noms utilisateur non privilégiés autorisés" "user.max_user_namespaces=$_KRN_USERNS" \
        "A doorway for many local privilege escalations. 'sysctl -w user.max_user_namespaces=0'. Breaks rootless containers."
      _krn_door open
    fi
  fi

  # ── KRN-02  Unprivileged eBPF ────────────────────────────────────────────────
  _KRN_BPF="$(_krn_sysctl kernel.unprivileged_bpf_disabled)"
  case "$_KRN_BPF" in
    1|2) add_result "Kernel" "PASS" "KRN-02" "Unprivileged eBPF disabled" \
           "eBPF non privilégié désactivé" "unprivileged_bpf_disabled=$_KRN_BPF" ""
         _krn_door closed ;;
    "?") add_result "Kernel" "WARN" "KRN-02" "eBPF policy not readable" \
           "Politique eBPF illisible" "kernel.unprivileged_bpf_disabled absent" ""
         _krn_door na ;;
    *)   add_result "Kernel" "WARN" "KRN-02" "Unprivileged eBPF allowed" \
           "eBPF non privilégié autorisé" "unprivileged_bpf_disabled=$_KRN_BPF" \
           "The eBPF verifier is a recurring exploitation surface. 'sysctl -w kernel.unprivileged_bpf_disabled=1'"
         _krn_door open ;;
  esac

  # ── KRN-03  io_uring ─────────────────────────────────────────────────────────
  # Young, large and fast-moving: a disproportionate share of recent LPEs.
  _KRN_URING="$(_krn_sysctl kernel.io_uring_disabled)"
  if [[ "$_KRN_URING" == "?" ]]; then
    add_result "Kernel" "PASS" "KRN-03" "io_uring control not present" \
      "Contrôle io_uring absent" "kernel.io_uring_disabled unsupported on this kernel" ""
    _krn_door na
  elif [[ "$_KRN_URING" == "2" ]]; then
    add_result "Kernel" "PASS" "KRN-03" "io_uring disabled" "io_uring désactivé" "io_uring_disabled=2" ""
    _krn_door closed
  else
    add_result "Kernel" "WARN" "KRN-03" "io_uring available to unprivileged users" \
      "io_uring accessible sans privilège" "io_uring_disabled=$_KRN_URING" \
      "A young and heavily exposed subsystem. 'sysctl -w kernel.io_uring_disabled=2' (1 = restricted to io_uring_group). May affect some databases and proxies."
    _krn_door open
  fi

  # ── KRN-04  userfaultfd ──────────────────────────────────────────────────────
  # Not itself a bug, but what turns a race into a reliable exploit.
  _KRN_UFFD="$(_krn_sysctl vm.unprivileged_userfaultfd)"
  if [[ "$_KRN_UFFD" == "0" ]]; then
    add_result "Kernel" "PASS" "KRN-04" "Unprivileged userfaultfd disabled" \
      "userfaultfd non privilégié désactivé" "vm.unprivileged_userfaultfd=0" ""
    _krn_door closed
  elif [[ "$_KRN_UFFD" == "?" ]]; then
    add_result "Kernel" "PASS" "KRN-04" "userfaultfd control not present" \
      "Contrôle userfaultfd absent" "vm.unprivileged_userfaultfd unsupported" ""
    _krn_door na
  else
    add_result "Kernel" "WARN" "KRN-04" "Unprivileged userfaultfd allowed" \
      "userfaultfd non privilégié autorisé" "vm.unprivileged_userfaultfd=$_KRN_UFFD" \
      "Used to make kernel race conditions reliably exploitable. 'sysctl -w vm.unprivileged_userfaultfd=0'"
    _krn_door open
  fi

  # ── KRN-05  Kernel module loading ────────────────────────────────────────────
  _KRN_MODLOCK="$(_krn_sysctl kernel.modules_disabled)"
  if [[ "$_KRN_MODLOCK" == "1" ]]; then
    add_result "Kernel" "PASS" "KRN-05" "Module loading locked" "Chargement de modules verrouillé" "kernel.modules_disabled=1" ""
  else
    add_result "Kernel" "WARN" "KRN-05" "Module loading open" "Chargement de modules ouvert" "kernel.modules_disabled=${_KRN_MODLOCK/\?/0}" \
      "Locking after boot stops a rootkit being loaded as a module. 'sysctl -w kernel.modules_disabled=1' once the machine has settled. Irreversible until reboot."
  fi

  # ── KRN-06  kexec ────────────────────────────────────────────────────────────
  _KRN_KEXEC="$(_krn_sysctl kernel.kexec_load_disabled)"
  if [[ "$_KRN_KEXEC" == "1" ]]; then
    add_result "Kernel" "PASS" "KRN-06" "kexec disabled" "kexec désactivé" "kexec_load_disabled=1" ""
  else
    add_result "Kernel" "WARN" "KRN-06" "kexec allowed" "kexec autorisé" "kexec_load_disabled=${_KRN_KEXEC/\?/0}" \
      "kexec boots an arbitrary kernel without going through the firmware, bypassing Secure Boot. 'sysctl -w kernel.kexec_load_disabled=1'"
  fi

  # ── KRN-07  TTY line discipline autoload ─────────────────────────────────────
  _KRN_LDISC="$(_krn_sysctl dev.tty.ldisc_autoload)"
  if [[ "$_KRN_LDISC" == "0" ]]; then
    add_result "Kernel" "PASS" "KRN-07" "TTY line discipline autoload disabled" \
      "Chargement auto des disciplines TTY désactivé" "dev.tty.ldisc_autoload=0" ""
  elif [[ "$_KRN_LDISC" == "?" ]]; then
    add_result "Kernel" "PASS" "KRN-07" "ldisc autoload control not present" \
      "Contrôle ldisc absent" "dev.tty.ldisc_autoload unsupported" ""
  else
    add_result "Kernel" "WARN" "KRN-07" "TTY line discipline autoload enabled" \
      "Chargement auto des disciplines TTY activé" "dev.tty.ldisc_autoload=$_KRN_LDISC" \
      "Lets an unprivileged user load old, lightly audited TTY modules. 'sysctl -w dev.tty.ldisc_autoload=0'"
  fi

  # ── KRN-08  Kernel lockdown ──────────────────────────────────────────────────
  if [[ -r /sys/kernel/security/lockdown ]]; then
    _KRN_LOCKDOWN="$(sed -n 's/.*\[\([a-z]*\)\].*/\1/p' /sys/kernel/security/lockdown 2>/dev/null)"
    case "$_KRN_LOCKDOWN" in
      integrity|confidentiality)
        add_result "Kernel" "PASS" "KRN-08" "Kernel lockdown active" "Verrouillage noyau actif" "lockdown=$_KRN_LOCKDOWN" "" ;;
      *)
        add_result "Kernel" "WARN" "KRN-08" "Kernel lockdown off" "Verrouillage noyau inactif" "lockdown=${_KRN_LOCKDOWN:-none}" \
          "Stops even root from changing the running kernel. Enabled through Secure Boot, or 'lockdown=integrity' on the kernel command line." ;;
    esac
  else
    add_result "Kernel" "WARN" "KRN-08" "Kernel lockdown not available" "Verrouillage noyau indisponible" \
      "/sys/kernel/security/lockdown absent" "Requires a kernel built with CONFIG_SECURITY_LOCKDOWN_LSM."
  fi

  # ── KRN-09  BPF JIT hardening ────────────────────────────────────────────────
  _KRN_JIT="$(_krn_sysctl net.core.bpf_jit_harden)"
  if [[ "$_KRN_JIT" =~ ^[12]$ ]]; then
    add_result "Kernel" "PASS" "KRN-09" "BPF JIT hardening on" "Durcissement JIT BPF actif" "bpf_jit_harden=$_KRN_JIT" ""
  elif [[ "$_KRN_JIT" == "?" ]]; then
    add_result "Kernel" "PASS" "KRN-09" "BPF JIT control not present" "Contrôle JIT BPF absent" "net.core.bpf_jit_harden unsupported" ""
  else
    add_result "Kernel" "WARN" "KRN-09" "BPF JIT hardening off" "Durcissement JIT BPF inactif" "bpf_jit_harden=$_KRN_JIT" \
      "Without hardening, the JIT makes spraying code into kernel memory easier. 'sysctl -w net.core.bpf_jit_harden=2'"
  fi

  # ── KRN-10  SysRq ────────────────────────────────────────────────────────────
  _KRN_SYSRQ="$(_krn_sysctl kernel.sysrq)"
  if [[ "$_KRN_SYSRQ" == "0" || "$_KRN_SYSRQ" == "4" ]]; then
    add_result "Kernel" "PASS" "KRN-10" "SysRq restricted" "SysRq restreint" "kernel.sysrq=$_KRN_SYSRQ" ""
  else
    add_result "Kernel" "WARN" "KRN-10" "SysRq permissive" "SysRq permissif" "kernel.sysrq=${_KRN_SYSRQ/\?/unknown}" \
      "SysRq exposes kernel operations from the physical console, including a memory dump. 'sysctl -w kernel.sysrq=0' (4 keeps only the keyboard reset)."
  fi

  # ── KRN-11  Exotic filesystem modules ────────────────────────────────────────
  # Rarely used, rarely audited, historically a steady source of CVEs. Reached by
  # anyone who can plug in a USB stick or mount an image.
  _KRN_FS_LOADED=""
  for _m in cramfs freevxfs jffs2 hfs hfsplus squashfs udf ksmbd; do
    lsmod 2>/dev/null | awk '{print $1}' | grep -qx "$_m" && _KRN_FS_LOADED+="$_m "
  done
  if [[ -z "$_KRN_FS_LOADED" ]]; then
    add_result "Kernel" "PASS" "KRN-11" "No exotic filesystem modules loaded" \
      "Aucun module de système de fichiers exotique chargé" "cramfs/freevxfs/jffs2/hfs/hfsplus/udf/ksmbd absent" ""
  else
    add_result "Kernel" "WARN" "KRN-11" "Exotic filesystem modules loaded" \
      "Modules de systèmes de fichiers exotiques chargés" "loaded: ${_KRN_FS_LOADED% }" \
      "Rarely used, rarely audited, a regular source of CVEs. Add 'install <module> /bin/true' to /etc/modprobe.d/ for any you do not need."
  fi

  # ── KRN-12  Exposure summary ─────────────────────────────────────────────────
  # The point of the family, stated once: how many doorways are still open.
  # Counts the verdicts recorded above; it does not re-read a single sysctl.
  if [[ "$_KRN_DOORS_KNOWN" -eq 0 ]]; then
    add_result "Kernel" "WARN" "KRN-12" "LPE doorway status unknown" \
      "État des portes d'élévation inconnu" "no doorway control readable on this kernel" ""
  elif [[ "$_KRN_DOORS_OPEN" -eq 0 ]]; then
    add_result "Kernel" "PASS" "KRN-12" "Primary LPE doorways closed" \
      "Principales portes d'élévation fermées" "$_KRN_DOORS_KNOWN of $_KRN_DOORS_KNOWN closed" ""
  else
    add_result "Kernel" "WARN" "KRN-12" "Primary LPE doorways open" \
      "Principales portes d'élévation ouvertes" \
      "$_KRN_DOORS_OPEN of $_KRN_DOORS_KNOWN open (userns, eBPF, io_uring, userfaultfd)" \
      "These settings neutralise whole classes of exploit, with no patch and no reboot. See 'aartool surface'."
  fi
}

_checks_auth() {
# =============================================================================
#  2. AUTHENTICATION & ACCESS
# =============================================================================
section "2. AUTHENTICATION & ACCESS"

# AUTH-01 Root account locked
ROOT_STATUS=$(passwd -S root 2>/dev/null | awk '{print $2}' || echo "")
if [[ "$ROOT_STATUS" =~ ^L ]]; then
  add_result "Auth" "PASS" "AUTH-01" "Root account locked" "Compte root verrouillé" "Status: $ROOT_STATUS" ""
else
  add_result "Auth" "WARN" "AUTH-01" "Root account not locked" "Root non verrouillé" "Status: ${ROOT_STATUS:-unknown}" \
    "Verrouillez: 'passwd -l root'"
fi

# AUTH-02 Empty passwords
EMPTY_PASS=$(awk -F: '($2==""){print $1}' /etc/shadow 2>/dev/null | tr '\n' ',' | sed 's/,$//' || echo "")
if [[ -z "$EMPTY_PASS" ]]; then
  add_result "Auth" "PASS" "AUTH-02" "No empty password accounts" "Aucun compte sans mdp" "All accounts secured" ""
else
  add_result "Auth" "FAIL" "AUTH-02" "Empty password accounts" "Comptes sans mot de passe" "$EMPTY_PASS" \
    "Set a password, or lock the account: 'passwd -l <user>'"
fi

# AUTH-03 Password max age
PASSMAX=$(grep -E "^PASS_MAX_DAYS" /etc/login.defs 2>/dev/null | awk '{print $2}' || echo "")
if [[ -n "$PASSMAX" && "$PASSMAX" -le 90 ]]; then
  add_result "Auth" "PASS" "AUTH-03" "Password max age <= 90 days" "Expiration mdp ≤ 90j" "PASS_MAX_DAYS=$PASSMAX" ""
else
  add_result "Auth" "FAIL" "AUTH-03" "Password max age too long" "Expiration mdp trop longue" "PASS_MAX_DAYS=${PASSMAX:-not set}" \
    "Set PASS_MAX_DAYS=90 in /etc/login.defs"
fi

# AUTH-04 Password min length (pwquality preferred, fallback to login.defs)
PASSMINLEN=""
if [[ -f /etc/security/pwquality.conf ]]; then
  PASSMINLEN=$(grep -E "^\s*minlen\s*=" /etc/security/pwquality.conf 2>/dev/null | \
    awk -F= '{print $2}' | tr -d ' ' | head -1 || echo "")
fi
[[ -z "$PASSMINLEN" ]] && \
  PASSMINLEN=$(grep -E "^PASS_MIN_LEN" /etc/login.defs 2>/dev/null | awk '{print $2}' || echo "")
if [[ -n "$PASSMINLEN" && "$PASSMINLEN" -ge 12 ]]; then
  add_result "Auth" "PASS" "AUTH-04" "Password min length >= 12" "Longueur mdp ≥ 12" "minlen=$PASSMINLEN" ""
else
  add_result "Auth" "WARN" "AUTH-04" "Password min length too short" "Longueur mdp insuffisante" "minlen=${PASSMINLEN:-not set}" \
    "Set 'minlen = 14' in /etc/security/pwquality.conf"
fi

# AUTH-05 No NOPASSWD ALL in sudo
if grep -rE '^\s*[^#].*NOPASSWD\s*:\s*ALL' /etc/sudoers /etc/sudoers.d/ 2>/dev/null | grep -qv "^#"; then
  add_result "Auth" "FAIL" "AUTH-05" "Passwordless sudo ALL found" "Sudo sans mdp (ALL) détecté" "NOPASSWD:ALL present" \
    "Review /etc/sudoers: grant NOPASSWD only on specific commands."
else
  add_result "Auth" "PASS" "AUTH-05" "No unrestricted passwordless sudo" "Sudo sans mdp (ALL) absent" "sudoers OK" ""
fi

# AUTH-06 Inactive never-logged accounts
INACTIVE=$(lastlog 2>/dev/null | awk 'NR>1 && /Never logged in/{print $1}' | \
  grep -vE "^(root|bin|daemon|adm|lp|sync|shutdown|halt|mail|operator|games|ftp|nobody)$" | \
  tr '\n' ',' | sed 's/,$//' || echo "")
if [[ -z "$INACTIVE" ]]; then
  add_result "Auth" "PASS" "AUTH-06" "No stale never-logged accounts" "Pas de comptes inutilisés" "OK" ""
else
  add_result "Auth" "WARN" "AUTH-06" "Never-logged-in accounts found" "Comptes jamais utilisés" "${INACTIVE:0:80}" \
    "Check and remove: 'userdel <user>'"
fi

# AUTH-07 Password minimum age (PASS_MIN_DAYS)
PASSMIN_DAYS=$(grep -E "^PASS_MIN_DAYS" /etc/login.defs 2>/dev/null | awk '{print $2}' || echo "")
if [[ -n "$PASSMIN_DAYS" && "$PASSMIN_DAYS" -ge 1 ]]; then
  add_result "Auth" "PASS" "AUTH-07" "Password min age >= 1 day" "Âge min mdp ≥ 1j" "PASS_MIN_DAYS=$PASSMIN_DAYS" ""
else
  add_result "Auth" "WARN" "AUTH-07" "Password min age not set" "Âge min mdp non défini" "PASS_MIN_DAYS=${PASSMIN_DAYS:-0}" \
    "Set PASS_MIN_DAYS=7 in /etc/login.defs"
fi

# AUTH-08 Password warning age (PASS_WARN_AGE)
PASS_WARN=$(grep -E "^PASS_WARN_AGE" /etc/login.defs 2>/dev/null | awk '{print $2}' || echo "")
if [[ -n "$PASS_WARN" && "$PASS_WARN" -ge 7 ]]; then
  add_result "Auth" "PASS" "AUTH-08" "Password warning age >= 7 days" "Alerte expiration mdp ≥ 7j" "PASS_WARN_AGE=$PASS_WARN" ""
else
  add_result "Auth" "WARN" "AUTH-08" "Password warning age too low" "Alerte expiration mdp insuffisante" "PASS_WARN_AGE=${PASS_WARN:-not set}" \
    "Set PASS_WARN_AGE=14 in /etc/login.defs"
fi

# AUTH-09 Account lockout policy (faillock / pam_tally2)
LOCKOUT_OK=false
if [[ -f /etc/security/faillock.conf ]]; then
  DENY_VAL=$(grep -E "^\s*deny\s*=" /etc/security/faillock.conf 2>/dev/null | \
    awk -F= '{print $2}' | tr -d ' ' | head -1 || echo "")
  [[ -n "$DENY_VAL" && "$DENY_VAL" -le 5 && "$DENY_VAL" -gt 0 ]] && LOCKOUT_OK=true
fi
grep -rqE 'pam_tally2|pam_faillock' /etc/pam.d/ 2>/dev/null && LOCKOUT_OK=true
if $LOCKOUT_OK; then
  add_result "Auth" "PASS" "AUTH-09" "Account lockout configured" "Verrouillage compte configuré" "faillock/pam_tally2 active" ""
else
  add_result "Auth" "FAIL" "AUTH-09" "No account lockout policy" "Aucune politique de verrouillage" "faillock unconfigured" \
    "Configure faillock: 'deny=5, unlock_time=900' in /etc/security/faillock.conf"
fi

# AUTH-10 Shell timeout (TMOUT)
TMOUT_VAL=$(grep -rE "^\s*TMOUT\s*=" /etc/profile /etc/profile.d/*.sh /etc/bashrc /etc/bash.bashrc 2>/dev/null | \
  grep -oE '[0-9]+' | sort -n | head -1 || echo "")
if [[ -n "$TMOUT_VAL" && "$TMOUT_VAL" -le 900 && "$TMOUT_VAL" -gt 0 ]]; then
  add_result "Auth" "PASS" "AUTH-10" "Shell timeout configured" "Délai session shell configuré" "TMOUT=${TMOUT_VAL}s" ""
else
  add_result "Auth" "WARN" "AUTH-10" "Shell timeout not configured" "Délai session shell absent" "TMOUT=${TMOUT_VAL:-not set}" \
    "Add to /etc/profile.d/timeout.sh: 'readonly TMOUT=600; export TMOUT'"
fi

# AUTH-11 No extra UID 0 accounts (besides root)
UID0_ACCOUNTS=$(awk -F: '($3==0 && $1!="root"){print $1}' /etc/passwd 2>/dev/null | \
  tr '\n' ',' | sed 's/,$//' || echo "")
if [[ -z "$UID0_ACCOUNTS" ]]; then
  add_result "Auth" "PASS" "AUTH-11" "No extra UID 0 accounts" "Aucun compte UID 0 illégitime" "root only" ""
else
  add_result "Auth" "FAIL" "AUTH-11" "Extra UID 0 accounts found" "Comptes UID 0 supplémentaires" "$UID0_ACCOUNTS" \
    "Remove or change these accounts: only root should have UID 0."
fi

# AUTH-12 /etc/group permissions
GRP_PERMS=$(stat -c "%a" /etc/group 2>/dev/null || echo "")
if [[ "$GRP_PERMS" == "644" ]]; then
  add_result "Auth" "PASS" "AUTH-12" "/etc/group perms 644" "Perms /etc/group correctes" "Mode: 644" ""
else
  add_result "Auth" "FAIL" "AUTH-12" "/etc/group perms wrong" "Perms /etc/group incorrectes" "Mode: ${GRP_PERMS:-?}" \
    "Fix: 'chmod 644 /etc/group'"
fi

# AUTH-13 /etc/gshadow permissions
GSHADOW_PERMS=$(stat -c "%a" /etc/gshadow 2>/dev/null || echo "")
if [[ "$GSHADOW_PERMS" =~ ^(640|600|000|400)$ ]]; then
  add_result "Auth" "PASS" "AUTH-13" "/etc/gshadow perms correct" "Perms /etc/gshadow correctes" "Mode: $GSHADOW_PERMS" ""
else
  add_result "Auth" "FAIL" "AUTH-13" "/etc/gshadow perms wrong" "Perms /etc/gshadow incorrectes" "Mode: ${GSHADOW_PERMS:-?}" \
    "Fix: 'chmod 640 /etc/gshadow && chown root:shadow /etc/gshadow'"
fi

# AUTH-14 Password complexity (pwquality)
PWQUAL_OK=false
if [[ -f /etc/security/pwquality.conf ]]; then
  PWQUAL_MINLEN=$(grep -E "^\s*minlen\s*=" /etc/security/pwquality.conf 2>/dev/null | \
    awk -F= '{print $2}' | tr -d ' ' | head -1 || echo "")
  [[ -n "$PWQUAL_MINLEN" && "$PWQUAL_MINLEN" -ge 12 ]] && PWQUAL_OK=true
fi
if $PWQUAL_OK; then
  add_result "Auth" "PASS" "AUTH-14" "Password complexity configured" "Complexité mdp configurée" "pwquality: minlen=${PWQUAL_MINLEN}" ""
else
  add_result "Auth" "WARN" "AUTH-14" "Password complexity not enforced" "Complexité mdp non configurée" "pwquality.conf absent or weak" \
    "Configure /etc/security/pwquality.conf: minlen=14, dcredit=-1, ucredit=-1, ocredit=-1"
fi

# AUTH-15 sudo use_pty enforced (CIS 1.3.2)
if grep -rqsE "^\s*Defaults\s+.*use_pty" /etc/sudoers /etc/sudoers.d/ 2>/dev/null; then
  add_result "Auth" "PASS" "AUTH-15" "sudo use_pty enforced" "sudo use_pty activé" "Defaults use_pty found" ""
else
  add_result "Auth" "WARN" "AUTH-15" "sudo use_pty not enforced" "sudo use_pty absent" "Defaults use_pty not found in sudoers" \
    "Add 'Defaults use_pty' to /etc/sudoers.d/99-cis-hardening (CIS 1.3.2)"
fi

# AUTH-16 sudo logfile configured (CIS 1.3.3)
SUDO_LOGFILE=$(grep -rshE "^\s*Defaults\s+.*logfile=" /etc/sudoers /etc/sudoers.d/ 2>/dev/null | \
  grep -oE 'logfile=[^ ]+' | head -1 || echo "")
if [[ -n "$SUDO_LOGFILE" ]]; then
  add_result "Auth" "PASS" "AUTH-16" "sudo logfile configured" "Journal sudo configuré" "$SUDO_LOGFILE" ""
else
  add_result "Auth" "WARN" "AUTH-16" "sudo logfile not configured" "Journal sudo absent" "No logfile= in sudoers" \
    "Add 'Defaults logfile=/var/log/sudo.log' to /etc/sudoers.d/99-cis-hardening (CIS 1.3.3)"
fi
}

_checks_ssh() {
# =============================================================================
#  3. SSH HARDENING
# =============================================================================
section "3. SSH HARDENING"

# SSH-01 PermitRootLogin
RL=$(get_ssh "PermitRootLogin")
if [[ "$RL" =~ ^(no|prohibit-password)$ ]]; then
  add_result "SSH" "PASS" "SSH-01" "PermitRootLogin disabled" "Root SSH désactivé" "PermitRootLogin=$RL" ""
else
  add_result "SSH" "FAIL" "SSH-01" "PermitRootLogin enabled" "Root SSH activé" "PermitRootLogin=${RL:-yes(default)}" \
    "Add 'PermitRootLogin no' to /etc/ssh/sshd_config"
fi

# SSH-02 PasswordAuthentication
PA=$(get_ssh "PasswordAuthentication")
if [[ "$PA" == "no" ]]; then
  add_result "SSH" "PASS" "SSH-02" "Password auth disabled" "Auth mdp SSH désactivée" "PasswordAuthentication=no" ""
else
  add_result "SSH" "WARN" "SSH-02" "Password auth enabled" "Auth mdp SSH activée" "PasswordAuthentication=${PA:-yes(default)}" \
    "Prefer SSH keys: 'PasswordAuthentication no'"
fi

# SSH-03 MaxAuthTries
MA=$(get_ssh "MaxAuthTries")
if [[ -n "$MA" && "$MA" -le 4 ]]; then
  add_result "SSH" "PASS" "SSH-03" "MaxAuthTries <= 4" "Tentatives SSH ≤ 4" "MaxAuthTries=$MA" ""
else
  add_result "SSH" "WARN" "SSH-03" "MaxAuthTries not restricted" "Tentatives SSH non limitées" "MaxAuthTries=${MA:-6(default)}" \
    "Set 'MaxAuthTries 3' in sshd_config"
fi

# SSH-04 AllowTcpForwarding
TF=$(get_ssh "AllowTcpForwarding")
if [[ "$TF" == "no" ]]; then
  add_result "SSH" "PASS" "SSH-04" "TCP Forwarding disabled" "Transfert TCP désactivé" "AllowTcpForwarding=no" ""
else
  add_result "SSH" "WARN" "SSH-04" "TCP Forwarding enabled" "Transfert TCP activé" "AllowTcpForwarding=${TF:-yes(default)}" \
    "Add 'AllowTcpForwarding no' if it is not required."
fi

# SSH-05 X11Forwarding
X11=$(get_ssh "X11Forwarding")
if [[ "$X11" == "no" ]]; then
  add_result "SSH" "PASS" "SSH-05" "X11 Forwarding disabled" "Redirection X11 désactivée" "X11Forwarding=no" ""
else
  add_result "SSH" "WARN" "SSH-05" "X11 Forwarding enabled" "Redirection X11 activée" "X11Forwarding=${X11:-yes}" \
    "Add 'X11Forwarding no' to sshd_config"
fi

# SSH-06 LoginGraceTime
LGT=$(get_ssh "LoginGraceTime")
LGT_INT=$(echo "${LGT:-120}" | grep -oE '[0-9]+' | head -1)
if [[ -n "$LGT_INT" && "$LGT_INT" -le 60 ]]; then
  add_result "SSH" "PASS" "SSH-06" "LoginGraceTime <= 60s" "Délai connexion SSH ≤ 60s" "LoginGraceTime=${LGT}" ""
else
  add_result "SSH" "WARN" "SSH-06" "LoginGraceTime too long" "Délai connexion SSH trop long" "LoginGraceTime=${LGT:-120(default)}" \
    "Set 'LoginGraceTime 60' in sshd_config"
fi

# SSH-07 PermitEmptyPasswords
PE=$(get_ssh "PermitEmptyPasswords")
if [[ "$PE" == "no" || -z "$PE" ]]; then
  add_result "SSH" "PASS" "SSH-07" "PermitEmptyPasswords disabled" "Mdp vide SSH interdit" "PermitEmptyPasswords=${PE:-no(default)}" ""
else
  add_result "SSH" "FAIL" "SSH-07" "PermitEmptyPasswords enabled" "Mdp vide SSH autorisé" "PermitEmptyPasswords=$PE" \
    "Add 'PermitEmptyPasswords no' to sshd_config"
fi

# SSH-08 IgnoreRhosts
IR=$(get_ssh "IgnoreRhosts")
if [[ "$IR" == "yes" || -z "$IR" ]]; then
  add_result "SSH" "PASS" "SSH-08" "IgnoreRhosts enabled" "Rhosts ignorés" "IgnoreRhosts=${IR:-yes(default)}" ""
else
  add_result "SSH" "FAIL" "SSH-08" "IgnoreRhosts disabled" "Rhosts autorisés" "IgnoreRhosts=$IR" \
    "Add 'IgnoreRhosts yes' to sshd_config"
fi

# SSH-09 HostbasedAuthentication
HBA=$(get_ssh "HostbasedAuthentication")
if [[ "$HBA" == "no" || -z "$HBA" ]]; then
  add_result "SSH" "PASS" "SSH-09" "HostbasedAuthentication disabled" "Auth par hôte désactivée" "HostbasedAuthentication=${HBA:-no(default)}" ""
else
  add_result "SSH" "FAIL" "SSH-09" "HostbasedAuthentication enabled" "Auth par hôte activée" "HostbasedAuthentication=$HBA" \
    "Add 'HostbasedAuthentication no' to sshd_config"
fi

# SSH-10 Legal banner
BANNER_FILE=$(get_ssh "Banner")
BANNER_OK=false
if [[ -n "$BANNER_FILE" && -f "$BANNER_FILE" ]]; then
  BANNER_LEN=$(wc -c < "$BANNER_FILE" 2>/dev/null || echo 0)
  [[ "${BANNER_LEN:-0}" -gt 10 ]] && BANNER_OK=true
fi
if $BANNER_OK; then
  add_result "SSH" "PASS" "SSH-10" "SSH legal banner configured" "Bannière légale SSH présente" "Banner=$BANNER_FILE" ""
else
  add_result "SSH" "WARN" "SSH-10" "SSH legal banner missing" "Bannière légale SSH absente" "Banner=${BANNER_FILE:-not set}" \
    "Create /etc/issue.net and add 'Banner /etc/issue.net' to sshd_config"
fi

# SSH-11 ClientAliveInterval
CAI=$(get_ssh "ClientAliveInterval")
if [[ -n "$CAI" && "$CAI" -le 300 && "$CAI" -gt 0 ]]; then
  add_result "SSH" "PASS" "SSH-11" "ClientAliveInterval <= 300s" "Délai inactivité SSH configuré" "ClientAliveInterval=$CAI" ""
else
  add_result "SSH" "WARN" "SSH-11" "ClientAliveInterval not configured" "Délai inactivité SSH absent" "ClientAliveInterval=${CAI:-not set}" \
    "Set 'ClientAliveInterval 300' and 'ClientAliveCountMax 3' in sshd_config"
fi

# SSH-12 UsePAM
UPAM=$(get_ssh "UsePAM")
if [[ "$UPAM" == "yes" || -z "$UPAM" ]]; then
  add_result "SSH" "PASS" "SSH-12" "UsePAM enabled" "PAM SSH activé" "UsePAM=${UPAM:-yes(default)}" ""
else
  add_result "SSH" "WARN" "SSH-12" "UsePAM disabled" "PAM SSH désactivé" "UsePAM=$UPAM" \
    "Add 'UsePAM yes' to sshd_config"
fi

# SSH-13 Weak ciphers absent
CIPHERS=$(get_ssh "Ciphers")
if [[ -n "$CIPHERS" ]] && echo "$CIPHERS" | grep -qiE '(arcfour|3des|des|blowfish|cast128)'; then
  add_result "SSH" "FAIL" "SSH-13" "Weak SSH ciphers configured" "Chiffrements SSH faibles détectés" "$CIPHERS" \
    "Allow only strong ciphers in sshd_config (chacha20, aes256-gcm, aes128-ctr)"
else
  add_result "SSH" "PASS" "SSH-13" "No weak SSH ciphers" "Pas de chiffrements SSH faibles" "${CIPHERS:-default (verify)}" ""
fi

# SSH-14 sshd_config permissions
SSHD_CFG_PERMS=$(stat -c "%a" /etc/ssh/sshd_config 2>/dev/null || echo "")
if [[ "$SSHD_CFG_PERMS" =~ ^(600|640|644)$ ]]; then
  add_result "SSH" "PASS" "SSH-14" "sshd_config permissions OK" "Perms sshd_config correctes" "Mode: $SSHD_CFG_PERMS" ""
else
  add_result "SSH" "WARN" "SSH-14" "sshd_config permissions loose" "Perms sshd_config trop permissives" "Mode: ${SSHD_CFG_PERMS:-?}" \
    "Fix: 'chmod 600 /etc/ssh/sshd_config && chown root:root /etc/ssh/sshd_config'"
fi

# SSH-15 MaxSessions
MS=$(get_ssh "MaxSessions")
if [[ -n "$MS" && "$MS" -le 4 ]]; then
  add_result "SSH" "PASS" "SSH-15" "MaxSessions <= 4" "Sessions SSH max ≤ 4" "MaxSessions=$MS" ""
else
  add_result "SSH" "WARN" "SSH-15" "MaxSessions not restricted" "Sessions SSH non limitées" "MaxSessions=${MS:-10(default)}" \
    "Set 'MaxSessions 4' in sshd_config"
fi
}

_checks_filesystem() {
# =============================================================================
#  4. FILESYSTEM & PERMISSIONS
# =============================================================================
section "4. FILESYSTEM & PERMISSIONS"

# FS-01 /etc/passwd
PP=$(stat -c "%a" /etc/passwd 2>/dev/null || echo "")
[[ "$PP" == "644" ]] && \
  add_result "Files" "PASS" "FS-01" "/etc/passwd perms 644" "Perms /etc/passwd correctes" "Mode: 644" "" || \
  add_result "Files" "FAIL" "FS-01" "/etc/passwd perms wrong" "Perms /etc/passwd incorrectes" "Mode: ${PP:-?}" \
    "Fix: 'chmod 644 /etc/passwd'"

# FS-02 /etc/shadow
SP=$(stat -c "%a" /etc/shadow 2>/dev/null || echo "")
if [[ "$SP" =~ ^(640|600|000|400)$ ]]; then
  add_result "Files" "PASS" "FS-02" "/etc/shadow perms correct" "Perms /etc/shadow correctes" "Mode: $SP" ""
else
  add_result "Files" "FAIL" "FS-02" "/etc/shadow perms wrong" "Perms /etc/shadow incorrectes" "Mode: ${SP:-?}" \
    "Fix: 'chmod 640 /etc/shadow'"
fi

# FS-03 /etc/sudoers
SDP=$(stat -c "%a" /etc/sudoers 2>/dev/null || echo "")
if [[ "$SDP" =~ ^(440|400)$ ]]; then
  add_result "Files" "PASS" "FS-03" "/etc/sudoers perms 440" "Perms sudoers correctes" "Mode: $SDP" ""
else
  add_result "Files" "WARN" "FS-03" "/etc/sudoers perms wrong" "Perms sudoers incorrectes" "Mode: ${SDP:-not found}" \
    "Fix: 'chmod 440 /etc/sudoers'"
fi

# FS-04 World-writable files
WW=$(find /etc /usr /bin /sbin -xdev -perm -0002 -type f 2>/dev/null | wc -l)
if [[ "$WW" -eq 0 ]]; then
  add_result "Files" "PASS" "FS-04" "No world-writable files" "Aucun fichier inscriptible par tous" "0 found in /etc /usr /bin /sbin" ""
else
  add_result "Files" "FAIL" "FS-04" "World-writable files found" "Fichiers inscriptibles par tous" "$WW file(s)" \
    "Audit: 'find /etc /usr -perm -0002 -type f -ls'"
fi

# FS-05 SUID count
SUID=$(find / -xdev -perm -4000 -type f 2>/dev/null | wc -l)
if [[ "$SUID" -le 20 ]]; then
  add_result "Files" "PASS" "FS-05" "SUID binary count OK" "Binaires SUID: count OK" "Count: $SUID" ""
else
  add_result "Files" "WARN" "FS-05" "High SUID binary count" "Nombre élevé de binaires SUID" "Count: $SUID (manual review required)" \
    "Audit: 'find / -xdev -perm -4000 -ls', then remove the SUID bit from binaries that do not need it."
fi

# FS-06 /tmp noexec
TMP_OPTS=$(grep -E '\s/tmp\s' /proc/mounts 2>/dev/null | awk '{print $4}' | head -1 || echo "")
if echo "$TMP_OPTS" | grep -q "noexec"; then
  add_result "Files" "PASS" "FS-06" "/tmp mounted noexec" "/tmp monté noexec" "noexec on /tmp" ""
else
  add_result "Files" "WARN" "FS-06" "/tmp not noexec" "/tmp sans noexec" "Executables can run from /tmp" \
    "Mount /tmp with noexec,nosuid,nodev in /etc/fstab"
fi

# FS-07 Sticky bit on world-writable directories
NOSTICKY=$(find / -xdev -type d -perm -0002 ! -perm -1000 2>/dev/null | wc -l)
if [[ "$NOSTICKY" -eq 0 ]]; then
  add_result "Files" "PASS" "FS-07" "Sticky bit on all world-writable dirs" "Sticky bit sur répertoires partagés" "All world-writable dirs have sticky bit" ""
else
  add_result "Files" "FAIL" "FS-07" "World-writable dirs without sticky bit" "Répertoires sans sticky bit" "$NOSTICKY dir(s)" \
    "Fix: 'find / -xdev -type d -perm -0002 ! -perm -1000 -exec chmod +t {} \;'"
fi

# FS-08 /etc/crontab permissions
CRONTAB_PERMS=$(stat -c "%a" /etc/crontab 2>/dev/null || echo "")
if [[ "$CRONTAB_PERMS" =~ ^(600|400)$ ]]; then
  add_result "Files" "PASS" "FS-08" "/etc/crontab perms OK" "Perms /etc/crontab correctes" "Mode: $CRONTAB_PERMS" ""
elif [[ -z "$CRONTAB_PERMS" ]]; then
  add_result "Files" "WARN" "FS-08" "/etc/crontab not found" "/etc/crontab introuvable" "File absent" ""
else
  add_result "Files" "WARN" "FS-08" "/etc/crontab perms too open" "Perms /etc/crontab trop permissives" "Mode: $CRONTAB_PERMS" \
    "Fix: 'chmod 600 /etc/crontab && chown root:root /etc/crontab'"
fi

# FS-09 /var/tmp noexec
VARTMP_OPTS=$(grep -E '\s/var/tmp\s' /proc/mounts 2>/dev/null | awk '{print $4}' | head -1 || echo "")
if echo "$VARTMP_OPTS" | grep -q "noexec"; then
  add_result "Files" "PASS" "FS-09" "/var/tmp mounted noexec" "/var/tmp monté noexec" "noexec on /var/tmp" ""
else
  add_result "Files" "WARN" "FS-09" "/var/tmp not noexec" "/var/tmp sans noexec" "${VARTMP_OPTS:-not separately mounted}" \
    "Mount /var/tmp with noexec,nosuid,nodev in /etc/fstab"
fi

# FS-10 Unowned files and directories
UNOWNED=$(find / -xdev \( -nouser -o -nogroup \) -type f 2>/dev/null | wc -l)
if [[ "$UNOWNED" -eq 0 ]]; then
  add_result "Files" "PASS" "FS-10" "No unowned files" "Aucun fichier sans propriétaire" "0 files" ""
else
  add_result "Files" "WARN" "FS-10" "Unowned files found" "Fichiers sans propriétaire" "$UNOWNED file(s) (manual review required)" \
    "Audit: 'find / -xdev \( -nouser -o -nogroup \) -type f -ls' and assign an owner."
fi

# FS-11 /var/log not world-readable
VARLOG_PERMS=$(stat -c "%a" /var/log 2>/dev/null || echo "")
_VL_LAST="${VARLOG_PERMS: -1}"
if [[ "$_VL_LAST" == "0" || "$_VL_LAST" == "1" ]]; then
  add_result "Files" "PASS" "FS-11" "/var/log not world-readable" "/var/log non lisible par tous" "Mode: $VARLOG_PERMS" ""
else
  add_result "Files" "WARN" "FS-11" "/var/log world-readable" "/var/log lisible par tous" "Mode: ${VARLOG_PERMS:-?}" \
    "Fix: 'chmod 750 /var/log'"
fi

# FS-12 SSH host private key permissions
SSH_KEY_ISSUES=$(find /etc/ssh -name "ssh_host_*_key" ! -name "*.pub" ! -perm 600 2>/dev/null | wc -l)
if [[ "$SSH_KEY_ISSUES" -eq 0 ]]; then
  add_result "Files" "PASS" "FS-12" "SSH host private keys 600" "Clés privées SSH protégées" "All at mode 600" ""
else
  add_result "Files" "FAIL" "FS-12" "SSH host private key perms wrong" "Clés privées SSH mal protégées" "$SSH_KEY_ISSUES key(s) wrong perms" \
    "Fix: 'chmod 600 /etc/ssh/ssh_host_*_key'"
fi
}

_checks_network() {
# =============================================================================
#  5. NETWORK
# =============================================================================
section "5. NETWORK"

# NET-01 Firewall
if svc_active firewalld; then
  add_result "Network" "PASS" "NET-01" "firewalld active" "firewalld actif" "firewalld: running" ""
elif svc_active ufw; then
  add_result "Network" "PASS" "NET-01" "ufw active" "ufw actif" "ufw: running" ""
elif iptables -L INPUT -n 2>/dev/null | grep -qvE "^(Chain|target|$)"; then
  add_result "Network" "WARN" "NET-01" "iptables rules (verify)" "Règles iptables (à vérifier)" "iptables rules found" \
    "Check your iptables rules, or migrate to firewalld."
else
  add_result "Network" "FAIL" "NET-01" "No firewall active" "Aucun pare-feu actif" "No firewall detected" \
    "Enable: 'systemctl enable --now firewalld'"
fi

# NET-02 IP Forwarding
IPF=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "?")
if [[ "$IPF" == "0" ]]; then
  add_result "Network" "PASS" "NET-02" "IP forwarding disabled" "Transfert IP désactivé" "ip_forward=0" ""
else
  add_result "Network" "WARN" "NET-02" "IP forwarding enabled" "Transfert IP activé" "ip_forward=$IPF" \
    "Disable if unused: 'sysctl -w net.ipv4.ip_forward=0'"
fi

# NET-03 ICMP Redirects (accept)
ICR=$(sysctl -n net.ipv4.conf.all.accept_redirects 2>/dev/null || echo "?")
if [[ "$ICR" == "0" ]]; then
  add_result "Network" "PASS" "NET-03" "ICMP redirects disabled" "Redirections ICMP désactivées" "accept_redirects=0" ""
else
  add_result "Network" "FAIL" "NET-03" "ICMP redirects accepted" "Redirections ICMP acceptées" "accept_redirects=$ICR" \
    "Add to /etc/sysctl.d/: 'net.ipv4.conf.all.accept_redirects=0'"
fi

# NET-04 SYN Cookies
SC=$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null || echo "?")
if [[ "$SC" == "1" ]]; then
  add_result "Network" "PASS" "NET-04" "TCP SYN cookies enabled" "SYN cookies TCP activés" "tcp_syncookies=1" ""
else
  add_result "Network" "FAIL" "NET-04" "TCP SYN cookies disabled" "SYN cookies TCP désactivés" "tcp_syncookies=$SC" \
    "Enable: 'sysctl -w net.ipv4.tcp_syncookies=1'"
fi

# NET-05 Dangerous services
DANGEROUS_SVCS=("telnet" "rsh" "rlogin" "ftp" "tftp" "nis" "talk" "chargen" "telnetd" "ftpd")
FOUND_SVCS=()
for svc in "${DANGEROUS_SVCS[@]}"; do
  svc_active "$svc" && FOUND_SVCS+=("$svc") || true
done
if [[ ${#FOUND_SVCS[@]} -eq 0 ]]; then
  add_result "Network" "PASS" "NET-05" "No dangerous services" "Aucun service dangereux" "telnet/ftp/rsh all inactive" ""
else
  add_result "Network" "FAIL" "NET-05" "Dangerous services active" "Services dangereux actifs" "${FOUND_SVCS[*]}" \
    "Disable: 'systemctl disable --now <service>'"
fi

# NET-06 Source routing disabled
SRC_ROUTE=$(sysctl -n net.ipv4.conf.all.accept_source_route 2>/dev/null || echo "?")
if [[ "$SRC_ROUTE" == "0" ]]; then
  add_result "Network" "PASS" "NET-06" "Source routing disabled" "Routage source désactivé" "accept_source_route=0" ""
else
  add_result "Network" "FAIL" "NET-06" "Source routing enabled" "Routage source activé" "accept_source_route=$SRC_ROUTE" \
    "Add: 'net.ipv4.conf.all.accept_source_route=0' to /etc/sysctl.d/"
fi

# NET-07 Send redirects disabled
SEND_REDIR=$(sysctl -n net.ipv4.conf.all.send_redirects 2>/dev/null || echo "?")
if [[ "$SEND_REDIR" == "0" ]]; then
  add_result "Network" "PASS" "NET-07" "Send redirects disabled" "Envoi redirections ICMP désactivé" "send_redirects=0" ""
else
  add_result "Network" "FAIL" "NET-07" "Send redirects enabled" "Envoi redirections ICMP activé" "send_redirects=$SEND_REDIR" \
    "Add: 'net.ipv4.conf.all.send_redirects=0' to /etc/sysctl.d/"
fi

# NET-08 Martian packet logging
MARTIAN=$(sysctl -n net.ipv4.conf.all.log_martians 2>/dev/null || echo "?")
if [[ "$MARTIAN" == "1" ]]; then
  add_result "Network" "PASS" "NET-08" "Martian packet logging enabled" "Journalisation paquets Martien active" "log_martians=1" ""
else
  add_result "Network" "WARN" "NET-08" "Martian packet logging disabled" "Paquets Martien non journalisés" "log_martians=$MARTIAN" \
    "Enable: 'net.ipv4.conf.all.log_martians=1' in /etc/sysctl.d/"
fi

# NET-09 Reverse path filtering
RP_FILTER=$(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null || echo "?")
if [[ "$RP_FILTER" == "1" || "$RP_FILTER" == "2" ]]; then
  add_result "Network" "PASS" "NET-09" "Reverse path filtering enabled" "Filtrage chemin inverse actif" "rp_filter=$RP_FILTER" ""
else
  add_result "Network" "FAIL" "NET-09" "Reverse path filtering disabled" "Filtrage chemin inverse inactif" "rp_filter=$RP_FILTER" \
    "Enable: 'net.ipv4.conf.all.rp_filter=1' in /etc/sysctl.d/"
fi

# NET-10 IPv6 router advertisements disabled
IPV6_RA=$(sysctl -n net.ipv6.conf.all.accept_ra 2>/dev/null || echo "0")
if [[ "$IPV6_RA" == "0" ]]; then
  add_result "Network" "PASS" "NET-10" "IPv6 RA disabled" "Annonces routeur IPv6 désactivées" "accept_ra=0" ""
else
  add_result "Network" "WARN" "NET-10" "IPv6 RA accepted" "Annonces routeur IPv6 acceptées" "accept_ra=$IPV6_RA" \
    "If IPv6 is not required: 'net.ipv6.conf.all.accept_ra=0' in /etc/sysctl.d/"
fi

# NET-11 ICMP broadcast ignored
BCAST_ICMP=$(sysctl -n net.ipv4.icmp_echo_ignore_broadcasts 2>/dev/null || echo "?")
if [[ "$BCAST_ICMP" == "1" ]]; then
  add_result "Network" "PASS" "NET-11" "ICMP broadcast ignored" "Broadcast ICMP ignoré" "icmp_echo_ignore_broadcasts=1" ""
else
  add_result "Network" "WARN" "NET-11" "ICMP broadcast not ignored" "Broadcast ICMP non ignoré" "icmp_echo_ignore_broadcasts=$BCAST_ICMP" \
    "Enable: 'net.ipv4.icmp_echo_ignore_broadcasts=1' in /etc/sysctl.d/"
fi

# NET-13 IPv6 fully disabled (CIS 3.3.1)
IPV6_ALL=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo "0")
IPV6_DEF=$(sysctl -n net.ipv6.conf.default.disable_ipv6 2>/dev/null || echo "0")
if [[ "$IPV6_ALL" == "1" && "$IPV6_DEF" == "1" ]]; then
  add_result "Network" "PASS" "NET-13" "IPv6 fully disabled" "IPv6 entièrement désactivé" "disable_ipv6=1 (all + default)" ""
else
  add_result "Network" "WARN" "NET-13" "IPv6 not disabled" "IPv6 non désactivé" "all=$IPV6_ALL default=$IPV6_DEF" \
    "Add to /etc/sysctl.d/99-cis-ipv6.conf: net.ipv6.conf.all.disable_ipv6=1 and net.ipv6.conf.default.disable_ipv6=1"
fi

# NET-12 Wireless interfaces disabled (CIS 3.1.2)
_WIRELESS_OK=false
# Check rfkill (Ubuntu/Debian)
if command -v rfkill &>/dev/null 2>&1; then
  _RF_OUT=$(rfkill list wifi 2>/dev/null || echo "")
  if [[ -z "$_RF_OUT" || "$_RF_OUT" == *"Soft blocked: yes"* || "$_RF_OUT" == *"Hard blocked: yes"* ]]; then
    _WIRELESS_OK=true
  fi
fi
# Check nmcli (RHEL/NetworkManager)
if command -v nmcli &>/dev/null 2>&1; then
  _NM_OUT=$(nmcli radio all 2>/dev/null || echo "")
  [[ "$_NM_OUT" == *"disabled"* ]] && _WIRELESS_OK=true
fi
# Check kernel module blacklist (defense-in-depth fallback)
if grep -rqsE "blacklist\s+(iwlwifi|cfg80211|mac80211)" /etc/modprobe.d/ 2>/dev/null; then
  _WIRELESS_OK=true
fi
if $_WIRELESS_OK; then
  add_result "Network" "PASS" "NET-12" "Wireless interfaces disabled" "Interfaces sans-fil désactivées" "rfkill/nmcli/modprobe blacklist confirmed" ""
else
  add_result "Network" "WARN" "NET-12" "Wireless not disabled" "Interfaces sans-fil actives" "No rfkill block, nmcli disable, or module blacklist found" \
    "Disable: 'rfkill block wifi' (Ubuntu) or 'nmcli radio all off' (RHEL), plus blacklist iwlwifi in /etc/modprobe.d/"
fi
}

_checks_logging() {
# =============================================================================
#  6. LOGGING & AUDIT
# =============================================================================
section "6. LOGGING & AUDIT"

# LOG-01 auditd
if svc_active auditd; then
  add_result "Logging" "PASS" "LOG-01" "auditd running" "auditd actif" "auditd: active" ""
else
  add_result "Logging" "FAIL" "LOG-01" "auditd not running" "auditd inactif" "auditd: inactive" \
    "Enable: 'systemctl enable --now auditd'"
fi

# LOG-02 syslog
if svc_active rsyslog || svc_active syslog || svc_active systemd-journald; then
  add_result "Logging" "PASS" "LOG-02" "System logging active" "Journalisation active" "rsyslog/journald running" ""
else
  add_result "Logging" "FAIL" "LOG-02" "No system logging" "Journalisation inactive" "rsyslog/journald inactive" \
    "Enable: 'systemctl enable --now rsyslog'"
fi

# LOG-03 logrotate
if [[ -f /etc/logrotate.conf ]]; then
  add_result "Logging" "PASS" "LOG-03" "logrotate configured" "Rotation logs configurée" "/etc/logrotate.conf present" ""
else
  add_result "Logging" "WARN" "LOG-03" "logrotate not found" "Rotation logs absente" "No logrotate.conf" \
    "Install: 'dnf install logrotate'"
fi

# LOG-04 Audit rules
if cmd_exists auditctl; then
  AUDIT_RULES=$(auditctl -l 2>/dev/null | grep -cE "execve|chmod|chown|delete|login|sudo" || true)
  AUDIT_RULES=${AUDIT_RULES:-0}
  if [[ "$AUDIT_RULES" -ge 3 ]]; then
    add_result "Logging" "PASS" "LOG-04" "Audit rules configured" "Règles d'audit présentes" "$AUDIT_RULES rules found" ""
  else
    add_result "Logging" "WARN" "LOG-04" "Few audit rules" "Peu de règles d'audit" "$AUDIT_RULES rule(s)" \
      "Add rules under /etc/audit/rules.d/ (see the cyberaar.hardening Ansible roles)."
  fi
else
  add_result "Logging" "WARN" "LOG-04" "auditctl not available" "auditctl indisponible" "Cannot check rules" \
    "Install: 'dnf install audit'"
fi

# LOG-05 Audit log max size configured
AUDITD_CONF="/etc/audit/auditd.conf"
if [[ -f "$AUDITD_CONF" ]]; then
  MAX_LOG=$(grep -E "^\s*max_log_file\s*=" "$AUDITD_CONF" 2>/dev/null | \
    awk -F= '{print $2}' | tr -d ' ' | head -1 || echo "")
  if [[ -n "$MAX_LOG" && "$MAX_LOG" -ge 8 ]]; then
    add_result "Logging" "PASS" "LOG-05" "Audit log max size >= 8 MB" "Taille max log audit ≥ 8 Mo" "max_log_file=${MAX_LOG}MB" ""
  else
    add_result "Logging" "WARN" "LOG-05" "Audit log max size too small" "Taille max log audit insuffisante" "max_log_file=${MAX_LOG:-not set}" \
      "Set 'max_log_file = 8' in /etc/audit/auditd.conf"
  fi
else
  add_result "Logging" "WARN" "LOG-05" "auditd.conf not found" "auditd.conf introuvable" "Not at /etc/audit/auditd.conf" \
    "Install auditd: 'dnf install audit'"
fi

# LOG-06 Kernel audit=1 at boot
if grep -qE '\baudit=1\b' /proc/cmdline 2>/dev/null; then
  add_result "Logging" "PASS" "LOG-06" "Kernel audit enabled at boot" "Audit noyau activé au boot" "audit=1 in kernel cmdline" ""
else
  add_result "Logging" "WARN" "LOG-06" "Kernel audit not enabled at boot" "Audit noyau absent au boot" "audit=1 missing from /proc/cmdline" \
    "Add 'audit=1' to GRUB_CMDLINE_LINUX in /etc/default/grub, then regenerate grub.cfg"
fi

# LOG-07 journald persistent storage
if [[ -d /var/log/journal ]]; then
  add_result "Logging" "PASS" "LOG-07" "journald persistent storage" "Journald persistant" "/var/log/journal exists" ""
else
  add_result "Logging" "WARN" "LOG-07" "journald not persistent" "Journald non persistant" "/var/log/journal absent (volatile)" \
    "Enable: 'mkdir -p /var/log/journal && systemd-tmpfiles --create --prefix /var/log/journal'"
fi

# LOG-09 journald Storage=persistent configured (CIS 4.2.1.1)
_JD_STORAGE=$(grep -rshE '^\s*Storage\s*=' /etc/systemd/journald.conf /etc/systemd/journald.conf.d/*.conf 2>/dev/null | \
  awk -F= '{print $2}' | tr -d ' ' | tail -1)
if [[ "$_JD_STORAGE" == "persistent" || "$_JD_STORAGE" == "auto" ]]; then
  add_result "Logging" "PASS" "LOG-09" "journald Storage configured" "Stockage journald configuré" "Storage=$_JD_STORAGE" ""
else
  add_result "Logging" "WARN" "LOG-09" "journald Storage not set" "Stockage journald non configuré" "Storage=${_JD_STORAGE:-not set}" \
    "Create /etc/systemd/journald.conf.d/99-cis-journald.conf with Storage=persistent"
fi

# LOG-10 journald rate limiting configured (CIS 4.2.1.3)
_JD_BURST=$(grep -rshE '^\s*RateLimitBurst\s*=' /etc/systemd/journald.conf /etc/systemd/journald.conf.d/*.conf 2>/dev/null | \
  awk -F= '{print $2}' | tr -d ' ' | tail -1)
if [[ -n "$_JD_BURST" && "$_JD_BURST" -gt 0 ]] 2>/dev/null; then
  add_result "Logging" "PASS" "LOG-10" "journald rate limiting configured" "Limitation débit journald configurée" "RateLimitBurst=$_JD_BURST" ""
else
  add_result "Logging" "WARN" "LOG-10" "journald rate limiting not set" "Limitation débit journald absente" "RateLimitBurst=${_JD_BURST:-not set}" \
    "Add RateLimitBurst=10000 and RateLimitInterval=30s to /etc/systemd/journald.conf.d/99-cis-journald.conf"
fi

# LOG-08 Remote syslog configured (informational, no Ansible remediation)
REMOTE_LOG=false
if [[ -f /etc/rsyslog.conf ]] || [[ -d /etc/rsyslog.d ]]; then
  grep -rqE '@@?[0-9a-zA-Z]|action\(type="omfwd"' /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null && REMOTE_LOG=true
fi
if $REMOTE_LOG; then
  add_result "Logging" "PASS" "LOG-08" "Remote syslog configured" "Syslog distant configuré" "Remote forwarding found in rsyslog" ""
else
  add_result "Logging" "WARN" "LOG-08" "No remote syslog" "Pas de syslog distant" "Logs stored locally only" \
    "Configure a remote syslog server in /etc/rsyslog.d/ so logs are centralised."
fi
}

_checks_integrity() {
# =============================================================================
#  7. INTEGRITY & MALWARE
# =============================================================================
section "7. INTEGRITY & MALWARE"

# INT-01 AIDE installed
if cmd_exists aide || cmd_exists aide2; then
  add_result "Integrity" "PASS" "INT-01" "AIDE installed" "AIDE installé" "File integrity monitor present" ""
else
  add_result "Integrity" "WARN" "INT-01" "AIDE not installed" "AIDE non installé" "No file integrity monitor" \
    "Install: 'dnf install aide && aide --init'"
fi

# INT-02 Rootkit scanner (manual verification required)
if cmd_exists rkhunter || cmd_exists chkrootkit; then
  add_result "Integrity" "PASS" "INT-02" "Rootkit scanner present" "Scanner rootkit présent" "rkhunter/chkrootkit found (run manually)" ""
else
  add_result "Integrity" "WARN" "INT-02" "No rootkit scanner" "Aucun scanner rootkit" "rkhunter/chkrootkit absent" \
    "Install: 'dnf install rkhunter', then run 'rkhunter --check' by hand."
fi

# INT-03 Suspicious cron entries
SUSP_CRON=$(grep -rE '(wget|curl|bash|nc |ncat|python|perl).*(http|/tmp)' \
  /etc/cron* /var/spool/cron/ 2>/dev/null | grep -vc '^#' || true)
SUSP_CRON=${SUSP_CRON:-0}
if [[ "$SUSP_CRON" -eq 0 ]]; then
  add_result "Integrity" "PASS" "INT-03" "No suspicious cron entries" "Crons propres" "Crontabs look clean" ""
else
  add_result "Integrity" "FAIL" "INT-03" "Suspicious cron entries" "Crons suspects détectés" "$SUSP_CRON entry/entries (manual review required)" \
    "Audit: 'crontab -l' and /etc/cron*, look for wget/curl/bash fetching into /tmp."
fi

# INT-04 Open listening ports (informational, manual review required).
# A bare count is not reviewable: what matters is which services face the
# network. Separate the listeners bound to ALL interfaces (0.0.0.0 / :: / *) --
# reachable from every network the host is on, held off each one only by a
# firewall -- from those bound to loopback, and name the all-interface ports so
# the reviewer sees the actual surface rather than a number. Still unmapped:
# binding a service to the right interface is app-specific, not a role a
# playbook can apply safely, so this stays a human review.
INT04_LISTEN=$(ss -tlnH 2>/dev/null || true)
INT04_ALLP=$(printf '%s\n' "$INT04_LISTEN" | awk '{print $4}' \
  | grep -E '^(0\.0\.0\.0|\*|\[::\]):[0-9]+$' | sed -E 's/.*:([0-9]+)$/\1/' \
  | sort -un | tr '\n' ' ' | sed 's/ *$//')
INT04_ALL=$(printf '%s' "$INT04_ALLP" | wc -w | tr -d ' ')
INT04_LO=$(printf '%s\n' "$INT04_LISTEN" | awk '{print $4}' | grep -cE '^(127\.|\[::1\])' || true)
INT04_LO=${INT04_LO:-0}
if [[ "$INT04_ALL" -gt 0 ]]; then
  INT04_DETAIL="$INT04_ALL on all interfaces (ports: $INT04_ALLP), $INT04_LO loopback-only"
else
  INT04_TOTAL=$(printf '%s\n' "$INT04_LISTEN" | grep -c . || true)
  INT04_DETAIL="${INT04_TOTAL:-0} listening, none on all interfaces ($INT04_LO loopback-only)"
fi
add_result "Integrity" "WARN" "INT-04" "Open listening ports" "Ports en écoute (revue manuelle)" "$INT04_DETAIL" \
  "Manual review: 'ss -tlnp'. Every all-interfaces (0.0.0.0/::) listener is reachable from every network the host is on, limited only by the firewall; bind services that need only local or one-network access to 127.0.0.1 or that interface, and close the rest."

# INT-05 Package manager GPG/signature check
PKG_GPG_OK=false
if [[ -f /etc/dnf/dnf.conf ]] || [[ -d /etc/yum.repos.d ]]; then
  GPGCHECK_OFF=$(grep -rE "^\s*gpgcheck\s*=\s*0" \
    /etc/dnf/dnf.conf /etc/yum.conf /etc/yum.repos.d/*.repo 2>/dev/null | wc -l)
  [[ "$GPGCHECK_OFF" -eq 0 ]] && PKG_GPG_OK=true
elif cmd_exists apt-get; then
  UNAUTH=$(grep -rE "AllowUnauthenticated\s+true" \
    /etc/apt/apt.conf /etc/apt/apt.conf.d/ 2>/dev/null | wc -l)
  [[ "$UNAUTH" -eq 0 ]] && PKG_GPG_OK=true
else
  PKG_GPG_OK=true  # Cannot determine, assume OK
fi
if $PKG_GPG_OK; then
  add_result "Integrity" "PASS" "INT-05" "Package signature check enabled" "Vérif signature paquets active" "gpgcheck enforced" ""
else
  add_result "Integrity" "FAIL" "INT-05" "Package signature check disabled" "Vérif signature paquets désactivée" "gpgcheck=0 found" \
    "Enable: 'gpgcheck=1' in /etc/dnf/dnf.conf and every .repo file"
fi

# INT-06 fail2ban running
if svc_active fail2ban; then
  add_result "Integrity" "PASS" "INT-06" "fail2ban running" "fail2ban actif" "fail2ban: active" ""
else
  add_result "Integrity" "WARN" "INT-06" "fail2ban not running" "fail2ban inactif" "fail2ban: inactive or not installed" \
    "Install and enable: 'dnf install fail2ban && systemctl enable --now fail2ban'"
fi

# INT-07 AIDE database initialized
AIDE_DB_OK=false
for _aide_db in /var/lib/aide/aide.db.gz /var/lib/aide/aide.db /var/lib/aide/aide.db.new.gz; do
  [[ -f "$_aide_db" ]] && AIDE_DB_OK=true && break
done
if $AIDE_DB_OK; then
  add_result "Integrity" "PASS" "INT-07" "AIDE database initialized" "Base AIDE initialisée" "aide.db found" ""
elif cmd_exists aide || cmd_exists aide2; then
  add_result "Integrity" "FAIL" "INT-07" "AIDE installed but DB missing" "AIDE installé sans base de données" "aide.db not found" \
    "Initialise: 'aide --init && cp /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz'"
else
  # Do not restate INT-01 here. When AIDE is absent both checks used to emit
  # the identical title "AIDE not installed", so one missing package produced
  # two warnings that read as two problems, and a reader counting findings
  # counted it twice. The verdict is still WARN, because the machine genuinely
  # has no integrity database; only the wording changes, to say which finding
  # it follows from.
  add_result "Integrity" "WARN" "INT-07" "AIDE database not initialised" \
    "Base AIDE non initialisée" "AIDE is not installed, see INT-01" \
    "Install AIDE first: 'dnf install aide && aide --init'"
fi

# INT-08 Cron directory permissions (not world-writable)
CRON_DIR_ISSUES=""
for _cdir in /etc/cron.d /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.hourly; do
  [[ -d "$_cdir" ]] || continue
  _CDIR_P=$(stat -c "%a" "$_cdir" 2>/dev/null || echo "")
  # World-writable = last octet is 2,3,6,7
  echo "$_CDIR_P" | grep -qE "^[0-9][0-9][2367]" && \
    CRON_DIR_ISSUES="${CRON_DIR_ISSUES:+$CRON_DIR_ISSUES, }$_cdir ($_CDIR_P)"
done
if [[ -z "$CRON_DIR_ISSUES" ]]; then
  add_result "Integrity" "PASS" "INT-08" "Cron directories not world-writable" "Répertoires cron sécurisés" "cron.d and cron.* OK" ""
else
  add_result "Integrity" "FAIL" "INT-08" "Cron directory world-writable" "Répertoires cron inscriptibles par tous" "$CRON_DIR_ISSUES" \
    "Fix: 'chmod 700 /etc/cron.d /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.hourly'"
fi
}

_checks_compliance() {
# =============================================================================
#  8. COMPLIANCE & POLICY
# =============================================================================
section "8. COMPLIANCE & POLICY"

# COMP-01 Legal banner /etc/issue.net
if [[ -f /etc/issue.net ]]; then
  BANNER_LINES=$(wc -l < /etc/issue.net 2>/dev/null || echo 0)
  if [[ "$BANNER_LINES" -ge 2 ]]; then
    add_result "Compliance" "PASS" "COMP-01" "Legal banner configured (/etc/issue.net)" "Bannière légale configurée" "${BANNER_LINES} line(s)" ""
  else
    add_result "Compliance" "WARN" "COMP-01" "Legal banner too short" "Bannière légale trop courte" "${BANNER_LINES} line(s) in /etc/issue.net" \
      "Add an authorised-access warning to /etc/issue.net (at least 2 lines)"
  fi
else
  add_result "Compliance" "WARN" "COMP-01" "No legal banner (/etc/issue.net)" "Bannière légale absente" "/etc/issue.net missing" \
    "Create /etc/issue.net with a legal warning message."
fi

# COMP-02 /tmp on dedicated partition or tmpfs
TMP_DEDICATED=false
grep -qE '\s/tmp\s' /etc/fstab 2>/dev/null && TMP_DEDICATED=true
grep -qE 'tmpfs\s+/tmp' /proc/mounts 2>/dev/null && TMP_DEDICATED=true
if $TMP_DEDICATED; then
  add_result "Compliance" "PASS" "COMP-02" "/tmp on dedicated partition/tmpfs" "/tmp partition dédiée" "Separate /tmp mount found" ""
else
  add_result "Compliance" "WARN" "COMP-02" "/tmp not on dedicated partition" "/tmp non isolé" "/tmp not separately mounted" \
    "Isolate /tmp: add 'tmpfs /tmp tmpfs defaults,noexec,nosuid,nodev 0 0' to /etc/fstab"
fi

# COMP-03 /home on separate partition (informational, cannot change post-install)
HOME_PART=$(grep -cE '\s/home\s' /proc/mounts 2>/dev/null || true)
HOME_PART=${HOME_PART:-0}
if [[ "$HOME_PART" -ge 1 ]]; then
  add_result "Compliance" "PASS" "COMP-03" "/home on separate partition" "/home partition dédiée" "Separate /home mount" ""
else
  add_result "Compliance" "WARN" "COMP-03" "/home not on separate partition" "/home non isolé" "Shared with / partition (manual review)" \
    "Manual review: putting /home on its own partition is recommended (CIS 1.1.18)"
fi

# COMP-04 /var on separate partition (informational, cannot change post-install)
VAR_PART=$(grep -cE '\s/var\s' /proc/mounts 2>/dev/null || true)
VAR_PART=${VAR_PART:-0}
if [[ "$VAR_PART" -ge 1 ]]; then
  add_result "Compliance" "PASS" "COMP-04" "/var on separate partition" "/var partition dédiée" "Separate /var mount" ""
else
  add_result "Compliance" "WARN" "COMP-04" "/var not on separate partition" "/var non isolé" "Shared with / partition (manual review)" \
    "Manual review: a separate /var stops logs filling / (CIS 1.1.12)"
fi

# COMP-05 Default umask hardened (027 or stricter)
UMASK_VAL=""
while IFS= read -r _um; do
  [[ "$_um" =~ ^0?(027|077)$ ]] && UMASK_VAL="$_um" && break
done < <(grep -rE "^\s*(umask|UMASK)\s+" \
  /etc/profile /etc/profile.d/*.sh /etc/bashrc /etc/bash.bashrc /etc/login.defs 2>/dev/null | \
  grep -v "^#" | grep -oE '[0-7]{3,4}')
if [[ -n "$UMASK_VAL" ]]; then
  add_result "Compliance" "PASS" "COMP-05" "Umask 027 or stricter" "Umask 027 ou plus restrictif" "umask=$UMASK_VAL" ""
else
  _RAW_UMASK=$(grep -rE "^\s*(umask|UMASK)\s+" \
    /etc/profile /etc/profile.d/*.sh /etc/bashrc /etc/bash.bashrc /etc/login.defs 2>/dev/null | \
    grep -v "^#" | grep -oE '[0-7]{3,4}' | head -1 || echo "022 (default)")
  add_result "Compliance" "WARN" "COMP-05" "Umask too permissive" "Umask trop permissif" "umask=${_RAW_UMASK}" \
    "Set 'umask 027' in /etc/profile.d/umask.sh: it protects newly created files."
fi

# COMP-06 ASLR fully enabled
ASLR=$(sysctl -n kernel.randomize_va_space 2>/dev/null || echo "?")
if [[ "$ASLR" == "2" ]]; then
  add_result "Compliance" "PASS" "COMP-06" "ASLR fully enabled" "ASLR activé (niveau 2)" "randomize_va_space=2" ""
elif [[ "$ASLR" == "1" ]]; then
  add_result "Compliance" "WARN" "COMP-06" "ASLR partial (level 1)" "ASLR partiel" "randomize_va_space=1 (prefer 2)" \
    "Enable level 2: 'sysctl -w kernel.randomize_va_space=2'"
else
  add_result "Compliance" "FAIL" "COMP-06" "ASLR disabled" "ASLR désactivé" "randomize_va_space=$ASLR" \
    "Enable ASLR: 'sysctl -w kernel.randomize_va_space=2'"
fi

# COMP-07 Kernel pointer restriction
KPTR=$(sysctl -n kernel.kptr_restrict 2>/dev/null || echo "?")
if [[ "$KPTR" == "2" ]]; then
  add_result "Compliance" "PASS" "COMP-07" "Kernel pointers hidden (kptr_restrict=2)" "Pointeurs noyau cachés" "kptr_restrict=2" ""
elif [[ "$KPTR" == "1" ]]; then
  add_result "Compliance" "WARN" "COMP-07" "Kernel pointers partially restricted" "Pointeurs noyau partiellement restreints" "kptr_restrict=1 (prefer 2)" \
    "Harden it: 'sysctl -w kernel.kptr_restrict=2'"
else
  add_result "Compliance" "FAIL" "COMP-07" "Kernel pointers exposed" "Pointeurs noyau exposés" "kptr_restrict=$KPTR" \
    "Enable: 'sysctl -w kernel.kptr_restrict=2' in /etc/sysctl.d/"
fi

# COMP-08 dmesg restriction
DMESG=$(sysctl -n kernel.dmesg_restrict 2>/dev/null || echo "?")
if [[ "$DMESG" == "1" ]]; then
  add_result "Compliance" "PASS" "COMP-08" "dmesg restricted to root" "dmesg restreint à root" "dmesg_restrict=1" ""
else
  add_result "Compliance" "WARN" "COMP-08" "dmesg not restricted" "dmesg accessible à tous" "dmesg_restrict=$DMESG" \
    "Enable: 'sysctl -w kernel.dmesg_restrict=1'"
fi

# COMP-09 ptrace scope restricted
PTRACE=$(sysctl -n kernel.yama.ptrace_scope 2>/dev/null || echo "?")
if [[ "$PTRACE" =~ ^[1-3]$ ]]; then
  add_result "Compliance" "PASS" "COMP-09" "ptrace scope restricted" "ptrace restreint" "ptrace_scope=$PTRACE" ""
else
  add_result "Compliance" "WARN" "COMP-09" "ptrace unrestricted" "ptrace non restreint" "ptrace_scope=${PTRACE:-0}" \
    "Enable: 'sysctl -w kernel.yama.ptrace_scope=1'"
fi

# COMP-10 USB storage module blacklisted
if grep -rqsE "blacklist\s+usb.storage|blacklist\s+usb_storage" /etc/modprobe.d/ 2>/dev/null; then
  add_result "Compliance" "PASS" "COMP-10" "USB storage blacklisted" "Stockage USB désactivé" "usb_storage in modprobe blacklist" ""
else
  add_result "Compliance" "WARN" "COMP-10" "USB storage not blacklisted" "Stockage USB non désactivé" "usb_storage module loadable" \
    "Add 'blacklist usb-storage' to /etc/modprobe.d/blacklist.conf (unless this is a workstation)"
fi

# COMP-11 cron service enabled (CIS 5.1.1)
_CRON_SVC="crond"
systemctl list-units --type=service 2>/dev/null | grep -q "^.*cron\.service" && _CRON_SVC="cron"
if systemctl is-enabled "$_CRON_SVC" &>/dev/null && systemctl is-active "$_CRON_SVC" &>/dev/null; then
  add_result "Compliance" "PASS" "COMP-11" "Cron service enabled and running" "Service cron actif" "$_CRON_SVC: enabled + active" ""
else
  add_result "Compliance" "WARN" "COMP-11" "Cron service not active" "Service cron inactif" "$_CRON_SVC not running or not enabled" \
    "Enable: 'systemctl enable --now cron' (Ubuntu) or 'systemctl enable --now crond' (RHEL)"
fi

# COMP-12 cron.allow and at.allow exist (CIS 5.1.8 / 5.1.9)
_CRON_ALLOW=true
_CRON_ALLOW_DETAIL=""
[[ -f /etc/cron.allow ]] || { _CRON_ALLOW=false; _CRON_ALLOW_DETAIL="/etc/cron.allow missing"; }
[[ -f /etc/at.allow ]]   || { _CRON_ALLOW=false; _CRON_ALLOW_DETAIL="${_CRON_ALLOW_DETAIL:+$_CRON_ALLOW_DETAIL, }/etc/at.allow missing"; }
if $_CRON_ALLOW; then
  add_result "Compliance" "PASS" "COMP-12" "cron.allow and at.allow configured" "Accès cron/at restreint" "allow-list model enforced" ""
else
  add_result "Compliance" "WARN" "COMP-12" "cron/at allow-list not enforced" "Accès cron/at non restreint" "${_CRON_ALLOW_DETAIL}" \
    "Create /etc/cron.allow and /etc/at.allow (empty = root only) and remove cron.deny/at.deny (CIS 5.1.8-5.1.9)"
fi
}

# =============================================================================
#  TERMINAL RENDERERS
#  _render_summary  — score box + Ansible remediation plan (terminal)
#  _ansible_terminal_plan — detailed per-check plan (called by _render_summary)
# =============================================================================

_ansible_terminal_plan() {
  declare -A seen_plan=()
  local -a plan_keys=()
  local -a plan_vals=()

  for _id in "${FAIL_IDS[@]}" "${WARN_IDS[@]}"; do
    [[ -z "${ANSIBLE_MAP[$_id]+x}" ]] && continue
    local _entry="${ANSIBLE_MAP[$_id]}"
    IFS='|' read -r _tags _role_r _role_u _desc <<< "$_entry"
    local _key
    _key=$(echo "$_tags" | tr ',' '_')
    [[ -n "${seen_plan[$_key]+x}" ]] && continue
    seen_plan["$_key"]=1
    plan_keys+=("$_key")
    plan_vals+=("$_entry")
  done

  if [[ ${#plan_keys[@]} -eq 0 ]]; then
    printf "  ${GREEN}✅  All checks passed — no Ansible remediation needed.${NC}\n\n"
    return
  fi

  # The target is not known here: this script audits a machine, it does not read
  # an inventory. A placeholder is honest; a path relative to a git checkout is
  # not, and that is what used to be printed.
  local _tgt="<host>"
  [[ -n "$AARTOOL_TARGET" ]] && _tgt="$AARTOOL_TARGET"

  # Detect OS family for role name hint
  local _os_hint="(RHEL9 / Ubuntu — auto-detected per host)"
  grep -qi 'rhel\|centos\|almalinux\|rocky' /etc/os-release 2>/dev/null && \
    _os_hint="(RHEL9 / AlmaLinux / Rocky)"
  grep -qi 'ubuntu\|debian' /etc/os-release 2>/dev/null && \
    _os_hint="(Ubuntu / Debian)"

  printf "\n${BOLD}${CYAN}━━━  REMEDIATION  %s${NC}\n" "$(rule '━' $(( REPORT_WIDTH - 19 )) )"
  printf "  Platform: ${BOLD}%s${NC}\n\n" "$_os_hint"

  local _idx=1
  local _all_tags=""
  for _key in "${plan_keys[@]}"; do
    local _i=$(( _idx - 1 ))
    IFS='|' read -r _tags _role_r _role_u _desc <<< "${plan_vals[$_i]}"
    local _role_hint="$_role_r / $_role_u"
    grep -qi 'rhel\|centos\|almalinux\|rocky' /etc/os-release 2>/dev/null && _role_hint="$_role_r"
    grep -qi 'ubuntu\|debian' /etc/os-release 2>/dev/null && _role_hint="$_role_u"
    printf "  ${YELLOW}[%02d]${NC} ${BOLD}%-42s${NC}  tags: ${CYAN}%s${NC}\n" \
      "$_idx" "$_desc" "$_tags"
    printf "       Role  : %s\n" "$_role_hint"
    printf "       ${GREEN}aartool apply --target %s --only %s${NC}\n\n" \
      "$_tgt" "$_tags"
    # collect unique tags
    IFS=',' read -ra _t <<< "$_tags"
    for t in "${_t[@]}"; do
      [[ "$_all_tags" != *"$t"* ]] && _all_tags="${_all_tags:+$_all_tags,}$t"
    done
    (( _idx++ ))
  done

  printf "  ${BOLD}── Everything above, in one command: ────────────────────────────────────────${NC}\n"
  printf "  ${GREEN}aartool apply --target %s --only %s${NC}\n" \
    "$_tgt" "$_all_tags"
  printf "\n  ${CYAN}   Preview first. It changes nothing:${NC}\n"
  printf "  ${GREEN}aartool plan --target %s --only %s${NC}\n" \
    "$_tgt" "$_all_tags"
  printf "\n  ${CYAN}   %s is a host or group in your inventory.${NC}\n" "$_tgt"
  printf "  ${CYAN}   aartool advise orders these by what an attacker reaches first,${NC}\n"
  printf "  ${CYAN}   and says what each fix costs before you run it.${NC}\n"
  printf "${BOLD}%s${NC}\n\n" "$(rule)"
}

_render_summary() {
  printf "\n${BOLD}%s${NC}\n" "$(rule)"
  printf "${BOLD}  aartool security score: ${NC}"
  if   [[ "$SCORE" -ge 80 ]]; then printf "${GREEN}${BOLD}%s%%${NC}\n" "$SCORE"
  elif [[ "$SCORE" -ge 60 ]]; then printf "${YELLOW}${BOLD}%s%%${NC}\n" "$SCORE"
  else printf "${RED}${BOLD}%s%%${NC}\n" "$SCORE"; fi
  # Failures lead. They are the only line that means "this is wrong" rather
  # than "this could not be verified", and putting PASS first buried them.
  printf "  ${RED}%-4s failed${NC}   ${YELLOW}%-4s warnings${NC}   ${GREEN}%-4s passed${NC}   of %s checks\n" \
    "$FAIL" "$WARN" "$PASS" "$TOTAL"
  printf "  ${DIM}A warning counts as half a failure in the score.${NC}\n"
  printf "  %s  ·  %s\n" "$HOSTNAME_VAL" "$DATE_VAL"
  printf "${BOLD}%s${NC}\n" "$(rule)"

  # The remediation plan used to print here, after the score, which put the one
  # number anybody looks for in the middle of the output with 117 lines below
  # it. `aartool advise` does that job properly: ordered by what an attacker
  # reaches first, with the cost of each fix, rather than grouped by Ansible
  # tag. Duplicating it worse, in the way of the score, helped nobody.
  #
  # _ansible_terminal_plan is still defined and still used by the HTML report.
  printf "\n  ${CYAN}Next:${NC}  aartool advise   what to fix first, and what each fix costs\n"
  if [[ "${AARTOOL_HINTS:-0}" != "1" ]]; then
    printf "         ${DIM}aartool inspect --hints   a one-line fix under each finding${NC}\n"
  fi
  printf "\n"
}

# =============================================================================
#  JSON RENDERER
#  Iterates RESULT_* parallel arrays to build the JSON report file.
# =============================================================================
_render_json() {
  [[ -z "$JSON_OUT" ]] && return

  local n="${#RESULT_ID[@]}"
  local JSON_ARR="["
  for (( i=0; i<n; i++ )); do
    # JSON-escape: backslash first, then double-quote, then strip newlines
    local de="${RESULT_DETAIL[$i]//\\/\\\\}"
    de="${de//\"/\\\"}"; de="${de//$'\n'/ }"
    local re="${RESULT_REMEDIATION[$i]//\\/\\\\}"
    re="${re//\"/\\\"}"; re="${re//$'\n'/ }"
    local ne="${RESULT_NAME_EN[$i]//\\/\\\\}"
    ne="${ne//\"/\\\"}"
    JSON_ARR+="{\"id\":\"${RESULT_ID[$i]}\",\"category\":\"${RESULT_CATEGORY[$i]}\",\"status\":\"${RESULT_STATUS[$i]}\",\"wave\":$(_wave_of "${RESULT_ID[$i]}"),\"check\":\"${ne}\",\"detail\":\"${de}\",\"remediation\":\"${re}\"}"
    [[ $i -lt $((n-1)) ]] && JSON_ARR+=","
  done
  JSON_ARR+="]"

  # The tag each finding is remediated by, so a consumer of this report can
  # build a working `aartool plan --only ...` without carrying its own copy of
  # ANSIBLE_MAP. The dashboard did exactly that duplication and it is the same
  # drift that has bitten this repository three times: two places that must
  # agree, with nothing checking that they do. Only ids that appear in this
  # report are emitted, so the object stays small.
  local _j_tags="{" _j_first=1 _j_id _j_tag
  local -A _j_seen=()
  for (( i=0; i<n; i++ )); do
    _j_id="${RESULT_ID[$i]}"
    [[ -n "${_j_seen[$_j_id]:-}" ]] && continue
    _j_seen[$_j_id]=1
    _j_tag="${ANSIBLE_MAP[$_j_id]:-}"
    [[ -z "$_j_tag" ]] && continue          # deliberately unmapped, see the map
    _j_tag="${_j_tag%%|*}"                  # tags field
    _j_tag="${_j_tag%%,*}"                  # the one `--only` should use
    [[ -z "$_j_tag" ]] && continue
    [[ $_j_first -eq 0 ]] && _j_tags+=","
    _j_tags+="\"${_j_id}\":\"${_j_tag}\""
    _j_first=0
  done
  _j_tags+="}"

  # Values that come from the audited machine or from the command line. A quote
  # in any of them breaks the document or injects a key.
  local _j_host _j_os _j_inv
  _j_host=$(json_escape "$HOSTNAME_VAL")
  _j_os=$(json_escape "$OS_VAL")
  _j_inv=$(json_escape "${ANSIBLE_INVENTORY:-inventory/hosts}")

  cat > "$JSON_OUT" <<EOF
{
  "aartool": {
    "version": "${SCRIPT_VERSION}",
    "host": "${_j_host}",
    "os": "${_j_os}",
    "date": "${DATE_VAL}",
    "date_iso": "${DATE_ISO}",
    "score": ${SCORE},
    "summary": {
      "pass": ${PASS},
      "warn": ${WARN},
      "fail": ${FAIL},
      "total": ${TOTAL}
    },
    "results": ${JSON_ARR},
    "ansible_remediation": {
      "fail_ids": [$(printf '"%s",' "${FAIL_IDS[@]}" | sed 's/,$//')],
      "warn_ids": [$(printf '"%s",' "${WARN_IDS[@]}" | sed 's/,$//')],
      "playbook": "playbooks/2_configure_hardening.yml",
      "inventory": "${_j_inv}"
    },
    "remediation_tags": ${_j_tags}
  }
}
EOF
  chmod 600 "$JSON_OUT"
  printf "  📄 JSON: %s\n" "$JSON_OUT"
}

# ─── LOGO BASE64 ─────────────────────────────────────────────────────────────
# White logo (used in header and footer)
LOGO_WHITE_VAR="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MhYlAAAAAJKxKAEAAACQjEUJAAAAgGQsSgAAAAAkY1ECAAAAIBmLEgAAAADJWJQAAAAASMaiBAAAAEAyFiUAAAAAkrEoAQAAAJCMRQkAAACAZCxKAAAAACRjUQIAAAAgGYsSAAAAAMlYlAAAAABIxqIEAAAAQDIWJQAAAACSsSgBAAAAkIxFCQAAAIBkLEoAAAAAJGNRAgAAACAZixIAAAAAyViUAAAAAEjGogQAAABAMhYlAAAAAJKxKAEAAACQjEUJAAAAgGQsSgAAAAAkY1ECAAAAIBmLEgAAAADJWJQAAAAASMaiBAAAAEAyFiUAAAAAkrEoAQAAAJCMRQkAAACAZCxKAAAAACRjUQIAAAAgGYsSAAAAAMlYlAAAAABIxqIEAAAAQDIWJQAAAACSsSgBAAAAkIxFCQAAAIBkLEoAAAAAJGNRAgAAACAZixIAAAAAyViUAAAAAEjGogQAAABAMhYlAAAAAJKxKAEAAACQjEUJAAAAgGQsSgAAAAAkY1ECAAAAIBmLEgAAAADJWJQAAAAASMaiBAAAAEAyFiUAAAAAkrEoAQAAAJCMRQkAAACAZCxKAAAAACRjUQIAAAAgGYsSAAAAAMlYlAAAAABIxqIEAAAAQDIWJQAAAACSsSgBAAAAkIxFCQAAAIBkLEoAAAAAJGNRAgAAACAZixIAAAAAyViUAAAAAEjGogQAAABAMhYlAAAAAJKxKAEAAACQjEUJAAAAgGQsSgAAAAAkY1ECAAAAIBmLEgAAAADJWJQAAAAASMaiBAAAAEAyFiUAAAAAkrEoAQAAAJCMRQkAAACAZCxKAAAAACRjUQIAAAAgGYsSAAAAAMlYlAAAAABIxqIEAAAAQDIWJQAAAACSsSgBAAAAkIxFCQAAAIBkLEoAAAAAJGNRAgAAACAZixIAAAAAyViUAAAAAEjGogQAAABAMhYlAAAAAJKxKAEAAACQjEUJAAAAgGQsSgAAAAAkY1ECAAAAIBmLEgAAAADJWJQAAAAASMaiBAAAAEAyFiUAAAAAkrEoAQAAAJCMRQkAAACAZCxKAAAAACRjUQIAAAAgGYsSAAAAAMlYlAAAAABIxqIEAAAAQDIWJQAAAACSsSgBAAAAkIxFCQAAAIBkLEoAAAAAJGNRAgAAACAZixIAAAAAyViUAAAAAEjGogQAAABAMhYlAAAAAJKxKAEAAACQ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AADCSJQAAAAACCNRAgAAACCMRAkAAACAMBIlAAAAAMJIlAAAAAAII1ECAAAAIIxECQAAAIAwEiUAAAAAwkiUAAAAAAgjUQIAAAAgjEQJAAAAgDASJQAAAADCSJQAAAAACCNRAgAAACCMRAkAAACAMBIlAAAAAMJIlAAAAAAII1ECAAAAIIxECQAAAIAwEiUAAAAAwkiUAAAAAAgjUQIAAAAgjEQJAAAAgDASJQAAAADCSJQAAAAACCNRAgAAACCMRAkAAACAMBIlAAAAAMJIlAAAAAAII1ECAAAAIIxECQAAAIAwEiUAAAAAwkiUAAAAAAgjUQIAAAAgjEQJAAAAgDASJQAAAADCSJQAAAAACCNRAgAAACCMRAkAAACAMBIlAAAAAMJIlAAAAAAII1ECAAAAIIxECQAAAIAwEiUAAAAAwkiUAAAAAAgjUQIAAAAgjEQJAAAAgDASJQAAAADCSJQAAAAACCNRAgAAACCMRAkAAACAMBIlAAAAAMJIlAAAAAAII1ECAAAAIIxECQAAAIAwEiUAAAAAwkiUAAAAAAgjUQIAAAAgjEQJAAAAgDASJQAAAADCSJQAAAAACCNRAgAAACCMRAkAAACAMBIlAAAAAMJIlAAAAAAII1ECAAAAIIxECQAAAIAwEiUAAAAAwkiUAAAAAAgjUQIAAAAgjEQJAAAAgDASJQAAAADCSJQAAAAACCNRAgAAACCMRAkAAACAMBIlAAAAAMJIlAAAAAAII1ECAAAAIIxECQAAAIAwEiUAAAAAwkiUAAAAAAgjUQIAAAAgjEQJAAAAgDASJQAAAADCSJQAAAAACCNRAgAAACCMRAkAAACAMBIlAAAAAMJIlAAAAAAII1ECAAAAIIxECQAAAIAwEiUAAAAAwkiUAAAAAAgjUQIAAAAgjEQJAAAAgDASJQAAAADCSJQAAAAACCNRAgAAACCMRAkAAACAMBIlAAAAAMJIlAAAAAAII1ECAAAAIIxECQAAAIAwEiUAAAAAwkiUAAAAAAgjUQIAAAAgjEQJAAAAgDASJQAAAADCSJQAAAAACCNRAgAAACCMRAkAAACAMBIlAAAAAMJIlAAAAAAII1ECAAAAIIxECQAAAIAwEiUAAAAAwkiUAAAAAAgjUQIAAAAgjEQJAAAAgDASJQAAAADCSJQAAAAACCNRAgAAACCMRAkAAACAMBIlAAAAAMJIlAAAAAAII1ECAAAAIIxECQAAAIAwEiUAAAAAwkiUAAAAAAgjUQIAAAAgjEQJAAAAgDASJQAAAADCSJQAAAAACCNRAgAAACCMRAkAAACAMBIlAAAAAMJIlAAAAAAII1ECAAAAIIxECQAAAIAwEiUAAAAAwkiUAAAAAAgjUQIAAAAgjEQJAAAAgDASJQAAAADCSJQAAAAACCNRAgAAACCMRAkAAACAMBIlAAAAAMJIlAAAAAAII1ECAAAAIMz/B5SjPpCAVn5HAAAAAElFTkSuQmCC"



# =============================================================================
#  HTML RENDERER
#  Builds HTML_ROWS locally from RESULT_* parallel arrays, then renders the
#  full branded report via heredoc. CSS/JS unchanged from original.
# =============================================================================
_render_html() {
  [[ -z "$HTML_OUT" ]] && return

  # Build HTML result rows from RESULT_* parallel arrays
  local HTML_ROWS=""
  local _n="${#RESULT_ID[@]}"
  for (( _i=0; _i<_n; _i++ )); do
    local _h_detail _h_rem _h_name_en _badge _rem_html
    _h_detail=$(html_escape "${RESULT_DETAIL[$_i]}")
    _h_rem=$(html_escape "${RESULT_REMEDIATION[$_i]}")
    _h_name_en=$(html_escape "${RESULT_NAME_EN[$_i]}")
    case "${RESULT_STATUS[$_i]}" in
      PASS) _badge="<span class='badge pass'>✅ PASS</span>" ;;
      WARN) _badge="<span class='badge warn'>⚠️ WARN</span>" ;;
      FAIL) _badge="<span class='badge fail'>❌ FAIL</span>" ;;
    esac
    _rem_html=""
    [[ "${RESULT_STATUS[$_i]}" != "PASS" && -n "${RESULT_REMEDIATION[$_i]}" ]] && \
      _rem_html="<div class='remediation'>${_h_rem}</div>"
    HTML_ROWS+="<tr>"
    HTML_ROWS+="<td class='col-id'><span class='cat-label'>${RESULT_ID[$_i]}</span></td>"
    HTML_ROWS+="<td class='col-status'>${_badge}</td>"
    HTML_ROWS+="<td class='col-check'><div class='check-name'>${_h_name_en}</div></td>"
    HTML_ROWS+="<td class='col-detail'><span class='detail-val'>${_h_detail}</span>${_rem_html}</td>"
    HTML_ROWS+="</tr>"
  done

  # The score colour is chosen here, in shell, but named as a TOKEN rather than
  # baked as a hex. Three literal hexes used to be written into the document at
  # generation time, which put the single largest element on the page outside
  # the palette: it could not follow the light theme in @media print, so the
  # score ring stayed at #22c55e on white paper while everything around it
  # switched. Emitting var(--...) lets the same cascade reach it.
  #
  # Thresholds match dashboard/index.html: < 60 danger, < 80 warn, else accent.
  SC_TOKEN="--danger"
  [[ "$SCORE" -ge 60 ]] && SC_TOKEN="--warn"
  [[ "$SCORE" -ge 80 ]] && SC_TOKEN="--accent"

  RING_COLOR="var(${SC_TOKEN})"
  # The dim companion is a token too, so print gets the printable variant.
  case "$SC_TOKEN" in
    '--danger') RING_COLORALPHA='var(--fail-bg)' ;;
    '--warn')   RING_COLORALPHA='var(--warn-bg)' ;;
    *)          RING_COLORALPHA='var(--pass-bg)' ;;
  esac
  RING_OFFSET=$(python3 -c "import math; s=${SCORE}; c=2*math.pi*36; print(round(c*(1-s/100),2))" 2>/dev/null || echo '113')

  # English, like every other word in this document, the CLI, the JSON and the
  # dashboard. The page declared lang="fr" and printed CRITIQUE/FAIBLE/MOYEN
  # while rendering English check names and English remediation either side of
  # it, which read as a bug rather than as a translation.
  #
  # Label boundaries must nest inside the colour boundaries above, or the page
  # contradicts itself: at 78 this read "BON" in amber.
  SCORE_LABEL="CRITICAL"
  [[ "$SCORE" -ge 40 ]] && SCORE_LABEL="WEAK"
  [[ "$SCORE" -ge 60 ]] && SCORE_LABEL="FAIR"
  [[ "$SCORE" -ge 80 ]] && SCORE_LABEL="GOOD"
  [[ "$SCORE" -ge 90 ]] && SCORE_LABEL="STRONG"


  # Build Ansible remediation HTML
  ANSIBLE_PLAN_HTML=""
  declare -A html_plan_entries=()
  for _id in "${FAIL_IDS[@]}" "${WARN_IDS[@]}"; do
    [[ -z "${ANSIBLE_MAP[$_id]+x}" ]] && continue
    _entry="${ANSIBLE_MAP[$_id]}"
    IFS='|' read -r _tags _role_r _role_u _desc <<< "$_entry"
    _tkey=$(echo "$_tags" | tr ',' '_')
    html_plan_entries["$_tkey"]="$_entry"
  done

  # See the note in terminal.sh: this script audits a machine and has no
  # inventory, so the target is a placeholder rather than a path that only
  # resolves inside a git checkout.
  _tgt="&lt;host&gt;"
  [[ -n "$AARTOOL_TARGET" ]] && _tgt=$(html_escape "$AARTOOL_TARGET")

  _all_tags_html=""
  for _tkey in $(echo "${!html_plan_entries[@]}" | tr ' ' '\n' | sort); do
    IFS='|' read -r _tags _role_r _role_u _desc <<< "${html_plan_entries[$_tkey]}"
    _all_tags_html="${_all_tags_html:+$_all_tags_html,}$_tags"
    ANSIBLE_PLAN_HTML+="<tr class='plan-row'>"
    ANSIBLE_PLAN_HTML+="<td class='plan-desc'><strong>$_desc</strong></td>"
    ANSIBLE_PLAN_HTML+="<td class='plan-role'><code>$_role_r</code><br><small>Ubuntu: <code>$_role_u</code></small></td>"
    ANSIBLE_PLAN_HTML+="<td class='plan-tags'><span class='tag-badge'>--only $_tags</span></td>"
    ANSIBLE_PLAN_HTML+="<td class='plan-cmd'><code>aartool apply --target $_tgt --only $_tags</code></td>"
    ANSIBLE_PLAN_HTML+="</tr>"
  done
  _all_tags_html=$(echo "$_all_tags_html" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
  ANSIBLE_CONSOLIDATED_CMD="aartool apply --target ${_tgt} --only ${_all_tags_html}"

# Values that come from the audited machine, not from this script. hostname and
# PRETTY_NAME in /etc/os-release are both settable by root on the target, so on
# any report generated for a host you do not control they are attacker input.
# Harmless while the tool audits the machine it runs on; not harmless the moment
# a report is produced for someone else or served from a web front end.
_h_host=$(html_escape "$HOSTNAME_VAL")
_h_os=$(html_escape "$OS_VAL")

cat > "$HTML_OUT" <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>aartool: ${_h_host}</title>
<style>
/* ── Design Tokens ───────────────────────────────────────────────────────────
   These are the tokens from dashboard/index.html, which are in turn the tokens
   from website/src/styles/global.css. There is no second CyberAar palette.

   This file used to carry its own teal and a lime green that appear nowhere
   else in the product. A report and the dashboard that loads it are the same
   tool and should not look like two.

   No webfonts. This document is opened on air-gapped machines, and a <link> to
   fonts.googleapis.com told a third party the IP and referrer of whoever opened
   an audit report. The system stacks below are the dashboard's, verbatim.
   ────────────────────────────────────────────────────────────────────────── */
:root {
  --bg:        #080d1a;
  --surface:   #0d1526;
  --surface-2: #111c30;
  --border:    rgba(255, 255, 255, 0.08);
  --border-2:  rgba(255, 255, 255, 0.14);
  --text:      #e2e8f0;
  --muted:     #94a3b8;
  --accent:    #00e5b0;
  --warn:      #f59e0b;
  --danger:    #ef4444;
  --info:      #38bdf8;

  --mono: ui-monospace, SFMono-Regular, "DejaVu Sans Mono", Menlo, Consolas, monospace;
  --sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Inter, sans-serif;

  /* One type scale, the dashboard's. */
  --fs-hero: 3.1rem;
  --fs-xl:   1.9rem;
  --fs-lg:   1.05rem;
  --fs-md:   0.9rem;
  --fs-sm:   0.8rem;
  --fs-xs:   0.74rem;
  --fs-2xs:  0.67rem;

  --r-sm: 5px; --r-md: 8px; --r-lg: 12px;

  /* Tinted fills. Defined per theme rather than derived, because color-mix()
     is not safe to depend on for a file whose whole point is opening on a
     machine we know nothing about. */
  --accent-dim:   rgba(0, 229, 176, .15);
  --pass-bg:      rgba(0, 229, 176, .08);
  --warn-bg:      rgba(245, 158, 11, .08);
  --fail-bg:      rgba(239, 68, 68, .08);

  /* Decorative alphas. These existed as rgba() literals of the OLD palette
     (0,194,168 = the old teal, 126,211,72 = the old lime, 13,27,62 and
     19,34,68 = the old navies), which the first port missed because it only
     looked for hex. A colour written in decimal is still a colour outside the
     palette: it does not follow @media print, so borders and glows stayed on
     the dark theme on paper. */
  --accent-glow:  rgba(0, 229, 176, .30);
  --accent-wash:  rgba(0, 229, 176, .08);
  --accent-soft:  rgba(0, 229, 176, .06);
  --accent-hover: rgba(0, 229, 176, .25);
  --pass-edge:    rgba(0, 229, 176, .25);
  --warn-edge:    rgba(245, 158, 11, .25);
  --fail-edge:    rgba(239, 68, 68, .25);
  --panel:        rgba(13, 21, 38, .90);
  --panel-hover:  rgba(17, 28, 48, .95);
  --hairline:     rgba(255, 255, 255, .05);
  --shadow:       rgba(0, 0, 0, .40);

  /* ── Aliases ───────────────────────────────────────────────────────────────
     The rules below this block are written against these names. Custom
     properties resolve at use time, so overriding only the canonical tokens in
     @media print re-colours everything through these automatically. Keep it
     that way: define a colour once, alias it here, never inline a hex below. */
  --ca-navy:      var(--bg);
  --ca-navy-mid:  var(--surface);
  --ca-navy-lt:   var(--surface-2);
  --ca-teal:      var(--accent);
  --ca-green:     var(--accent);
  --ca-teal-dim:  var(--accent-dim);
  --ca-green-dim: var(--accent-dim);
  --pass:         var(--accent);
  --fail:         var(--danger);
  --card:         var(--surface);
  --radius:       var(--r-lg);
  --font-display: var(--mono);
  --font-body:    var(--sans);
  --font-mono:    var(--mono);
}

/* ── Reset + base ────────────────────────────────────────────────────── */
*,*::before,*::after { box-sizing:border-box; margin:0; padding:0 }
html { scroll-behavior:smooth }
body {
  font-family: var(--font-body);
  background: var(--ca-navy);
  color: var(--text);
  min-height: 100vh;
  overflow-x: hidden;
  line-height: 1.6;
}

/* ── Background: logo watermark ─────────────────────────────────────── */
body::before {
  content: '';
  position: fixed;
  inset: 0;
  background:
    radial-gradient(ellipse 80% 60% at 50% -10%, var(--accent-wash) 0%, transparent 70%),
    radial-gradient(ellipse 60% 40% at 100% 100%, var(--accent-soft) 0%, transparent 60%);
  background-attachment: fixed;
  opacity: 0.04;
  pointer-events: none;
  z-index: 0;
}

.page-wrap {
  position: relative;
  z-index: 1;
  max-width: 1100px;
  margin: 0 auto;
  padding: 0 1.5rem 3rem;
}

/* ── Header ──────────────────────────────────────────────────────────── */
header {
  background: linear-gradient(135deg, var(--ca-navy-mid) 0%, var(--ca-navy-lt) 100%);
  border-bottom: 1px solid var(--border);
  padding: 1.6rem 2rem;
  margin: 0 -1.5rem 2.5rem;
  display: grid;
  grid-template-columns: auto 1fr auto;
  align-items: center;
  gap: 1.5rem;
  position: sticky;
  top: 0;
  z-index: 100;
  backdrop-filter: blur(12px);
  box-shadow: 0 4px 30px var(--shadow);
}
.header-logo img {
  height: 54px;
  width: auto;
  display: block;
  filter: drop-shadow(0 2px 8px var(--accent-glow));
}
.header-title {
  display: flex;
  flex-direction: column;
  gap: .15rem;
}
.header-title h1 {
  font-family: var(--font-display);
  font-size: 1.3rem;
  font-weight: 700;
  letter-spacing: -.01em;
  color: var(--text);
  line-height: 1.2;
}
.header-title .subtitle {
  font-size: .8rem;
  color: var(--muted);
  font-family: var(--font-mono);
}
.header-meta {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: .25rem;
  font-size: .78rem;
  color: var(--muted);
  font-family: var(--font-mono);
  white-space: nowrap;
}
.header-meta strong { color: var(--text); }
.version-badge {
  display: inline-block;
  background: var(--ca-teal-dim);
  color: var(--ca-teal);
  border: 1px solid var(--accent-glow);
  border-radius: 20px;
  padding: .1rem .6rem;
  font-size: .68rem;
  font-family: var(--font-mono);
  font-weight: 500;
  letter-spacing: .04em;
}

/* ── Score hero ──────────────────────────────────────────────────────── */
.score-hero {
  background: linear-gradient(135deg, var(--ca-navy-mid), var(--ca-navy-lt));
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 2rem 2.5rem;
  margin-bottom: 1.5rem;
  display: grid;
  grid-template-columns: auto 1fr auto;
  gap: 2rem;
  align-items: center;
  position: relative;
  overflow: hidden;
}
.score-hero::before {
  content: '';
  position: absolute;
  top: -50%;
  right: -5%;
  width: 220px;
  height: 220px;
  background: radial-gradient(circle, var(--accent-soft) 0%, transparent 70%);
  pointer-events: none;
}
.score-ring {
  position: relative;
  width: 90px;
  height: 90px;
  flex-shrink: 0;
}
.score-ring svg { width: 90px; height: 90px; transform: rotate(-90deg); }
.score-ring .track { fill: none; stroke: var(--border); stroke-width: 7; }
.score-ring .bar   { fill: none; stroke-width: 7; stroke-linecap: round;
                     stroke-dasharray: 226; stroke-dashoffset: ${RING_OFFSET};
                     stroke: ${RING_COLOR};
                     filter: drop-shadow(0 0 6px ${RING_COLORALPHA}); }
.score-ring-label {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  font-family: var(--font-display);
  font-weight: 800;
  font-size: 1.35rem;
  line-height: 1;
  color: ${RING_COLOR};
}
.score-ring-label small { font-size: .5rem; font-weight: 400; color: var(--muted); margin-top:.1rem; }
.score-hero-text h2 {
  font-family: var(--font-display);
  font-size: 1.6rem;
  font-weight: 800;
  letter-spacing: -.02em;
  margin-bottom: .35rem;
}
.score-hero-text h2 span { color: ${RING_COLOR}; }
.score-hero-text p { color: var(--muted); font-size: .88rem; max-width: 500px; }
.score-stats {
  display: flex;
  flex-direction: column;
  gap: .5rem;
  align-items: flex-end;
}
.stat-pill {
  display: flex;
  align-items: center;
  gap: .5rem;
  background: var(--hairline);
  border: 1px solid var(--border);
  border-radius: 20px;
  padding: .3rem .9rem;
  font-size: .8rem;
  font-family: var(--font-mono);
  white-space: nowrap;
}
.stat-pill .dot {
  width: 7px; height: 7px;
  border-radius: 50%;
  flex-shrink: 0;
}
.stat-pill .cnt { font-weight: 600; color: var(--text); margin-right: .1rem; }

/* ── Progress bar ────────────────────────────────────────────────────── */
.progress-wrap { margin-bottom: 2rem; }
.progress-label {
  display: flex;
  justify-content: space-between;
  font-size: .72rem;
  color: var(--muted);
  font-family: var(--font-mono);
  margin-bottom: .4rem;
}
.progress {
  background: var(--hairline);
  border-radius: 99px;
  height: 6px;
  overflow: hidden;
  position: relative;
}
.progress-bar {
  height: 100%;
  border-radius: 99px;
  background: linear-gradient(90deg, var(--ca-teal), ${RING_COLOR});
  width: ${SCORE}%;
  box-shadow: 0 0 12px ${RING_COLOR}ALPHA;
  animation: grow .9s ease-out;
}
@keyframes grow { from { width: 0 } }

/* ── Section headers ─────────────────────────────────────────────────── */
.section-title {
  font-family: var(--font-display);
  font-size: .7rem;
  font-weight: 700;
  letter-spacing: .12em;
  text-transform: uppercase;
  color: var(--ca-teal);
  padding: .5rem 0;
  margin: 2rem 0 .75rem;
  border-bottom: 1px solid var(--border);
  display: flex;
  align-items: center;
  gap: .6rem;
}
.section-title::before {
  content: '';
  display: inline-block;
  width: 3px;
  height: 16px;
  background: linear-gradient(var(--ca-teal), var(--ca-green));
  border-radius: 3px;
}

/* ── Results table ───────────────────────────────────────────────────── */
.results-table {
  width: 100%;
  border-collapse: separate;
  border-spacing: 0;
  margin-bottom: .5rem;
  font-size: .85rem;
}
.results-table thead th {
  background: var(--panel);
  padding: .6rem 1rem;
  text-align: left;
  font-family: var(--font-mono);
  font-size: .65rem;
  font-weight: 500;
  letter-spacing: .1em;
  text-transform: uppercase;
  color: var(--muted);
  border-bottom: 1px solid var(--border);
}
.results-table thead th:first-child { border-radius: var(--radius) 0 0 0; }
.results-table thead th:last-child  { border-radius: 0 var(--radius) 0 0; }
.results-table tbody tr {
  background: var(--card);
  transition: background .15s;
}
.results-table tbody tr:hover { background: var(--panel-hover); }
.results-table tbody tr + tr td { border-top: 1px solid var(--border); }
.results-table td {
  padding: .75rem 1rem;
  vertical-align: middle;
}
.results-table tbody tr:last-child td:first-child { border-radius: 0 0 0 var(--radius); }
.results-table tbody tr:last-child td:last-child  { border-radius: 0 0 var(--radius) 0; }
.col-id {
  font-family: var(--font-mono);
  font-size: .7rem;
  color: var(--muted);
  white-space: nowrap;
  width: 70px;
}
.col-status { width: 110px; }
.col-check  {}
.col-detail { width: 40%; }
.check-name {
  font-weight: 500;
  color: var(--text);
  font-size: .85rem;
}
.check-fr {
  font-size: .73rem;
  color: var(--muted);
  margin-top: .1rem;
  font-style: italic;
}
.detail-val {
  font-family: var(--font-mono);
  font-size: .78rem;
  color: var(--info);
  word-break: break-all;
}
.remediation {
  margin-top: .4rem;
  font-size: .77rem;
  color: var(--ca-teal);
  padding: .35rem .7rem;
  background: var(--ca-teal-dim);
  border-left: 2px solid var(--ca-teal);
  border-radius: 0 6px 6px 0;
  line-height: 1.5;
}
.remediation::before { content: '↳ '; font-weight: 600; }

/* ── Status badges ───────────────────────────────────────────────────── */
.badge {
  display: inline-flex;
  align-items: center;
  gap: .3rem;
  padding: .22rem .7rem;
  border-radius: 20px;
  font-size: .72rem;
  font-weight: 600;
  font-family: var(--font-mono);
  letter-spacing: .04em;
  white-space: nowrap;
}
.badge.pass { background: var(--pass-bg); color: var(--pass); border: 1px solid var(--pass-edge); }
.badge.warn { background: var(--warn-bg); color: var(--warn); border: 1px solid var(--warn-edge); }
.badge.fail { background: var(--fail-bg); color: var(--fail); border: 1px solid var(--fail-edge); }

/* ── Category label ──────────────────────────────────────────────────── */
.cat-label {
  display: inline-block;
  font-size: .68rem;
  font-family: var(--font-mono);
  color: var(--muted);
  background: var(--hairline);
  border: 1px solid var(--border);
  border-radius: 4px;
  padding: .1rem .4rem;
}

/* ── Footer ──────────────────────────────────────────────────────────── */
footer {
  margin-top: 3rem;
  padding-top: 1.5rem;
  border-top: 1px solid var(--border);
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 1.5rem;
  align-items: center;
}
.footer-logo img {
  height: 36px;
  opacity: .7;
  transition: opacity .2s;
}
.footer-logo img:hover { opacity: 1; }
.footer-text {
  font-size: .78rem;
  color: var(--muted);
}
.footer-text a { color: var(--ca-teal); text-decoration: none; }
.footer-text a:hover { text-decoration: underline; }
.footer-text strong { color: var(--text); }

/* ── Print ───────────────────────────────────────────────────────────── */
/* ── Print ───────────────────────────────────────────────────────────────────
   The README offers print-to-PDF as the way to attach an audit to an engagement
   report, and this used to be four lines that reset no colours at all. The body
   is a dark ground with near-white text; browsers do not print background
   colours by default, so #e2e8f0 landed on white paper and the document came
   out essentially blank.

   Switching to the light palette is what the dashboard does, and it is better
   than forcing black: the accent survives as a colour rather than becoming
   another shade of grey. The two accent values are not a preference, they are
   the same brand colour measured against each ground. -------------------- */
@page { size: A4; margin: 15mm 13mm; }

@media print {
  :root {
    --bg:        #ffffff;
    --surface:   #ffffff;
    --surface-2: #f8fafc;
    --border:    #e2e8f0;
    --border-2:  #cbd5e1;
    --text:      #0f172a;
    --muted:     #475569;
    --accent:    #0F766E;   /* 4.5:1 on white; #00e5b0 is 1.4:1 */
    --warn:      #b45309;   /* 5.0:1 on white; #f59e0b is 2.2:1 */
    --danger:    #b91c1c;   /* 5.9:1 on white; #ef4444 is 3.3:1 */
    --info:      #1d4ed8;

    --accent-dim:   rgba(15, 118, 110, .10);
    --pass-bg:      rgba(15, 118, 110, .07);
    --warn-bg:      rgba(180, 83, 9, .07);
    --fail-bg:      rgba(185, 28, 28, .07);

    --accent-glow:  rgba(15, 118, 110, .25);
    --accent-wash:  rgba(15, 118, 110, .06);
    --accent-soft:  rgba(15, 118, 110, .05);
    --accent-hover: rgba(15, 118, 110, .12);
    --pass-edge:    rgba(15, 118, 110, .35);
    --warn-edge:    rgba(180, 83, 9, .35);
    --fail-edge:    rgba(185, 28, 28, .35);
    --panel:        #f8fafc;
    --panel-hover:  #f1f5f9;
    --hairline:     rgba(0, 0, 0, .08);
    --shadow:       rgba(0, 0, 0, .10);
  }

  body {
    background: var(--bg);
    color: var(--text);
    font-size: 10pt;
    line-height: 1.45;
  }
  body::before { display: none }
  header { position: static }
  .progress-bar { animation: none !important }

  /* Tinted status fills carry meaning here, so ask for them to be printed
     rather than relying on the reader having ticked "background graphics". */
  .status-pass, .status-warn, .status-fail,
  .score-hero, .plan-table th, thead {
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }

  /* A finding split across a page break loses the row it belongs to. */
  tr, .finding, .plan-row { break-inside: avoid; page-break-inside: avoid; }
  h1, h2, h3 { break-after: avoid; page-break-after: avoid; }

  /* Anything interactive is noise on paper. */
  a { text-decoration: none; color: var(--accent); }
}
@media (max-width: 680px) {
  header { grid-template-columns: auto 1fr; }
  .header-meta { display: none }
  .score-hero { grid-template-columns: 1fr; }
  .score-stats { align-items: flex-start; flex-direction: row; flex-wrap: wrap; }
}

/* ── Ansible remediation plan ────────────────────────────────────────────── */
.ansible-section { margin-top: 2.5rem; }
.plan-table {
  width: 100%;
  border-collapse: separate;
  border-spacing: 0;
  font-size: .82rem;
  margin-bottom: 1rem;
}
.plan-table thead th {
  background: var(--panel);
  padding: .6rem 1rem;
  text-align: left;
  font-family: var(--font-mono);
  font-size: .65rem;
  font-weight: 500;
  letter-spacing: .1em;
  text-transform: uppercase;
  color: var(--muted);
  border-bottom: 1px solid var(--border);
}
.plan-table thead th:first-child { border-radius: var(--radius) 0 0 0; }
.plan-table thead th:last-child  { border-radius: 0 var(--radius) 0 0; }
.plan-table tbody tr { background: var(--card); transition: background .15s; }
.plan-table tbody tr:hover { background: var(--panel-hover); }
.plan-table tbody tr + tr td { border-top: 1px solid var(--border); }
.plan-table td { padding: .75rem 1rem; vertical-align: top; }
.plan-table tbody tr:last-child td:first-child { border-radius: 0 0 0 var(--radius); }
.plan-table tbody tr:last-child td:last-child  { border-radius: 0 0 var(--radius) 0; }
.plan-desc { font-weight: 500; color: var(--text); min-width: 200px; }
.plan-role code { font-family: var(--font-mono); font-size: .75rem; color: var(--ca-teal); }
.plan-role small { color: var(--muted); font-size: .7rem; }
.plan-tags { white-space: nowrap; }
.tag-badge {
  display: inline-block;
  background: var(--ca-teal-dim);
  color: var(--ca-teal);
  border: 1px solid var(--accent-glow);
  border-radius: 4px;
  padding: .15rem .5rem;
  font-family: var(--font-mono);
  font-size: .72rem;
}
.plan-cmd code {
  font-family: var(--font-mono);
  font-size: .72rem;
  color: var(--ca-green);
  word-break: break-all;
}
.consolidated-cmd {
  background: var(--accent-soft);
  border: 1px solid var(--accent-glow);
  border-radius: var(--radius);
  padding: 1rem 1.2rem;
  margin-top: 1rem;
  font-family: var(--font-mono);
  font-size: .8rem;
  color: var(--ca-green);
  word-break: break-all;
}
.consolidated-cmd .cmd-label {
  display: block;
  font-size: .65rem;
  letter-spacing: .1em;
  text-transform: uppercase;
  color: var(--muted);
  margin-bottom: .4rem;
  font-family: var(--font-body);
}
.copy-btn {
  float: right;
  background: var(--ca-teal-dim);
  border: 1px solid var(--accent-glow);
  color: var(--ca-teal);
  border-radius: 6px;
  padding: .2rem .6rem;
  font-size: .7rem;
  cursor: pointer;
  font-family: var(--font-body);
  margin-top: -.1rem;
}
.copy-btn:hover { background: var(--accent-hover); }

</style>
</head>
<body>
<div class="page-wrap">

<header>
  <div class="header-logo">
    <img src="data:image/png;base64,${LOGO_WHITE_VAR}" alt="CyberAar logo">
  </div>
  <div class="header-title">
    <h1>Security Baseline Report</h1>
    <div class="subtitle">Generated by aartool-baseline v${SCRIPT_VERSION}</div>
  </div>
  <div class="header-meta">
    <div><strong>${_h_host}</strong></div>
    <div>${_h_os}</div>
    <div>${DATE_VAL}</div>
    <div><span class="version-badge">v${SCRIPT_VERSION}</span></div>
  </div>
</header>

<div class="score-hero">
  <div class="score-ring">
    <svg viewBox="0 0 90 90">
      <circle class="track" cx="45" cy="45" r="36"/>
      <circle class="bar"   cx="45" cy="45" r="36"/>
    </svg>
    <div class="score-ring-label">
      ${SCORE}%<small>${SCORE_LABEL}</small>
    </div>
  </div>
  <div class="score-hero-text">
    <h2>Security Score: <span>${SCORE}%</span></h2>
    <p>Full audit, <strong>${TOTAL}</strong> checks run on ${_h_host}.
      The findings below are ordered by section; run 'aartool advise' for them in the order an attacker would reach them.</p>
  </div>
  <div class="score-stats">
    <div class="stat-pill"><span class="dot" style="background:var(--pass)"></span><span class="cnt">${PASS}</span> PASSED</div>
    <div class="stat-pill"><span class="dot" style="background:var(--warn)"></span><span class="cnt">${WARN}</span> WARNINGS</div>
    <div class="stat-pill"><span class="dot" style="background:var(--fail)"></span><span class="cnt">${FAIL}</span> FAILED</div>
  </div>
</div>

<div class="progress-wrap">
  <div class="progress-label">
    <span>Overall security posture</span>
    <span>${SCORE}% / 100%</span>
  </div>
  <div class="progress"><div class="progress-bar"></div></div>
</div>

<div class="section-title">Check Results</div>

<table class="results-table">
<thead>
  <tr>
    <th class="col-id">ID</th>
    <th class="col-status">Status</th>
    <th class="col-check">Check</th>
    <th class="col-detail">Detail &amp; Remediation</th>
  </tr>
</thead>
<tbody>
${HTML_ROWS}
</tbody>
</table>

<div class="ansible-section">
  <div class="section-title">Remediation Plan</div>
  <p style="font-size:.85rem;color:var(--muted);margin-bottom:1rem;">
    A targeted command for each failing or warning check.
    Preview any of them with <code style="color:var(--ca-teal)">aartool plan</code>,
    same arguments. It changes nothing.
  </p>
  <table class="plan-table">
    <thead>
      <tr>
        <th>Issue</th>
        <th>Ansible Role</th>
        <th>Tags</th>
        <th>Command</th>
      </tr>
    </thead>
    <tbody>
${ANSIBLE_PLAN_HTML}
    </tbody>
  </table>
  <div class="consolidated-cmd">
    <button class="copy-btn" onclick="navigator.clipboard.writeText(this.nextElementSibling.textContent.trim()).then(()=>{this.textContent='✅ Copied';setTimeout(()=>this.textContent='📋 Copy',1500)})">📋 Copy</button>
    <span class="cmd-label">Fix everything in one run</span>
    ${ANSIBLE_CONSOLIDATED_CMD}
  </div>
</div>

<footer>
  <div class="footer-logo">
    <a href="https://github.com/cyberaar/aartool" target="_blank">
      <img src="data:image/png;base64,${LOGO_WHITE_VAR}" alt="CyberAar logo">
    </a>
  </div>
  <div class="footer-text">
    Generated by <a href="https://github.com/cyberaar/aartool" target="_blank">aartool-baseline v${SCRIPT_VERSION}</a><br>
    <strong>${DATE_VAL}</strong> · ${_h_host} · ${_h_os}
  </div>
</footer>

</div>

<script>
// Animate score ring on load
(function() {
  const bar = document.querySelector('.score-ring .bar');
  if (!bar) return;
  const score = ${SCORE};
  const circ  = 2 * Math.PI * 36; // 226.2
  const offset = circ * (1 - score / 100);
  bar.style.transition = 'stroke-dashoffset 1s ease-out';
  requestAnimationFrame(() => {
    setTimeout(() => { bar.style.strokeDashoffset = offset; }, 80);
  });
  bar.style.strokeDashoffset = circ; // start from empty
})();
</script>
</body>
</html>
HTMLEOF
  chmod 600 "$HTML_OUT"
  printf "  🌐 HTML: %s\n\n" "$HTML_OUT"
}

# =============================================================================
#  MAIN EXECUTION BLOCK
#  Root check → gather host info → run all check functions → render outputs
# =============================================================================

# ─── ROOT CHECK ──────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "❌  Please run as root: sudo bash $0"
  exit 1
fi

HOSTNAME_VAL=$(hostname -f 2>/dev/null || hostname)
DATE_VAL=$(date '+%Y-%m-%d %H:%M:%S')
# The human-readable one above has no timezone, which is fine on a page someone
# reads and wrong for the SIEM ingestion docs/BASELINE.md advertises: two hosts
# in two zones produce timestamps that cannot be ordered. Emitted alongside
# rather than instead, because `date` is in the HTML header and is what the
# dashboard sorts on in every report already written.
DATE_ISO=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
OS_VAL=$(grep -oP '(?<=^PRETTY_NAME=").+(?=")' /etc/os-release 2>/dev/null || uname -o)

# ─── RUN CHECKS ──────────────────────────────────────────────────────────────
_checks_system
# Kernel checks used to run at bundle-load time, because this file was the only
# check family with no wrapping function. That put twelve unlabelled KRN rows
# above section 1, before any header had been printed. It runs here now, which
# is where build.sh already placed the file in the concatenation order.
_checks_kernel
_checks_auth
_checks_ssh
_checks_filesystem
_checks_network
_checks_logging
_checks_integrity
_checks_compliance

# ─── COMPUTE SCORE ───────────────────────────────────────────────────────────
# A warning counts as half a failure, not as a whole one.
#
# This used to be PASS / TOTAL, which penalised a WARN exactly as hard as a
# FAIL. A stock Ubuntu box with 8 real failures and 57 warnings scored 40% in
# red, and a reader has no way to tell that from a machine with 65 failures.
# Worse, many warnings are "cannot determine" rather than "is wrong": no /boot
# to read, no mokutil installed, a container with no systemd. Scoring those
# identically to PermitRootLogin=yes is what made the number untrustworthy, and
# a number nobody trusts gets ignored along with the findings under it.
#
# FAIL still costs full marks. The point is that the headline number should
# separate "wrong" from "unverified", which is the same distinction `advise`
# makes when it pulls decisions out into their own list.
TOTAL=$((PASS + WARN + FAIL))
SCORE=0
# Values passed with -v rather than interpolated into the awk program text.
# PASS and TOTAL are internal counters today, so this is hygiene rather than a
# fix, but a program built by string concatenation is one refactor away from
# taking a value it did not choose.
[[ "$TOTAL" -gt 0 ]] && SCORE=$(awk -v p="$PASS" -v w="$WARN" -v t="$TOTAL" \
  'BEGIN {printf "%.0f", ((p + (w * 0.5)) / t) * 100}')

# ─── RENDER OUTPUTS ──────────────────────────────────────────────────────────
_render_summary          # terminal score box + ansible remediation plan
_render_json             # JSON file (if $JSON_OUT set)
_render_html             # HTML file (if $HTML_OUT set)

# ─── HAND THE REPORTS BACK ───────────────────────────────────────────────────
# This script has to run as root: it reads sshd_config, /etc/shadow and the
# audit rules. Everything it writes was therefore owned by root, mode 600, and
# under sudo that left the person who ran it unable to open the report the tool
# had just printed a path to. `aartool report` and `aartool diff` both failed on
# it with a permission error.
#
# `aartool inspect` already handled this (cmd/inspect.sh). The standalone script
# did not, and the standalone script is the path the README advertises as the
# fastest way to try the tool, so this was the first-run experience.
#
# Only files this run wrote, and the directory only when this run created it: a
# --output-dir the user pointed at something pre-existing is not ours to give
# away.
if [[ -n "${SUDO_UID:-}" && -n "${SUDO_GID:-}" ]]; then
  for _f in "$JSON_OUT" "$HTML_OUT"; do
    [[ -n "$_f" && -e "$_f" ]] && chown "${SUDO_UID}:${SUDO_GID}" "$_f" 2>/dev/null
  done
  [[ "${OUTPUT_DIR_CREATED:-false}" == true && -d "$OUTPUT_DIR" ]] \
    && chown "${SUDO_UID}:${SUDO_GID}" "$OUTPUT_DIR" 2>/dev/null
  true
fi
