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
