# Role: linux_ssh_hardening_ubuntu

## Purpose

Hardens the OpenSSH server configuration on Ubuntu/Debian systems:
- Disables root login and password authentication (key-based auth only)
- Enforces strong ciphers, MACs, and key exchange algorithms
- Disables weak and unnecessary SSH features (X11, TCP forwarding, empty passwords)
- Configures keepalive, session limits, and login grace time
- Sets a legal pre-login banner
- Validates the resulting config with `sshd -T` before applying

## Supported Platforms

- Ubuntu 20.04 LTS (Focal)
- Ubuntu 22.04 LTS (Jammy)
- Ubuntu 24.04 LTS (Noble)
- Debian 11 (Bullseye) / Debian 12 (Bookworm)

## CIS Coverage

- 5.1.1 Ensure permissions on `/etc/ssh/sshd_config` are configured
- 5.1.3 Ensure SSH access is limited
- 5.1.5 Ensure SSH `LoginGraceTime` is set
- 5.1.6 Ensure SSH `MaxAuthTries` is set
- 5.1.7 Ensure SSH banner is configured
- 5.1.8 Ensure SSH `PermitEmptyPasswords` is disabled
- 5.1.10 Ensure SSH `X11Forwarding` is disabled
- 5.1.11 Ensure SSH `AllowTcpForwarding` is disabled
- 5.1.13–5.1.15 Ensure strong ciphers, MACs, and KexAlgorithms

## Variables

| Variable | Default | Description |
|---|---|---|
| `linux_ssh_permit_root_login` | `no` | `PermitRootLogin` directive |
| `linux_ssh_password_auth` | `no` | `PasswordAuthentication`: force key-based auth |
| `linux_ssh_permit_empty_passwords` | `no` | Disallow empty password login |
| `linux_ssh_x11_forwarding` | `no` | Disable X11 forwarding |
| `linux_ssh_allow_tcp_forwarding` | `no` | Disable TCP port forwarding |
| `linux_ssh_gateway_ports` | `no` | Disable remote port bindings |
| `linux_ssh_permit_tunnel` | `no` | Disable tun/tap tunneling |
| `linux_ssh_ciphers` | `chacha20-poly1305@openssh.com,...` | Allowed encryption ciphers |
| `linux_ssh_macs` | `hmac-sha2-512-etm@openssh.com,...` | Allowed MAC algorithms |
| `linux_ssh_kexalgorithms` | `curve25519-sha256,...` | Allowed key exchange algorithms |
| `linux_ssh_banner` | `/etc/issue.net` | Path to pre-login banner file |
| `linux_ssh_max_auth_tries` | `4` | Max authentication attempts per connection |
| `linux_ssh_max_sessions` | `4` | Max concurrent sessions per connection |
| `linux_ssh_max_startups` | `10:30:60` | Throttle unauthenticated connections |
| `linux_ssh_login_grace_time` | `30` | Seconds to complete authentication |
| `linux_ssh_client_alive_interval` | `300` | Seconds between keepalive probes |
| `linux_ssh_client_alive_count_max` | `3` | Missed probes before disconnect |
| `linux_ssh_subsystem` | `internal-sftp` | Command run for the sftp subsystem (the role writes `Subsystem sftp <value>`) |
| `linux_ssh_sshd_binary` | `/usr/sbin/sshd` | Path to sshd for config validation |
| `linux_ssh_hardening_disabled` | `false` | Set `true` to skip this role entirely |

## Usage Example

```yaml
# group_vars/ubuntu_servers.yml
linux_ssh_permit_root_login: "no"
linux_ssh_password_auth: "no"
linux_ssh_max_auth_tries: 3
linux_ssh_login_grace_time: "20"
linux_ssh_client_alive_interval: 300
linux_ssh_client_alive_count_max: 3

# Allow TCP forwarding on a bastion host
linux_ssh_allow_tcp_forwarding: "yes"
```

## Differences from RHEL9 Counterpart

The variable set is identical between the Ubuntu and RHEL9 SSH hardening roles. The only difference is the `sshd_binary` default path:

| | Ubuntu/Debian | RHEL9 |
|---|---|---|
| sshd binary | `/usr/sbin/sshd` | `/usr/sbin/sshd` (same) |
| Config validation | `sshd -T -f %s` | `sshd -T -f %s` (same) |
| sshd service name | `ssh` | `sshd` |

Note: On Ubuntu the systemd service is named `ssh`, not `sshd`. The handler in this role uses the correct name.
