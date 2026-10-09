# linux_auditing_rhel9

## Purpose
Installs, configures, and hardens `auditd` for comprehensive logging of security events:  
- Service enabled/active  
- Sensible log rotation & space handling  
- Watches on identity files, privileged execs, mounts, sudoers, etc.  
- Makes rules immutable to prevent tampering

## Targeted OS
RHEL 9 / AlmaLinux 9 / Rocky Linux 9

## CIS References (v2.0.0)
- 6.3.1.x Install & enable auditd  
- 6.3.2.x auditd.conf settings  
- 6.3.3.x Audit rules for key events (identity, privileged, mounts, etc.)

## Idempotence
- Templates check content → only change if needed  
- Service restart only on actual change  
- GRUB only modified if boot auditing enabled; `audit=1` and
  `audit_backlog_limit` are appended to `/etc/default/grub` only when absent
  (existing parameters are kept), and added to the installed kernels with
  `grubby` only when one of them lacks them

## Variables
- Tune `linux_auditd_*` for log sizes/actions  
- `linux_auditd_backlog_limit: 8192`: kernel audit backlog before auditd starts (`0` leaves it unset)  
- Add more rules by extending the template

## Notes
- Logs to `/var/log/audit/audit.log`: consider forwarding to SIEM  
- Immutable rules (`-e 2`) require reboot to change  
- Test: `ausearch -k identity` or `aureport -a` after apply

## Log Forwarding for Critical Infrastructure

### Two-Layer Approach (Recommended for DAF-like envs)
1. **auditd → local rsyslog** via audisp-syslog plugin (simple, native)
   - Var: `linux_auditd_forward_to_syslog: true`

2. **rsyslog → central hardened log server**
   - Protocol: TCP (default), RELP (guaranteed delivery – best for critical)
   - Encryption: TLS (mandatory over untrusted networks)
   - Queueing: disk spool if remote down
   - Vars: `linux_rsyslog_remote_host`, `linux_rsyslog_remote_use_tls`, etc.

### Security Notes
- Use **RELP + TLS** if possible (install `rsyslog-relp` package if needed)
- Central server must be hardened (firewall, SELinux, immutable storage)
- Consider SIEM integration (Wazuh, ELK, Splunk) for alerting & correlation
- Test forwarding: `logger "Test from {{ ansible_hostname }}"` + check central server
- Audit log volume → plan storage/retention on central side (30–365 days typical)

### Future Extensions (if needed)
- Dedicated audit queue
- Failover remote servers
- Certificate-based mutual auth
