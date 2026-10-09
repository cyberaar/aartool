# linux_auditing_ubuntu

## Purpose
Installs and configures auditd with CIS-aligned audit rules and configures rsyslog for centralized log forwarding to enforce comprehensive system auditing.

## Targeted OS
Ubuntu 20.04 / 22.04 / 24.04, Debian 11 / 12

## CIS Alignment
CIS Section 4.1, Configure System Accounting (auditd), CIS Section 4.2, Configure Logging

## Key Variables
```yaml
linux_auditing_ubuntu_disabled: false   # set to true to skip this role
linux_auditd_enable_boot_auditing: true # audit=1 on the kernel cmdline
linux_auditd_backlog_limit: 8192         # audit_backlog_limit on the cmdline; 0 leaves it unset
```

See `defaults/main.yml` for all tunable parameters.
