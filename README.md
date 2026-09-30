# aartool

![aartool paths on a sample audit: three complete attack chains, the count of open findings at each stage, and the one link to cut in each, followed by aartool explain on that link](docs/media/aartool-paths.gif)

**Audit a Linux host, get an ordered plan, understand any finding, apply the
fix, and prove afterwards that only what you intended changed.**

Nothing is modified unless you type `apply`.

```bash
aartool demo                            # thirty-second tour. No root, changes nothing.
sudo aartool inspect                    # 109 checks. Changes nothing.
aartool advise                          # what to fix first, and what each fix costs
aartool explain KRN-01                  # why it matters, and what closing it breaks
aartool plan  --target web-01 --user ubuntu --only ssh   # preview the change
aartool apply --target web-01 --user ubuntu --only ssh   # make it
aartool diff before.json after.json     # prove only what you intended moved
```

Built on 52 CIS-aligned Ansible roles for the RHEL 9 family and Ubuntu/Debian,
a dependency-free audit script that runs on an air-gapped box, and a dashboard
that opens offline. `aartool` is the front door to all of it.

**Full manual: [docs/AARTOOL.md](docs/AARTOOL.md)**

### Tested on a real estate, not only in CI

Every release is exercised against live servers before it ships, and the
findings from those runs are what most of the fixes in the changelog come from.

- **15 production nodes audited** through a bastion, 15 of 15 succeeded. That
  run found a defect on the estate itself: a Jinja whitespace rule had collapsed
  the entire monitoring block of `/etc/hosts` onto one physical line on **every
  node**, for months, with nothing reporting it.
- **Hardening applied end to end** to a live documentation server running
  BookStack in containers: `doctor` to `plan` to `apply` to re-`inspect` to
  `diff`. Score 72 to 75, three findings cleared, **nothing regressed and the
  service stayed up throughout**.
- That single run found four defects in aartool that no test had caught,
  including a check that could never pass on any host and a check whose own
  remediation wrote a value the check rejected. All four are fixed, and each has
  a guard proven to fail on the bug it prevents.

CI covers Rocky 9 and Ubuntu 22.04 across 31 Molecule scenarios. Debian 12 is
supported by the role logic but has no Molecule image yet: treat it as untested.

---

## How this differs from the tools you already have

These are good tools and `aartool` does not replace them. The gap it is built
for is the middle of the workflow, between knowing and fixing.

| | what it gives you | what is still on you |
|---|---|---|
| [Lynis](https://cisofy.com/lynis/) | a thorough audit and a hardening index | deciding what to do first, and doing it |
| [OpenSCAP](https://www.open-scap.org/) / CIS-CAT | scanning against a formal profile, and an auditor-shaped report | the report is evidence, not a plan, and the profile is all-or-nothing |
| [ansible-lockdown](https://github.com/ansible-lockdown), [dev-sec.io](https://dev-sec.io/) | well-maintained remediation roles | knowing which of them this host needs, and what each one breaks |

`aartool` is the loop across that gap: audit, an order to work in, the cost of
each fix stated before you make it, the change itself, then a diff that proves
only what you intended moved.

The part that is genuinely different is `explain`. Every finding states what
closing it breaks, and "not on this machine" is a supported answer. A hardening
tool that argues one side gets switched off entirely, and its good advice goes
with it.

If Lynis already tells you what is wrong and you already know what to do about
it, you do not need this.

---

## Install

From the package repository, which is what most people want:

```bash
# Debian, Ubuntu
sudo curl -fsSL https://pkgs.cyberaar.io/aartool.sources \
  -o /etc/apt/sources.list.d/aartool.sources
sudo apt update && sudo apt install aartool

# RHEL, Rocky, AlmaLinux, Fedora
sudo curl -fsSL https://pkgs.cyberaar.io/aartool.repo -o /etc/yum.repos.d/aartool.repo
sudo dnf install aartool
```

Two commands, not one. `apt install aartool` on its own reports `E: Unable to
locate package aartool`, because apt will not install from a repository it has
not been told to trust, and it cannot be told from inside the install command.
That is apt's trust model, not something this packaging can shorten.

The apt file is [deb822](https://manpages.debian.org/apt/sources.list.5.en.html)
with the signing key **inline**, which is what makes it one file instead of
three. The older form needs the key in `/etc/apt/keyrings` and then needs it
made world readable, because apt verifies signatures as the unprivileged `_apt`
user and `curl | sudo tee` writes the file with your umask: on a machine set to
`umask 027` that is mode 0640, and apt fails with `Unknown error executing
apt-key`, naming neither the permission nor the file. Inline, there is no
second file to get wrong.

Both packages are signed, and so is the repository metadata. `apt upgrade` and
`dnf upgrade` pick up new releases from then on.

A `.deb` and an `.rpm` are also attached to every
[release](https://github.com/cyberaar/aartool/releases) if you would rather
install a file directly, on a machine that cannot reach the repository.

Ansible is a recommended dependency, not a required one: the audit half of the
tool never calls it. Your inventory belongs at `/etc/aartool/inventory`, where
an upgrade will not touch it. See [docs/PACKAGING.md](docs/PACKAGING.md) for the
layout and the reasoning.

To remove it:

```bash
sudo apt remove aartool       # or: sudo dnf remove aartool
```

From a clone, which is what you want if you intend to change anything:

```bash
git clone https://github.com/cyberaar/aartool
cd aartool
sudo scripts/aartool install              # symlink into /usr/local/bin
aartool doctor                            # is everything it needs actually here?
sudo aartool uninstall                    # removes the symlink, keeps the clone
```

Without root, or without installing at all:

```bash
scripts/aartool install --prefix ~/.local   # needs ~/.local/bin on PATH
./scripts/aartool advise                    # or just run it from the clone
```

Or take the single file, on a machine you cannot clone onto. The audit script
has no dependencies beyond the coreutils already there, which is what makes it
work on an air-gapped box:

```bash
curl -fsSLO https://github.com/cyberaar/aartool/releases/latest/download/aartool-baseline.sh
curl -fsSLO https://github.com/cyberaar/aartool/releases/latest/download/SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
chmod +x aartool-baseline.sh && sudo ./aartool-baseline.sh
```

`aartool` and the Ansible collection tarball are attached to every release the
same way, so neither Ansible Galaxy nor a container registry is on the critical
path. Release assets do not carry the executable bit, hence the `chmod`. Verify
against `SHA256SUMS`: for a tool that rewrites `sshd_config` and PAM, checking
what you downloaded is not ceremony.

Auditing the machine you are on still needs root either way: it reads
`sshd_config`, `/etc/shadow`, the audit rules and sysctls. Auditing a *remote*
host needs no privilege locally at all.

`install` creates a **symlink, not a copy**, and that matters: `aartool` finds
the playbooks, the audit script and the dashboard by walking up from its own
file. Copied into `/usr/local/bin` there is nothing above it but `/usr` and `/`.
Keep the clone where it is, or `export AARTOOL_HOME=/path/to/aartool`. If you
copy it and forget, the error says exactly that.

---

## The loop

**1. Audit.** Reports land in `./reports` as HTML and JSON. Under `sudo` they
are handed back to you, so the next command does not need root as well.

```bash
sudo aartool inspect                                  # this machine
aartool inspect --host 10.0.1.10 --user admin         # one remote host
aartool inspect --inventory ansible-hardening/inventory/hosts   # an estate
```

**2. Get a plan, not a list.** Forty findings in report order have no ordering:
the cheapest item and the one an attacker is walking through right now look
identical. `advise` sorts by **reachability**, and pulls anything with a real
operational cost into a separate list rather than hiding it.

```bash
aartool advise --target web-01 --user ubuntu
```

```
── Wave 1 · Reachable from the network: no account needed
   FAIL  SSH-01    PermitRootLogin enabled  explain
   FAIL  NET-01    No firewall active  [needs a decision]  explain
   WARN  SYS-11    Running the newest installed kernel  explain

     preview  aartool plan  --target web-01 --user ubuntu --only firewall,ssh,updates
     apply    aartool apply --target web-01 --user ubuntu --only firewall,ssh,updates

── Decide before you apply
   NET-01    No firewall active
             aartool explain NET-01
```

| wave | the question it answers |
|---|---|
| 1 | What can be reached from the network, with no account? |
| 2 | What turns an account into root? |
| 3 | What would mean you never found out? |
| 4 | Hygiene and audit evidence. |

**3. Understand anything in it.**

```bash
aartool explain KRN-01
```

Six sections, same order every time: **what** the check reads, **why** it
matters as a concrete path from finding to compromised machine, the **cost**
including what it breaks, how to fix it **by hand**, how to fix it **with
aartool**, and **more** for the part that is not obvious.

The cost section is the point. `KRN-01` says plainly that closing unprivileged
user namespaces breaks rootless Docker, Chrome's sandbox and most CI runners,
and that "not on this machine" is a legitimate answer. A hardening tool that
argues only one side gets switched off entirely, and then its safe advice goes
with it.

**4. Preview, then apply to one host** with a second SSH session open.

```bash
aartool plan  --target web-01 --user ubuntu --only ssh
aartool apply --target web-01 --user ubuntu --only ssh
```

To harden the machine you are on, which is the machine step 1 just audited, use
`localhost`. It needs no inventory and nothing goes over SSH:

```bash
sudo aartool plan  --target localhost --only ssh   # changes nothing
sudo aartool apply --target localhost --only ssh
```

`apply` asks you to type the target name back. `--target` is required and is
checked against the inventory first: the dangerous mistake is not "did I mean
to run this", it is "did I mean this host or that group".

**5. Prove it, and keep it that way.**

```bash
aartool diff before.json after.json
aartool diff last-week.json today.json --quiet \
  || mail -s "drift on $(hostname)" soc@example.com
```

Exit `0` nothing regressed, `1` something regressed, `2` not comparable. The
exit code is the feature: a weekly audit that mails you 109 results teaches you
to filter the mail.

---

## Commands

| command | what it does |
|---|---|
| `inspect` | Audit a machine. Changes nothing. |
| `advise` | Turn an audit into an ordered plan. |
| `explain` | What a finding means, what it costs, what to do. |
| `plan` | Show what hardening would change. Changes nothing. |
| `apply` | Apply hardening to a target. |
| `surface` | Kernel attack surface: what the next local privilege escalation would still reach, and what closing each doorway costs. |
| `doctor` | Check everything `plan` and `apply` depend on. Non-zero if anything is missing, so it works as a CI gate. |
| `report` | Bake reports into one self-contained HTML file, or serve the dashboard. |
| `diff` | What changed between two audits. |
| `paths` | How an attacker would chain your findings into a complete attack, and a link to cut. Exits 1 when a chain is complete, so it gates CI. |
| `badge` | A self-contained SVG hardening badge for your README, from an audit. |
| `demo` | The whole loop on a bundled sample audit. No root, no SSH, changes nothing. |
| `export` | An audit as SARIF for CI security tabs, or Prometheus metrics for node_exporter. |
| `install` | Put `aartool` on your PATH. |
| `uninstall` | Remove it again. On a packaged install it points you at `apt remove` instead. |

Add `-v` to any command to see what it is shelling out to. That is the flag
that helps when the failure is in `ssh` or `ansible` rather than in `aartool`.

Every flag, the exit-code table, a symptom-to-fix table and how to extend it:
**[docs/AARTOOL.md](docs/AARTOOL.md)**.

---

## Remote hosts, and the bastion in front of them

```bash
aartool inspect --host 10.0.1.31 --user admin \
  --ssh-key ~/.ssh/estate --jump admin@bastion.example.com
```

Use `--jump`, not `--ssh-opt '-J ...'`. They are not equivalent: `ssh` does not
pass the outer connection's options to the jump hop, so `-J` alongside
`--ssh-key` authenticates the target with your key and the bastion with
whatever the defaults happen to be. On a machine with no agent that fails with
`Host key verification failed`, a message about the bastion that never names the
bastion. `--jump` builds the `ProxyCommand` itself and carries the key onto hop
one.

`--ssh-key` also implies `IdentitiesOnly=yes`. An agent with several keys offers
each one, every offer counts against the target's `MaxAuthTries`, and a fleet
scan from such a workstation gets that workstation banned by `fail2ban` across
the estate.

The transport is `ssh` with the script on stdin, not `scp`. OpenSSH 9 `scp`
speaks SFTP, and a hardened host frequently has no `sftp` subsystem, so `scp`
fails on exactly the machines most likely to be running a security tool.

`scripts/tests/proof-remote.sh` proves all three against real hosts: it stands
up a bastion and a private target on a Docker network, removes the `sftp`
subsystem so `scp` genuinely cannot work, and runs the whole loop through them.

---

## `aartool report`: one file you can send someone

The toolkit ships a dashboard: one HTML file, no server, no internet. `report`
bakes your results straight into a copy of it, so what you hand over opens
offline on a machine that has never heard of this toolkit.

```bash
aartool report ./reports/*.json --out fleet.html    # self-contained, sendable
aartool report ./reports/*.json --open              # just look at it
aartool report --serve 8080                         # headless server
```

It is built for the person reading the audit rather than the person who ran it:
hosts sorted worst first with a visible way in, an estate heatmap that separates
a policy problem from one bad machine, and findings ranked by how many machines
each one affects. Remediation is shown as aartool commands throughout, and
print-to-PDF produces a document you can attach to an engagement report.

**Sharing it outside the estate it came from:**

```bash
aartool report ./reports/*.json --anonymise --out share.html
```

An audit report is a list of a machine's weaknesses with its name attached.
`--anonymise` turns hostnames into `server-01`, `server-02` and addresses into
`ip-01`, consistently across every file so a before-and-after pair still lines
up. The mapping is printed once and stored nowhere. `--redact` handles the
things only you know are identifying, and refuses any pattern that would also
rewrite the report's own fields, because that produces a valid file which opens
to an empty page.

---

## `aartool surface`

Red Hat and Debian ship the patch. Nothing helps you in the window *before* the
patch exists, or on the machine you cannot reboot until the change window in
three weeks.

```bash
aartool surface              # what would the next kernel LPE still reach here?
aartool surface --strict     # include mitigations that break real workloads
sudo aartool surface --apply # write the drop-in and load it
```

These settings close **classes** of local privilege escalation rather than
individual CVEs: unprivileged user namespaces, unprivileged eBPF, `io_uring`,
`userfaultfd`, `kexec`, module loading, TTY line-discipline autoload. Turning
user namespaces off fixes none of the bugs behind CVE-2022-0185 or
CVE-2023-0386. It removes the doorway they all use.

Two tiers, and only `safe` runs by default:

| tier | meaning |
|---|---|
| `safe` | no mainstream workload is known to depend on it |
| `strict` | will break something real for somebody, and the cost is printed |

Nothing is compiled and nothing is rebooted. Everything applied lands in one
drop-in file you can delete to revert.

---

## What's underneath

`aartool` does not replace any of these. Each stays independently usable, and
each has its own document.

| component | what it is | |
|---|---|---|
| **Ansible collection** | `cyberaar.hardening`: 52 CIS-aligned roles, RHEL 9 family and Ubuntu/Debian, in parallel pairs with automatic OS detection | [docs/ANSIBLE.md](docs/ANSIBLE.md) |
| **`aartool-baseline.sh`** | The audit itself: one bash file, no dependencies, `curl`-able onto an air-gapped box | [docs/BASELINE.md](docs/BASELINE.md) |
| **Dashboard** | Single HTML file, no server, no external requests, works on an isolated network | [docs/DASHBOARD.md](docs/DASHBOARD.md) |
| **Container image** | Ansible and the collections already present, for running without installing anything | [docs/CONTAINER.md](docs/CONTAINER.md) |
| **Packages** | `.deb` and `.rpm`, and the signed repository they are served from | [docs/PACKAGING.md](docs/PACKAGING.md) |
| **Media** | Regenerating the terminal graphic used in release posts | [docs/MEDIA.md](docs/MEDIA.md) |

### Layout

```
aartool/
├── docs/                             # AARTOOL, ANSIBLE, BASELINE, DASHBOARD, CONTAINER
├── scripts/
│   ├── aartool                       # generated bundle, do not edit
│   ├── aartool-src/                  # edit here: main.sh, run.sh, lib/, cmd/
│   ├── aartool-baseline.sh          # generated bundle, do not edit
│   ├── src/                          # edit here: checks/, renderers/, lib/
│   ├── build-aartool.sh  build.sh    # rebuild the two bundles
│   └── tests/                        # guards, each written after the bug it prevents
├── ansible-hardening/
│   ├── playbooks/                    # 3-step pipeline: audit, harden, audit
│   ├── roles/                        # 52 roles
│   ├── molecule/                     # 31 scenarios, all wired into CI
│   └── inventory/                    # hosts.example is tracked; hosts is not
├── dashboard/index.html
└── execution-environment/
```

**Both `scripts/aartool` and `scripts/aartool-baseline.sh` are generated.**
Edit the sources and run the matching build script; CI fails if the committed
bundle has drifted from them.

```bash
$EDITOR scripts/aartool-src/cmd/advise.sh
bash scripts/build-aartool.sh
bash scripts/tests/test_aartool.sh
```

---

## Goal

A free, community-maintained security toolkit giving practical,
context-adapted tooling to government and public administration, energy and
utilities, finance, telecoms and critical systems, healthcare and transport.

Community-maintained practices, translations and worked examples live in
**[cyberaar/Aar-Act](https://github.com/cyberaar/Aar-Act)**.

## Contributing

Fork, branch, and describe the change, the systems you tested on, and the CIS
controls affected. Roles are testable with Molecule; the guard tests are in
`scripts/tests/`. Full guide: [CONTRIBUTING.md](CONTRIBUTING.md).

If you add a guard, **prove it fails**: break the thing on purpose, watch the
test go red, then put it back. Every test in `scripts/tests/` was written after
the failure it describes was found in shipped code.

## License

**GNU General Public License v3.0**. Copyright (C) 2025-2026 CyberAar Team.
This program is free software: you can redistribute it and modify it under the
terms of the GPL as published by the Free Software Foundation, either version 3
or (at your option) any later version. See [LICENSE](LICENSE) for the full text.

© 2025–2026 CyberAar Team

## Contributors

- [@Bantou96](https://github.com/Bantou96), Founder
- [@moustaphisene](https://github.com/moustaphisene), CIS gap coverage: sudo, cron, wireless hardening roles

## How this is built and tested

Written with AI assistance ([Claude](https://claude.ai), Anthropic), and tested
harder because of it:

- **1378 assertions across the suite**, plus Molecule scenarios on Rocky 9 and
  Ubuntu 22.04.
- **Every guard here was proven to fail on injected drift before it was
  trusted.** A check that cannot fail is worse than no check.
- **Run against a live 15-node estate, not only in CI.** One live hardening run
  found 4 defects the suite had missed at the time, which is why it is still run
  on real machines rather than only in CI.
- **The check and role counts in this README are derived from the tool itself**,
  so the documentation cannot claim a number the code does not produce.

If a claim in this README is not checked by a test, treat it as a bug and open
an issue.

