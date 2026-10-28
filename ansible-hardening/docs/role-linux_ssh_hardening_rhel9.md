# Role: linux_ssh_hardening_rhel9

## Purpose

Hardens the OpenSSH server configuration on RHEL 9 family systems:
- Disables root login and password authentication (key-based auth only)
- Enforces strong ciphers, MACs, and key exchange algorithms (aligns with `linux_crypto_policies_rhel9`)
- Disables weak features (X11 forwarding, empty passwords, unused subsystems)
- Sets session timeouts, max auth tries, and connection limits
- Deploys a legal banner (`/etc/issue.net`)
- Validates and restarts `sshd` only when configuration changes

## Supported Platforms

- RHEL 9.x (Red Hat Enterprise Linux)
- AlmaLinux 9.x
- Rocky Linux 9.x

## CIS Coverage

- 5.1.1 Ensure permissions on `/etc/ssh/sshd_config` are configured
- 5.1.2 Ensure permissions on SSH private host key files are configured
- 5.1.3 Ensure permissions on SSH public host key files are configured
- 5.1.4 Ensure SSH access is limited
- 5.1.5 Ensure SSH LogLevel is appropriate
- 5.1.6 Ensure SSH PAM is enabled
- 5.1.7 Ensure SSH root login is disabled
- 5.1.8 Ensure SSH HostbasedAuthentication is disabled
- 5.1.9 Ensure SSH PermitEmptyPasswords is disabled
- 5.1.10 Ensure SSH PermitUserEnvironment is disabled
- 5.1.11 Ensure SSH IgnoreRhosts is enabled
- 5.1.12 Ensure SSH X11 forwarding is disabled
- 5.1.13 Ensure only strong ciphers are used
- 5.1.14 Ensure only strong MAC algorithms are used
- 5.1.15 Ensure only strong key exchange algorithms are used
- 5.1.16 Ensure SSH AllowTcpForwarding is disabled
- 5.1.17 Ensure SSH warning banner is configured
- 5.1.18 Ensure SSH MaxAuthTries is set to 4 or less
- 5.1.19 Ensure SSH MaxStartups is configured
- 5.1.20 Ensure SSH MaxSessions is limited

## Variables

| Variable | Default | Description |
|---|---|---|
| `linux_ssh_hardening_enabled` | `true` | Apply SSH hardening |
| `linux_ssh_permit_root_login` | `no` | `PermitRootLogin` (`no` / `prohibit-password` / `yes`) |
| `linux_ssh_password_auth` | `no` | `PasswordAuthentication`: force key-based auth |
| `linux_ssh_permit_empty_passwords` | `no` | `PermitEmptyPasswords` |
| `linux_ssh_x11_forwarding` | `no` | `X11Forwarding` |
| `linux_ssh_ciphers` | `chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,...` | Allowed ciphers |
| `linux_ssh_macs` | `hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,...` | Allowed MACs |
| `linux_ssh_kexalgorithms` | `curve25519-sha256,curve448-sha512,...` | Allowed key exchange algorithms |
| `linux_ssh_banner` | `/etc/issue.net` | Legal banner file path |
| `linux_ssh_max_auth_tries` | `4` | `MaxAuthTries`: anti-brute-force |
| `linux_ssh_max_sessions` | `4` | `MaxSessions` per connection |
| `linux_ssh_max_startups` | `10:30:60` | `MaxStartups`: connection throttle |
| `linux_ssh_login_grace_time` | `60` | `LoginGraceTime` in seconds |
| `linux_ssh_client_alive_interval` | `300` | `ClientAliveInterval` in seconds (5 min) |
| `linux_ssh_client_alive_count_max` | `3` | `ClientAliveCountMax`: probes before drop |
| `linux_ssh_subsystem` | `internal-sftp` | Command run for the sftp subsystem (the role writes `Subsystem sftp <value>`) |
| `linux_ssh_hardening_disabled` | `false` | Set `true` to skip this role entirely |

## Usage Example

```yaml
# group_vars/rhel_servers.yml

linux_ssh_permit_root_login: "no"
linux_ssh_password_auth: "no"
linux_ssh_max_auth_tries: 3

# Tighter session timeout for high-security servers (15 min idle)
linux_ssh_client_alive_interval: 300
linux_ssh_client_alive_count_max: 3
```

## Important Notes

`ClientAliveCountMax` must not be set to `0`: this drops the session on the first missed probe and will terminate Ansible connections during long-running tasks (AIDE init, package installs). The default of `3` means 15 minutes of idle time before disconnect.

## Differences from Ubuntu Counterpart

| Aspect | RHEL9 | Ubuntu/Debian |
|---|---|---|
| Config file | `/etc/ssh/sshd_config` | `/etc/ssh/sshd_config` |
| Crypto alignment | Aligns with `crypto-policies` (`FUTURE`) | Manual cipher/MAC configuration |
| Service name | `sshd` | `ssh` |
| Variables | Identical structure | Identical structure |
