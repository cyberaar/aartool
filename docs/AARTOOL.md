# aartool

One front door for the CyberAar hardening toolkit: audit a Linux host, get an
ordered plan, understand any finding in it, preview the fix, apply it, and prove
afterwards that only what you intended changed.

It changes nothing unless you type `apply`.

- [Why it exists](#why-it-exists)
- [Install](#install)
- [The five-minute version](#the-five-minute-version)
- [The workflow](#the-workflow)
- [Command reference](#command-reference)
- [Remote hosts and bastions](#remote-hosts-and-bastions)
- [Exit codes](#exit-codes)
- [When something goes wrong](#when-something-goes-wrong)
- [Environment variables](#environment-variables)
- [Using it in CI](#using-it-in-ci)
- [What it checks](#what-it-checks)
- [Extending it](#extending-it)
- [What it deliberately does not do](#what-it-deliberately-does-not-do)

---

## Where it has been run

CI is not evidence that a tool works on a real machine, only that it works on
the machine CI builds. Every release is exercised against live servers first.

| | |
|---|---|
| Estate audit | 15 production nodes through a bastion, 15 of 15 succeeded |
| Hardening applied | live documentation server running BookStack in containers, `doctor` to `plan` to `apply` to re-`inspect` to `diff`, score 72 to 75, nothing regressed, service up throughout |
| Remote transport | proved against a host with the `sftp` subsystem removed, where `scp` genuinely cannot work (`scripts/tests/proof-remote.sh`) |
| CI | 31 Molecule scenarios on Rocky 9 and Ubuntu 22.04, plus 746 assertions across seven guard suites |

Those runs are where most of the fixes come from. The estate audit found a
defect on the estate itself, a Jinja whitespace rule that had collapsed the
monitoring block of `/etc/hosts` onto one line on every node for months. The
hardening run found four defects in aartool, including a check that could never
pass on any host and a check whose own remediation wrote a value the check
rejected.

Debian 12 is supported by the role logic but has no Molecule image yet. Treat it
as untested rather than as a claim.

---

## Why it exists

The toolkit grew two entry points with two conventions for one workflow.
`aartool-baseline.sh` took `--host` and `--user`. `run-hardening.sh` took `-t`
and `-u`, and used `-T` for tags: one shift key away from `-t` for the target,
on a tool that rewrites `sshd_config`, PAM and firewall rules.

`aartool` wraps both. Neither is replaced and neither changed. `aartool-baseline.sh`
keeps the single-file portability that lets you `curl` it onto an air-gapped box.

Two things it does differently from what it wraps, both on purpose:

**The dry run is a command, not a flag.** `run-hardening.sh` applies by default
and takes `-c` to preview, so one missing character separates a report from a
rewritten SSH config. Here `plan` shows and `apply` does.

**`--target` is required.** `run-hardening.sh` defaults to the group
`linux_servers`, which is every machine in the inventory, so a bare invocation
hardens the whole estate. `aartool` refuses to guess, checks the target exists
in the inventory before calling Ansible, and `apply` asks you to type the target
name back rather than press `y`. The dangerous mistake here is not "did I mean
to run this", it is "did I mean this group or that one host".

---

## Install

```bash
git clone https://github.com/cyberaar/aartool
cd aartool
sudo scripts/aartool install                    # symlink into /usr/local/bin
# or, without root:
scripts/aartool install --prefix ~/.local       # ~/.local/bin must be on PATH
aartool doctor                                  # is everything it needs here?
```

`install` creates a **symlink, not a copy**, and that is not a detail. aartool
locates the playbooks, the baseline script and the dashboard by walking up from
its own file until it finds `ansible-hardening/`. Copied into `/usr/local/bin`
there is nothing above it but `/usr` and `/`, so a copy finds none of them.

Keep the clone where it is, or point aartool at it:

```bash
export AARTOOL_HOME=/opt/aartool
```

If you do copy it and forget, the error says exactly this rather than failing
somewhere further in.

### Without installing anything

Everything works from the clone:

```bash
./scripts/aartool inspect
```

### Without cloning anything

Every release attaches `aartool`, `aartool-baseline.sh`, the collection
tarball and a `SHA256SUMS`. Neither Ansible Galaxy nor a container registry is
on the critical path.

```bash
curl -fsSLO https://github.com/cyberaar/aartool/releases/latest/download/aartool-baseline.sh
curl -fsSLO https://github.com/cyberaar/aartool/releases/latest/download/SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
chmod +x aartool-baseline.sh && sudo ./aartool-baseline.sh
```

Assets do not carry the executable bit, hence the `chmod`. The single-file audit
script is the one to take to an air-gapped machine; `aartool` needs the rest of
the toolkit beside it, so clone or use the container for that.

### In a container

The repository ships an execution environment with Ansible and the collections
already present. See [CONTAINER.md](CONTAINER.md). Set `AARTOOL_HOME` to
wherever the toolkit is mounted.

---

## The five-minute version

On a machine you are sitting at:

```bash
sudo aartool inspect     # 109 checks. Changes nothing.
aartool advise           # the ordered plan, from the report inspect just wrote
aartool explain KRN-01   # anything in it you do not recognise
```

`inspect` writes an HTML report and a JSON report into `./reports`, unless `-o`
says otherwise. The HTML opens offline with no external requests, which is the
point on an isolated network. The JSON is what `advise`, `diff` and `report`
read.

Under `sudo` the reports are handed back to the user who invoked it, so the
second command does not need root as well. Pass `--no-save` if you want the
terminal output and no files.

---

## The workflow

### 1. Audit

```bash
sudo aartool inspect                                  # this machine
aartool inspect --host 10.0.1.10 --user admin         # one remote host
aartool inspect --inventory ansible-hardening/inventory/hosts   # an estate
```

### 2. Get a plan, not a list

```bash
aartool advise --target web-01 --user ubuntu
```

With no argument it reads the newest report in `.`, `./reports` or
`/var/log/cyberaar`.

Forty findings in report order is not a plan. It has no ordering, so the
cheapest item and the one an attacker is using right now look the same, and it
does not separate changes you can apply without a conversation from changes that
will break a workload.

`advise` orders by **reachability**, not by CVSS-style severity, because that is
what determines what an attacker gets to first:

| wave | question it answers |
|---|---|
| 1 | What can be reached from the network, with no account? |
| 2 | What turns an account into root? |
| 3 | What would mean you never found out? |
| 4 | Hygiene and audit evidence. |

Inside a wave: `FAIL` before `WARN`. Then anything whose fix has a real
operational cost is pulled out into a separate **Decide before you apply**
list, with the reason, because the fastest way to make someone stop using a
hardening tool is to break their containers on the first run.

```
── Wave 1 · Reachable from the network: no account needed
   FAIL  SSH-01    PermitRootLogin enabled  explain
   FAIL  NET-01    No host firewall active  [needs a decision]  explain
   WARN  SYS-11    Running the newest installed kernel  explain

     preview  aartool plan  --target web-01 --user ubuntu --only firewall,ssh,updates
     apply    aartool apply --target web-01 --user ubuntu --only firewall,ssh,updates
```

Every command it prints is generated from the same remediation map the reports
use, and a test asserts that every tag it can print is carried by a role in the
playbook. A plan that tells you to run an invalid `--only` produces a command
that exits zero, matches nothing and changes nothing, while you believe the
finding is fixed.

`--safe-only` takes the costly items out of the waves without hiding them: they
stay on the page under **Decide before you apply**. Nothing disappears.

### 3. Understand anything in it

```bash
aartool explain KRN-01
aartool explain --list              # all 109 check IDs
aartool explain --written           # the ones with a long-form entry
```

Each written entry answers six things in a fixed order, so it stays skimmable:

- **WHAT** the check reads
- **WHY** it matters, as the concrete path from the finding to a compromised machine
- **COST**, honestly, including what it breaks
- **BY HAND**, the commands, for when you are not using Ansible
- **WITH AARTOOL**, the tag and the variable
- **MORE**, the thing that is not obvious

`explain` always answers. Where there is no written entry it assembles one from
the remediation map, which covers 99 of the 109 IDs, and where an ID is
deliberately unmapped it says why there is no configuration fix. A help command
that refuses on a third of its inputs teaches people not to type it.

### 4. Preview

```bash
aartool plan --target web-01 --user ubuntu --only ssh
```

A dry run with `--diff`. Read it. This is the step people skip.

### 5. Apply, to one host, with a second session open

```bash
aartool apply --target web-01 --user ubuntu --only ssh
```

`apply` asks you to type the target name back. Keep a second SSH session open
until you have proved you can still log in with a third.

### 6. Prove what changed

```bash
sudo aartool inspect
aartool diff ./reports/<before>.json ./reports/<after>.json
```

### 7. Keep it that way

```bash
aartool diff last-week.json today.json --quiet \
  || mail -s "drift on $(hostname)" soc@example.com
```

The exit code is the feature. A weekly audit that mails you 109 results teaches
you to filter the mail. One that stays silent unless something **regressed** is
a thing you actually read.

---

## Command reference

Add `-v` (or `--verbose`) to any command to see what it is shelling out to.
That is the flag that helps when the failure is in `ansible` or `ssh` rather
than in aartool.

### `inspect`

Results stream as they run, one aligned row per check, grouped into the eight
families:

```
── 3. SSH HARDENING ────────────────────────────────────────────────
  STATUS ID        CHECK                                      DETAIL
  FAIL   SSH-01    Root login permitted                       PermitRootLogin yes
  PASS   SSH-02    Password authentication disabled           PasswordAuthentication no
```

The **check ID is in the second column** because `aartool explain SSH-01` needs
it, and it used to appear only in the JSON report.

The score is the **last** thing printed. It used to sit in the middle, with a
117-line remediation block after it: `aartool advise` does that job properly,
ordered by what an attacker reaches first and with the cost of each fix, so
inspect points at it rather than duplicating it worse.

`--hints` prints a one-line fix under each finding. It is off by default because
it roughly doubles the length of a 109-check run, and `explain <ID>` gives the
same thing in full plus what closing the finding breaks.

Audit a machine. Changes nothing.

| option | meaning |
|---|---|
| `--host HOST` | Audit one remote host over SSH |
| `--host-file FILE` | Audit every host listed in FILE, one per line |
| `--inventory FILE` | Audit every host in an Ansible inventory |
| `--user USER` | SSH user for a remote audit |
| `--ssh-key FILE` | SSH private key for a remote audit |
| `--jump USER@HOST[:PORT]` | Reach the target through a bastion. See [bastions](#remote-hosts-and-bastions) |
| `--ssh-opt OPT` | Extra `ssh` option, repeatable |
| `-o, --out DIR` | Write HTML and JSON reports to DIR. Default `./reports` |
| `--no-save` | Print to the terminal and write nothing |

With no `--host`, `--host-file` or `--inventory` it audits the machine it is
running on, which needs root.

### `advise`

Turn an audit into an ordered plan.

| option | meaning |
|---|---|
| `REPORT.json` | The report to read. Omit it and the newest `cyberaar-*.json` in `.`, `./reports` or `/var/log/cyberaar` is used |
| `--wave N` | Show only wave 1, 2, 3 or 4 |
| `--safe-only` | Keep costly findings out of the waves; still listed to decide on |
| `--target HOST` | Write the printed commands against this host |
| `--user USER` | Write the printed commands with this SSH user |

### `explain`

| form | meaning |
|---|---|
| `explain ID` | Explain one check. Case insensitive |
| `explain --list` | Every check ID and its title |
| `explain --written` | The IDs with a long-form entry |

`why` is an alias for `explain`.

### `plan` / `apply`

| option | meaning |
|---|---|
| `-t, --target HOST\|GROUP` | Required. Must exist in the inventory, or be `localhost` |
| `-u, --user USER` | SSH user. Default `ansible` |
| `--only TAGS` | Comma-separated role tags: `ssh`, `kernel`, `auth`, `firewall`, ... |
| `--full` | Run the three-step pipeline: audit, harden, audit |
| `-K, --ask-become-pass` | Prompt for the sudo password on the target |
| `-y, --yes` | `apply` only. Skip the typed confirmation. For automation, and the flag to think about before you use it |

**`--target localhost` hardens the machine you are on**, which is the machine
`inspect` just audited:

```bash
sudo aartool plan  --target localhost      # changes nothing
sudo aartool apply --target localhost
```

It needs no inventory and nothing goes over SSH: aartool writes a one-line
inventory with `ansible_connection=local` for the run and removes it afterwards.
That matters on a package install, where the playbooks live under `/usr/share`
and there is nowhere writable to keep an inventory.

Both commands need root for localhost, and both say so up front rather than
failing inside Ansible. `plan` needs it too: it changes nothing, but it still
reads `sshd_config`, audit rules and sysctls to work out what it *would*
change. Use `sudo`, or `-K` to be asked for the password.

### `surface`

Kernel attack surface: what a local privilege escalation would still reach.

| option | meaning |
|---|---|
| *(none)* | Assess. Changes nothing |
| `--strict` | Include the mitigations that break real workloads |
| `--fix` | Print the sysctl drop-in that would close the gaps |
| `--write FILE` | Write that drop-in to FILE instead of printing it |
| `--apply` | Write to `/etc/sysctl.d/60-aartool-surface.conf` and load it. Needs root |
| `-y, --yes` | Skip the confirmation on `--apply` |

Two tiers, and only `safe` runs by default:

| tier | meaning |
|---|---|
| `safe` | No mainstream workload is known to depend on it |
| `strict` | Will break something real for somebody, and the cost is printed |

Nothing is compiled and nothing is rebooted. Everything applied lands in one
drop-in file you can delete to revert.

### `report`

| option | meaning |
|---|---|
| `--out FILE` | One self-contained HTML file with the results already inside |
| `--open` | Open the dashboard in a browser |
| `--serve PORT` | Serve it on `127.0.0.1` only |
| `--anonymise` | Replace every hostname with `server-01`, `server-02`, ... and every IP with `ip-01`, ... consistently across all reports. Prints the mapping once and stores it nowhere |
| `--redact PAT` | Also replace this literal string everywhere. Repeatable, for the things only you know identify you |

An audit report is a list of a machine's weaknesses with its name attached.
There are good reasons to show one to somebody: a client, a talk, a post
explaining the tool. There is no good reason to hand over the hostnames while
doing it.

```bash
aartool report ./reports/*.json --anonymise --out share.html
```

The substitution is literal and global, not a field rewrite, because a hostname
does not only live in the `host` key: it turns up in evidence strings and
remediation hints too. Renaming the key alone produces a document that looks
anonymised and is not, which is worse than not trying.

`--redact` refuses a pattern that also appears in the report's own structural
fields. `--redact cyberaar` would rewrite every `cyberaar_baseline` key, and the
result is a valid HTML file that opens to an empty page. aartool checks the
finished artefact for that too, rather than trusting the transformation that
produced it.

`--serve` binds to loopback and says so, because this renders audit results for
an entire estate and has no authentication. Reach it with
`ssh -L 8080:127.0.0.1:8080 user@host`.

### `diff`

| option | meaning |
|---|---|
| `--quiet` | Print nothing when nothing regressed |

Refuses to compare two different hosts. A diff between two machines looks
exactly like drift and is not.

### `doctor`

| option | meaning |
|---|---|
| *(none)* | Check everything `plan` and `apply` depend on |
| `--target HOST` | Also test SSH and sudo on that host |

Exits non-zero if anything is missing, so it works as a CI gate. It exists
because `ansible-playbook` failing halfway with "couldn't resolve module
ansible.posix.sysctl" tells an operator nothing about `ansible-galaxy`, and a
half-applied hardening run is expensive.

### `install` / `uninstall`

| option | meaning |
|---|---|
| `--prefix DIR` | Install into `DIR/bin` instead of `/usr/local/bin` |
| `--uninstall` | Remove the symlink |

`aartool uninstall` is the same thing as `aartool install --uninstall`.

On an install that came from a `.deb` or an `.rpm`, both refuse and point at the
package manager:

```bash
sudo apt remove aartool       # Debian, Ubuntu
sudo dnf remove aartool       # RHEL, Rocky, AlmaLinux, Fedora
```

Deleting `/usr/bin/aartool` by hand would leave the package registered as
installed with its command missing, and no later `apt install` would repair
that, because apt already believes the package is present.

---

## Remote hosts and bastions

Most machines worth hardening are not directly reachable. Use `--jump`:

```bash
aartool inspect \
  --host 10.0.1.31 --user admin \
  --ssh-key ~/.ssh/id_ed25519 \
  --jump admin@bastion.example.com
```

Three things worth knowing before you run this against a real estate.

**Use `--jump`, not `--ssh-opt '-J ...'`.** They are not equivalent. `ssh` does
not pass the outer connection's options to the jump hop: not `-i`, not
`StrictHostKeyChecking`, not `BatchMode`. So `-J` alongside `--ssh-key`
authenticates the target with your key and the bastion with whatever the
defaults happen to be, and on a machine with no agent it fails like this:

```
ssh_askpass: exec(/usr/bin/ssh-askpass): No such file or directory
Host key verification failed.
```

A message about the bastion that never names the bastion. `--jump` builds the
`ProxyCommand` itself and carries the same key and connection options onto hop
one. `--ssh-opt` still exists for anything else you need to pass through.

**`--ssh-key` now implies `IdentitiesOnly=yes`.** An agent with several keys
loaded offers each one, every offer counts against the target's `MaxAuthTries`,
and a fleet scan from such a workstation gets that workstation banned by
`fail2ban` across the estate. If you named a key, that key is used and nothing
else. This costs an hour and it happens to everybody once.

**The remote audit does not use `scp`.** OpenSSH 9 switched `scp` to the SFTP
protocol, and a hardened host frequently has the `sftp` subsystem removed, which
is exactly the kind of host you are auditing. aartool pipes the script over
`ssh` with `cat` instead, and reuses one connection with `ControlMaster` so a
fleet scan opens one session per host rather than one per step.

All three are covered by `scripts/tests/proof-remote.sh`, which stands up a
bastion and a private target on a Docker network, removes the `sftp` subsystem
so `scp` genuinely cannot work, and runs the whole loop against them.

---

## Exit codes

| command | 0 | 1 | 2 |
|---|---|---|---|
| `inspect` | audit completed | could not run | |
| `advise` | plan printed | no usable report | |
| `explain` | explained | no such check | |
| `plan` | preview completed | Ansible failed | |
| `apply` | applied | Ansible failed | |
| `diff` | nothing regressed | something regressed | reports not comparable |
| `doctor` | everything present | something missing | |
| `surface` | assessed, gaps or none | bad arguments, or `--apply` without root | |

---

## When something goes wrong

Run the command again with `-v` first. It prints the underlying `ssh` or
`ansible-playbook` invocation, which you can then run by hand.

| symptom | cause | fix |
|---|---|---|
| `Cannot find the toolkit` | aartool was copied rather than symlinked | `export AARTOOL_HOME=/path/to/aartool`, or reinstall with `aartool install` |
| `No inventory at .../inventory/hosts` | `inventory/hosts` is gitignored, so a fresh clone has none | `cp ansible-hardening/inventory/hosts.example ansible-hardening/inventory/hosts` |
| `Target 'x' is not in the inventory` | typo, or the group is spelled differently | `grep -n x ansible-hardening/inventory/hosts` |
| `No audit report given and none found` | no audit has been run in this directory | `sudo aartool inspect`, which writes to `./reports` |
| `does not look like a cyberaar audit report` | the HTML report was passed instead of the JSON | use the `.json` from the same run |
| `couldn't resolve module ansible.posix.sysctl` | collections not installed | `ansible-galaxy collection install -r ansible-hardening/requirements.yml`, then `aartool doctor` |
| `A local audit needs root` | it reads `/etc/shadow`, sshd config, audit rules and sysctls | `sudo aartool inspect`, or audit another machine with `--host` |
| SSH banned you mid-scan | agent offered too many keys, `fail2ban` acted | pass `--ssh-key`, which now implies `IdentitiesOnly=yes`, and wait out the ban |
| `Host key verification failed` reaching a private host | `-J` was used and does not carry the key or options to the jump hop | use `--jump USER@BASTION` instead |
| `scp: subsystem request failed` from an old version | the host has no `sftp` subsystem | upgrade the toolkit; the transport no longer uses `scp` |
| Ansible reports `ok` but nothing changed | `--only` named a tag no role carries | `aartool explain <ID>` prints the tag the map actually uses |
| Container networking died after applying | `ip_forward` was turned off on a Docker host | `aartool explain NET-02`, then set `linux_ip_forwarding_enabled: true` and re-apply |
| Rootless containers broke after applying | `restrict_userns` was enabled | `aartool explain KRN-01`; remove the drop-in line and `sysctl --system` |

If a finding is what you disagree with rather than a failure, `aartool explain
<ID>` is the right next command: it states the cost as well as the benefit, and
"not on this machine" is a legitimate answer that the tool is written to expect.

---

## Environment variables

| variable | effect |
|---|---|
| `AARTOOL_HOME` | Where the toolkit lives. Overrides the upward search |
| `AARTOOL_INVENTORY` | Inventory file to use instead of `ansible-hardening/inventory/hosts` |
| `AARTOOL_VERBOSE=1` | Same as `-v` |

---

## Using it in CI

```yaml
- name: Toolkit prerequisites are present
  run: aartool doctor

- name: Audit
  run: sudo aartool inspect -o ./reports    # explicit, for a fixed CI path

- name: Fail the build on a regression
  run: aartool diff baseline/reference.json ./reports/*.json --quiet

- name: Publish a report anyone can open
  run: aartool report ./reports/*.json --out fleet.html
```

`doctor` as the first step is worth the ten seconds. A hardening run that fails
halfway leaves a machine in a state nobody designed.

---

## What it checks

109 checks across nine families. `aartool explain --list` prints all of them
with their titles.

| family | prefix | checks | covers |
|---|---|---|---|
| Authentication | `AUTH` | 16 | Accounts, PAM, password policy, lockout, sudo |
| SSH | `SSH` | 15 | `sshd_config`, algorithms, banner, timeouts |
| Network | `NET` | 13 | Firewall, forwarding, redirects, source routing |
| Kernel surface | `KRN` | 12 | User namespaces, eBPF, io_uring, userfaultfd, kexec, modules |
| Filesystem | `FS` | 12 | Mount options, permissions, setuid inventory |
| Compliance | `COMP` | 12 | CIS benchmark mapping |
| System | `SYS` | 11 | Distribution, kernel currency, patching, MAC, core dumps, boot |
| Logging | `LOG` | 10 | auditd, journald, forwarding |
| Integrity | `INT` | 8 | AIDE, file integrity |

99 of the 109 map to an Ansible role and appear in the plan `advise` prints. The
ten that do not are informational, or their remediation is not a configuration
change a playbook can make safely: `SYS-11` needs a reboot, `KRN-08` is a boot
parameter, `KRN-12` is a summary of the four above it.

The `KRN` family and `aartool surface` audit the same settings from two
directions, and a test asserts they cannot drift apart.

---

## Extending it

`aartool` is built from `scripts/aartool-src/` by `scripts/build-aartool.sh`,
the same way `aartool-baseline.sh` is built from `scripts/src/`. **Edit the
sources, not the bundle.** CI fails the build if the two drift.

```bash
$EDITOR scripts/aartool-src/cmd/advise.sh
bash scripts/build-aartool.sh
bash scripts/tests/test_aartool.sh
```

### Adding a check

1. Add the `add_result` calls in `scripts/src/checks/<family>.sh`.
2. Add an `ANSIBLE_MAP` entry in `scripts/src/lib/ansible_map.sh`, or a comment
   saying why there is none.
3. `bash scripts/build.sh`.
4. `bash scripts/tests/test_remediation_map.sh`.

### Adding a knowledge-base entry

1. Add the ID to `kb_ids` in `scripts/aartool-src/lib/kb.sh`.
2. Add the `case` branch with the six sections.
3. `bash scripts/build-aartool.sh && bash scripts/tests/test_aartool.sh`.

### The guards, and why they exist

| test | what it prevents |
|---|---|
| `test_remediation_map.sh` | A remediation command naming a tag no role carries. It runs cleanly, matches nothing, changes nothing, exits zero, and you believe the finding is fixed |
| `test_aartool.sh` (KB) | The knowledge base documenting a check that does not exist |
| `test_aartool.sh` (advise) | `advise` printing an `--only` the playbook would ignore |
| `test_aartool.sh` (explain) | A check ID that silently exits mid-page instead of answering |
| `test_escaping.sh` | `</script>` in a hostname ending the block in a report you email to a client |
| `test_distro.sh` | Picking the wrong role family on a derivative distribution |
| aartool-build workflow | The committed bundle drifting from the sources, so editing them stops having any effect |
| `proof-remote.sh` | The transport breaking against a real host while the fleet summary still says "1 succeeded". Needs Docker; run it before releasing a change to `scripts/src/lib/remote.sh` |

Every one of these was written after the failure it describes was found in
shipped code. If you add a guard, prove it fails: break the thing on purpose,
watch the test go red, then put it back.

---

## What it deliberately does not do

- **It does not delete accounts or binaries.** `AUTH-11` (a second UID 0
  account) and `FS-05` (unexpected setuid binaries) are reported, never fixed.
  Acting on either needs someone who knows what the machine runs.
- **It does not edit the kernel command line.** `KRN-08` (lockdown) and Secure
  Boot changes are printed, not applied. A playbook that rewrites GRUB on a
  machine whose console it cannot reach is a way to lose the machine.
- **It does not reboot.** `SYS-11` tells you the running kernel is not the newest
  installed and stops there. On a quorum cluster a reboot is an orchestration
  problem, not a configuration one.
- **It does not apply the strict tier by default.** A tool that silently breaks
  rootless containers gets disabled wholesale, and then none of the safe
  settings apply either.
- **It does not replace your distribution's patching.** Red Hat and Debian ship
  the patch. `surface` is for the window before the patch exists, and for the
  machine you cannot reboot until the change window in three weeks.

## paths, badge and demo

A list of 40 findings ranks nothing. An attacker does not exploit a list; they
walk a chain of *way in, way up, way to stay, way to not be seen*. Each link
alone is a "medium". Together they are the incident.

```bash
aartool paths            # which attack chains are complete on this host?
aartool paths || exit 1  # fail a CI job while any chain is complete
```

```
● COMPLETE  The silent tenant: root to never found
   [1] Persist below the OS      open   KRN-05 KRN-06 KRN-08
   [2] Nobody is recording       open   LOG-01 LOG-06 LOG-02
   [3] Nobody would notice       open   INT-01 INT-02 LOG-08
   A safe link to cut: KRN-06  kexec allowed
```

Breaking **one** link breaks the chain, so you can stop fixing everything and
fix the cheapest thing that matters. Read-only, derived from the audit alone.

`aartool badge [REPORT.json] [--out FILE.svg]` writes a self-contained SVG of the
score (red under 50, amber to 74, green to 89, bright green from 90) and prints
the Markdown to embed it. `aartool demo` runs `advise`, `paths` and `explain`
on a bundled sample audit: no root, no SSH, nothing read from the machine.

### paths across an estate, and as a diagram

```bash
aartool paths web-01.json web-02.json web-03.json   # one report per host
aartool paths web-01.json --format mermaid          # a diagram, one host
```

With several reports, `paths` shows for each chain which hosts have it complete
and the smallest set of findings whose closure breaks it on all of them. That is
the change to make in a shared role, not a list of hosts. A fix that needs a
decision is flagged. Two reports for the same host are refused, because a
before and after pair would count one machine twice; pass the newest per host.

`--format mermaid` prints a flowchart that GitHub, GitLab and most wikis render
inside a code fence with the language `mermaid`. It contains only the chain
definitions and check IDs plus the host name reduced to letters, digits and
`._-`, so a hostile hostname cannot inject diagram syntax. Exit codes are the
same as the text view: 1 when any chain is complete.
