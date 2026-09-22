# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **Two audit rules named syscalls that do not exist on x86_64, and that took
  the rest of the ruleset down with them.** `linux_auditing_ubuntu` and
  `linux_auditing_rhel9` both emitted `-S umount,umount2` and
  `-S adjtimex,settimeofday,stime`. Neither `umount` nor `stime` is an x86_64
  syscall, and `augenrules --load` does not skip a rule it cannot parse: it
  aborts at that line. Every rule after it, *including the closing `-e 2` that
  makes the ruleset immutable*, was therefore never loaded. A hardened host ran
  a fraction of the rules the benchmark asks for and stayed mutable, which is
  the opposite of what the role reports.

- **Nothing would have noticed.** The roles never ran `augenrules --load` at
  all; they wrote the file and notified a `Restart auditd` handler that carries
  `failed_when: false`, and auditd's own `ExecStartPost` carries a leading `-`.
  Three layers each turned the failure into a success. The roles now load the
  ruleset explicitly and fail on a rejected rule, while still treating an
  already-immutable ruleset (`enabled 2`) as the configured end state rather
  than an error, reporting that the change applies at the next reboot.

- **The test asserted something that could not fail.** Verification checked only
  that `auditctl -l` exited 0, and it exits 0 while printing `No rules`, so it
  passed against an empty ruleset. It now asserts on content, and a separate
  static assertion rejects any rendered ruleset naming `umount` or `stime` so
  the class of fault is caught even in containers where no rules can load.

## [3.5.3]: 2026-08-29

### Reverted

- **The single filesystem walk from 3.5.2 is reverted.** FS-05, FS-07 and FS-10
  go back to running their own `find / -xdev`. The combined traversal measured
  faster here and was slower in real use, which is the measurement that counts.
  Behaviour is identical to 3.5.1.

## [3.5.2]: 2026-08-29

### Changed

- **The filesystem was walked once instead of three times.** Reverted in 3.5.3;
  do not install this version for the change, it is superseded.

## [3.5.1]: 2026-08-29

### Fixed

- **The score box lost its banner.** `rule()` built the horizontal lines with
  `tr ' ' '━'`, and `tr` translates BYTES: `━` is three of them (`e2 94 81`), so
  every space became a lone `0xe2` and the summary printed a run of invalid
  UTF-8 where the banner should be. Introduced in 3.5.0 when the rules were made
  adaptive, and spotted by a reader rather than by the suite, which never looked
  at what a rule contained. Now built with parameter substitution, which
  replaces strings rather than bytes, and guarded on the character count, the
  byte count and UTF-8 validity.
- **The remediation plan told you to run a command that fails.** It read
  *"Ajoutez `--check --diff` pour simuler"*: French in an English document, and
  wrong, since `--check` and `--diff` are `ansible-playbook` flags while every
  command in that table is `aartool apply`, which rejects them. It now points at
  `aartool plan`. The Tags column advertised `--tags` beside a command using
  `--only`; both say `--only`.
- Two more French strings in that section: the `Commande aartool` column header
  and a bilingual button label.
- **Colours written as `rgba()` escaped the palette port.** `rgba(0,194,168,…)`
  is the old teal and `rgba(126,211,72,…)` the old lime, so borders, glows and
  table hovers did not follow the print theme. Sixteen literals are tokens now.

### Added

- **A guard that every check carries a French name.** `NAME_FR` is rendered by
  nothing: the tool is English on every surface. It is kept because it is
  complete, one correct and accented name for every branch of every check, which
  is the expensive half of a French mode. An asset like that does not die by
  being deleted, it dies by rotting: a new check family gets `""` because nothing
  displays it, and a year later the set is 80% complete and worth nothing.
  `scripts/tests/test_french_names.sh` fails on an empty French name, on the
  English copied into the French slot, and on its own extraction matching
  nothing. The copy threshold is derived from the two legitimately identical
  names in the tree (`SELinux Enforcing`, `SELinux Permissive`), not picked.

### Fixed

- **The report told you to run a command that fails.** The remediation plan read
  *"Ajoutez `--check --diff` pour simuler"*: French, in an English document, and
  wrong. `--check` and `--diff` are `ansible-playbook` flags, while every command
  in that table is `aartool apply`, which rejects them outright. It now says to
  preview with `aartool plan`. The Tags column advertised `--tags` next to a
  command using `--only`; both say `--only` now.
- Two more French strings in the same section: the `Commande aartool` column
  header and a bilingual `Tout corriger en une commande / Fix everything in one
  run` button label.
- **The palette port missed every colour written as `rgba()`.**
  `rgba(0,194,168,...)` is the old teal and `rgba(126,211,72,...)` the old lime,
  so borders, glows and table hovers stayed off-palette and did not follow the
  print theme. Sixteen literals replaced by tokens, with print variants.

### Changed

- `add_result`'s signature comment said its last parameter was `REMEDIATION_FR`,
  which has not been French for a long time, and said nothing about `NAME_FR`
  being carried but unrendered. Both documented.

## [3.5.0]: 2026-08-29

### Changed

- **The HTML report and the dashboard are one design system now.** The report
  carried its own palette, a teal and a lime green that appear nowhere else in
  the product, while the dashboard uses the tokens from
  `website/src/styles/global.css`. The report now uses those: same colours, same
  type scale, same radii. Colours are defined once and aliased, so the print
  theme re-colours everything through one override.
- **The CLI table fits the terminal.** Width came from a hard-coded 86 while
  rows ran to 156 characters, because the DETAIL column had no bound: section
  rules ended 70 columns short of the content they were ruling off, and on a
  standard 80-column terminal every row wrapped. Width now comes from
  `tput cols`, clamped to 60-140, with the columns derived from it once so the
  header and the rows cannot disagree. Long values are truncated with an
  ellipsis; the full text is in the JSON, the HTML and `aartool explain`.
- Findings are printed with the check name and detail truncated to the
  available space rather than the terminal wrapping them mid-word.

### Added

- **`wave` on every JSON result.** Reachability ordering is what `advise` is
  for, and a consumer of the JSON had to reimplement it to reproduce the
  ordering. Same reason `remediation_tags` exists. `scripts/tests/test_waves.sh`
  asserts the engine's mapping and `advise`'s agree for every check ID, so the
  two copies cannot drift.
- **`date_iso`**, UTC and RFC 3339, alongside the existing human-readable
  `date`, which has no timezone and cannot be ordered across hosts in different
  zones. `date` is unchanged, because the HTML header shows it and the dashboard
  sorts on it in every report already written.

### Fixed

- **The HTML report loaded fonts from Google on every open.** An audit report is
  a list of a machine's weaknesses, and opening one told a third party the IP
  and referrer of whoever read it, including reports scrubbed with `--anonymise`
  precisely so they could leave the estate. It also made "opens offline" untrue.
  Webfonts are gone, replaced by the dashboard's system stacks, and a guard in
  `test_dashboard.sh` now fails on any subresource fetched over the network.
  Anchors still work: following a link is the reader's decision.
- **Printing produced a near-blank document.** The report is a dark ground with
  near-white text and the whole print stylesheet was four lines that reset no
  colours; browsers do not print backgrounds by default, so the text landed on
  white paper. There is now a real A4 print stylesheet that switches to the
  light palette, keeps status fills with `print-color-adjust`, and avoids
  breaking a finding across pages.
- **The score colour was written into the document as a literal hex**, which put
  the largest element on the page outside the palette: it could not follow the
  print theme. It is emitted as a token. Score labels were rebanded so `BON` no
  longer appears in amber.
- **Colour was emitted whether or not stdout was a terminal.** Redirecting an
  audit to a file wrote 134 lines of raw ANSI escapes into it, and the
  `aartool diff ... || mail` pattern in the README mailed escape sequences.
  `NO_COLOR` and `FORCE_COLOR` are both honoured.
- **The HTML report is in English, and says so.** It declared `lang="fr"` and
  printed `CRITIQUE` / `FAIBLE` / `MOYEN` as the score label, either side of
  English check names and English remediation, and computed a French check name
  into a variable it never rendered. Score labels are now
  CRITICAL / WEAK / FAIR / GOOD / STRONG, the four remaining French remediation
  strings are translated, and a guard fails on French reaching the report. If a
  French report is wanted it should be a mode, not four leftover strings.
- Em dashes removed from check output, per house style.

## [3.4.0]: 2026-08-28

### Changed

- **One name in the output: `aartool`.** The tool called itself four things.
  The terminal said "CyberAar Security Score", `--help` said "CyberAar Security
  Baseline Checker", the HTML said "CyberAar Baseline Checker" in the footer and
  plain "Security Score" in the body, and only the dashboard said `aartool`.
  CyberAar is the company; aartool is the product. Every user-facing string now
  names the product.
- **`cyberaar-baseline.sh` is now `aartool-baseline.sh`**, and reports are
  written as `aartool-<host>-<date>.{html,json}`. Report discovery still matches
  the old `cyberaar-*.json` filenames, so `advise` and `report` keep finding
  audits taken before this release.
- **The JSON root key is `aartool`**, was `cyberaar_baseline`. Every reader in
  the toolkit accepts both, so existing reports still load in the dashboard, in
  `diff` and in `report`. External parsers should read `aartool` with the old
  key as a fallback.
- **A warning now counts as half a failure in the score**, where it used to
  count as a whole one. `score = (PASS + WARN/2) / TOTAL`. A stock Ubuntu box
  with 8 failures and 57 warnings scored 40% in red and now scores 67%. Many
  warnings mean "could not be verified here" (no `/boot`, no `mokutil`, no
  systemd in a container) rather than "is wrong", and scoring those exactly like
  `PermitRootLogin=yes` made the headline number untrustworthy.
  **Scores are not comparable across this change**; `aartool diff` now says so
  when the two reports come from different engine versions.
- The terminal summary leads with failures rather than passes, and states the
  weighting under the score.

### Fixed

- **Kernel checks printed above the first section header, with no header of
  their own.** `checks/kernel.sh` was the only check family with no wrapping
  function, so its twelve `KRN-*` results ran at bundle-load time, before
  `run.sh` had called anything. They now run as "1b. KERNEL ATTACK SURFACE",
  in the position the build order already implied.
- **Reports were unreadable by the person who ran them.** The standalone script
  must run as root, so it wrote `root:root` mode 600 and left the invoking user
  unable to open the file it had just printed a path to; `aartool report` and
  `aartool diff` both failed on it. `aartool inspect` already handed reports
  back to `SUDO_UID`, the standalone script did not, and the standalone script
  is the path the README advertises as the fastest way to try the tool.
- The HTML report subtitle repeated the `<h1>` verbatim.
- **INT-07 duplicated INT-01.** With AIDE absent both emitted the identical
  title "AIDE not installed", so one missing package read as two problems and
  was counted twice.
- **The `--help` banner executed a command and printed a version from the build
  machine.** It carried a backtick-quoted `aartool --version` inside an
  unquoted heredoc, so at display time it ran whatever `aartool` was installed
  and printed that version to the user. A build made on a box with an older
  package advertised `aartool 3.3.6` from a source file containing no such
  number. Caught by running the staged release asset before tagging; guarded
  now, in both directions (no undeclared version in `--help`, no backtick in
  the banner at all).

## [3.3.7]: 2026-08-27

### Fixed

- **`aartool report` with no arguments wrote an empty dashboard.** `advise`
  with no argument reads the most recent report; `report` did the opposite, so
  someone who had just run `inspect` and typed
  `aartool report --out audit.html` got a 190K file with nothing in it. The
  only warning was a parenthetical in the success line. It now uses the newest
  report from the same three locations `advise` searches, and says which one it
  picked.

  The empty dashboard is still available as `--empty`, because dragging reports
  onto it is a real workflow, just not the one you get by typing nothing.

Found while recording a demo, where the obvious command produced an empty
deliverable.

## [3.3.6]: 2026-08-27

**`aartool plan` now runs to completion on a fresh host.** Previously it stopped
at whichever of these came first.

### Fixed

- **AIDE initialisation used async, which Ansible refuses under `--check`**:
  "check mode and async cannot be used on same task". A validation error,
  raised before the task would have been skipped for being a command, so the
  run died rather than previewing. Guarded on `ansible_check_mode`, with a note
  saying what apply would do. It is the only async task in the codebase.
- **The GRUB bootloader role failed the whole run when
  `LINUX_BOOTLOADER_PASSWORD` was unset**, while `run-hardening.sh` printed
  "bootloader_password role will be skipped" three lines earlier. The wrapper's
  promise and the role's behaviour contradicted each other and the role won, so
  a first preview on an ordinary server died on a variable the user had just
  been told was optional. Only WSL escaped it, because the role skips itself
  there for unrelated reasons. Both bootloader roles now skip with an
  explanation and gate their remaining tasks on the password being set.

  **Behaviour change:** asking for a GRUB password without providing one no
  longer aborts the run.

- `test_service_guards.sh` also rejects an async task with no check-mode guard.

A full `aartool plan --target localhost` on a fresh Ubuntu host now reports
ok=128, changed=74, failed=0.

## [3.3.5]: 2026-08-27

### Fixed

- **40 service tasks could not survive a preview.** `aartool plan` runs the
  playbook with `--check`, which installs nothing, so a role that installs a
  package and then starts its service met a unit that was not there:
  `Could not find the requested service ssh`. The ssh task was already guarded,
  but on `_skip_service_mgmt`, which covers WSL *without* systemd; modern WSL
  has systemd, so the guard passed and the unit was still absent. A `when:` on
  a service task does not mean it is guarded against the unit not existing,
  which is why the ufw fix in 3.3.4 did not prevent this.

  The playbook now inventories the systemd units once, in a pre_task with
  `check_mode: false`, and shares it as `aartool_units`. Every service task
  with a literal name is guarded on it in check mode only, so behaviour outside
  a preview is unchanged. Of the 48 service tasks in the roles, the 8 left
  alone were already safe: six name no service (daemon-reload), two use
  templated names guarded on `ansible_facts.services`, and one tolerates
  failure.

- `test_service_guards.sh` enforces this for every future service task and runs
  in CI, so the class cannot come back one role at a time.

Reported by a user running `aartool plan` on WSL. Both this and the 3.3.4
firewall bug came from testers on a platform that is not the target, which is
exactly why they found them: a real server already has ufw, ssh and systemd
present, so the whole class was invisible there.

## [3.3.4]: 2026-08-26

### Fixed

- **`plan` failed on any host without a firewall package installed**, which is
  the host that most needs the firewall role. A preview installs nothing, so
  the package task reported "would install" and changed nothing, the binary
  verification was skipped because command modules do not run under `--check`,
  and the ufw module then ran against a binary that was not there:
  `Failed to find required executable "ufw"`. Both firewall roles now probe
  with `check_mode: false` and gate their configuration on the result, so a
  preview reports what `apply` would do. The ufw reload handler needed the same
  guard: handlers run at the end of the play, so it fired after every gated
  task had correctly skipped.
- **Five firewalld tasks lost their conditions.** They already carried a
  `when:` before the module key, and the new guard was appended as a second
  one; in YAML the later key wins, so conditions including
  `_firewalld_active | bool` would have been discarded and services removed
  regardless of them. Merged into single lists. Found by ansible-lint's
  `key-duplicates` while fixing the above, not by the failing run.

Reported by a user running `aartool plan --target localhost` on a fresh
machine.

## [3.3.3]: 2026-08-26

### Changed

- **inspect output is a table, and the score is at the end of it.** 109 results
  printed as 327 lines with the score in the middle. Each result is now one
  aligned row: STATUS, ID, CHECK, DETAIL, under a column header per section.
  Default output is 145 lines. Two things had been breaking the alignment: the
  status emoji, since `PASS` is one cell wide, `WARN` two plus a variation
  selector and `FAIL` two, so no two rows lined up; and a fixed-length section
  rule appended to a variable-length title.
- **The check ID is printed.** `aartool explain SSH-01` needs it, and the only
  place it appeared was the JSON report.
- **inspect no longer prints a remediation plan.** It used to follow the score
  with 117 lines grouped by Ansible tag. `aartool advise` does that job ordered
  by what an attacker reaches first, with the cost of each fix, and inspect now
  points at it.
- **Per-check fixes move behind `--hints`.** They printed under every non-PASS
  result, which is what doubled the length. `aartool explain <ID>` gives the
  same thing in full plus what closing the finding breaks.
- **The tool speaks English only.** All 119 remediation hints were French while
  every check name was English, so a single run mixed the two. The bilingual
  halves of the section titles and the per-check French line in the HTML report
  went with them, along with the report's French labels. Guarded: French text
  in a renderer fails the suite.

## [3.3.2]: 2026-08-26

### Fixed

- **`plan` and `apply` did not work from a package at all.** nfpm does not carry
  symlinks it finds inside a directory tree, so
  `ansible-hardening/playbooks/roles`, a symlink to `../roles`, was dropped
  silently. Every package shipped all 52 roles and no way for Ansible to reach
  them, failing with `ERROR! the role 'linux_kernel_hardening_rhel9' was not
  found`. Affected 3.3.0 and 3.3.1. The commands that need no Ansible all
  worked, so the package looked healthy. The link is now declared explicitly,
  and `run-hardening.sh` also exports `ANSIBLE_ROLES_PATH`, because the one path
  without which nothing runs should not depend on a symlink surviving a
  packaging step.

### Added

- **`plan` and `apply` check for the required Ansible collections first** and
  print the `ansible-galaxy` command, rather than letting Ansible fail with
  `couldn't resolve module/action 'ansible.posix.selinux'` pointed at a line
  inside a role, which reads like a bug in the role rather than a missing
  dependency on the machine.
- **`doctor` reports when another aartool is ahead on PATH.** `install`
  symlinks into `/usr/local/bin`, which precedes `/usr/bin`, so an old clone
  install silently shadows a newer package and you run the old version with none
  of its newer commands.

## [3.3.1]: 2026-08-26

### Fixed

- **Every audit ended with a command the reader could not run.** The
  remediation block printed `ansible-playbook -i inventory/hosts
  playbooks/...`, whose paths resolve only inside a git checkout. On a package
  install the playbooks are under `/usr/share/aartool` and that command fails
  immediately. Both the terminal and HTML reports now print
  `aartool apply --target <host> --only TAGS`, which is also the guarded path:
  `apply` requires a target and makes you type its name back, while a bare
  `ansible-playbook` with no `-l` defaults to the whole inventory.
- **The documented apt install failed on any machine with a strict umask.**
  `curl | sudo tee` created the keyring with the caller's umask; at `umask 027`
  that is mode 0640, and apt verifies as the unprivileged `_apt` user, which
  cannot read it. It failed with `Unknown error executing apt-key`, naming
  neither permissions nor the file. The instructions now `chmod a+r` the key.

### Added

- **`--target localhost`** for `plan` and `apply`: harden the machine you are
  on, with no inventory and nothing over SSH. This is the machine `inspect`
  just audited, and until now hardening it required an inventory entry, which a
  package install has no way to create. Both commands say up front that
  localhost needs root, rather than failing inside Ansible with "Premature end
  of stream waiting for become success".
- **`aartool uninstall`**, which previously reported itself as an unknown
  command while the same thing existed behind `install --uninstall`. On a
  packaged install it refuses and points at `apt remove` or `dnf remove`:
  deleting the symlink would leave the package registered and its command
  missing, which no later `apt install` would repair.

## [3.3.0]: 2026-08-25

### Added

- **aartool installs from a package.** A `.deb` and an `.rpm` are attached to
  this release and served from a signed repository at `pkgs.cyberaar.io`, so
  installing is `apt install aartool` or `dnf install aartool` after adding one
  source. Both are noarch. Ansible is a recommended dependency rather than a
  required one: the audit half of the tool never calls it, and a tool that
  claims to run on a constrained machine should not pull in the Ansible stack
  before it will read your sshd_config.
- **A banner on the human-facing paths.** A bare invocation and `--help` open
  with the tool's name and version. Not `--version`, which is parsed by
  scripts, and not on subcommands or error paths. A locale-chosen ASCII
  fallback covers terminals that cannot render block glyphs, which on a serial
  console or a rescue shell is not hypothetical.

### Fixed

- **LICENSE contained a placeholder rather than the licence.** The file held
  the literal text `[... full GPL-3.0 text ...]` where the terms should have
  been, so the project advertised GPL-3.0 while granting nothing and GitHub
  reported it as unlicensed. It is now the canonical GPL-3.0 text.

### Changed

- A packaged install reads its inventory from `/etc/aartool/inventory`.
  Everything under `/usr/share` belongs to the package manager and is replaced
  on upgrade, so an inventory there would be destroyed by the next
  `apt upgrade`. A git checkout is unaffected.

## [3.2.0]: 2026-08-23

### Changed

- **The dashboard is rebuilt for the person reading the audit, not the person
  who ran it.** It was a grid of score rings with an "Ansible Remediation" box
  offering a raw `ansible-playbook` command, and it never mentioned aartool.

  Panels now follow the order an auditor asks the questions: a stat row, then
  **Score by host** as a bar gauge sorted worst first so the first thing on
  screen is where to start, then **Where the findings are** across the whole
  estate, then **Fix once, help most hosts**, which ranks findings by how many
  machines they affect. Sort, scope and search sit above the panels rather than
  inside them.

  The host drawer orders findings into `aartool advise`'s waves and pulls
  anything whose fix carries a real operational cost into "decide before you
  apply", out of the sequence someone is about to run.

- **Remediation is expressed as aartool commands throughout**: `plan` and
  `apply` scoped with `--only`, `inspect` and `diff` to prove the movement, and
  `explain` on any individual finding.

- The dashboard uses the CyberAar palette, the same hex values as cyberaar.io,
  so a score colour means the same thing on the site, in the HTML report and in
  the dashboard.

### Added

- **`remediation_tags` in the JSON report**: the tag each finding is remediated
  by. A consumer can now build a working `aartool plan --only ...` without
  carrying its own copy of `ANSIBLE_MAP`, which is exactly the duplication that
  has caused drift in this repository three times. Reports written before this
  field still render; they get commands without `--only` and a line saying why.

- `test_dashboard.sh`: asserts the dashboard's mirrored copy of advise's wave
  and decision tables still matches advise id for id, that the `renderAll`
  contract `aartool report --out` injects against still exists, that the file
  references nothing outside itself so it works on an isolated network, that the
  palette tokens are present, and that the whole thing renders a real captured
  report under a stub DOM without throwing. It caught drift on its first run:
  `AUTH-14` was in advise's decision list and missing from the dashboard's.

## [3.1.0]: 2026-08-23

Hardening was applied end to end to a live server for the first time: doctor,
plan, apply, re-inspect, diff, on a docs host running BookStack in containers.
The service stayed up, the score moved 72 to 75, nothing regressed. Getting
there surfaced four defects that no test had, and every fix below came from that
run rather than from review.

### Fixed

- **`SYS-10` could never pass, on any host, ever.** It tested masking with
  `systemctl is-masked`, which is not a systemd verb: systemd answers "Unknown
  command verb" and exits non-zero. Every host ever scanned reported FAIL,
  including hosts where `ctrl-alt-del.target` was correctly symlinked to
  `/dev/null`. Confirmed across 15 nodes: 15 FAIL, 0 PASS, all masked. Now uses
  `is-enabled`, which reports `masked`, and prints the observed state as
  evidence.
- **`SYS-03` meant two different things depending on the platform.** dnf and
  zypper were asked for security updates; apt was asked for every upgradable
  package. A host with automatic security updates working, zero security updates
  outstanding and twenty routine ones reported the same FAIL as a RHEL host with
  twenty live CVEs. The apt branch now scopes to security and reports both
  counts: "0 security (20 total pending)".
- **`AUTH-03` could not be fixed by its own remediation.** The check wants
  `PASS_MAX_DAYS <= 90`; `linux_user_management_rhel9` set 90 and
  `linux_authselect_ubuntu`, which owns `/etc/login.defs` on Ubuntu, set 365. On
  Ubuntu you could apply the recommended fix, re-audit and see no change,
  indefinitely. The Ubuntu default is now 90, matching RHEL and the check.
- **`plan` and `apply` could not use an SSH key.** `inspect` always could. On an
  estate with a dedicated key they failed with `Permission denied (publickey)`,
  which reads as a fault on the target rather than a missing flag.
  `--ssh-key` is plumbed through `run-hardening.sh` as `-i`.
- **`doctor --target` could not check a host that needs a user.** It connected
  as whoever ran it, so it called a reachable host unreachable and printed a fix
  line that repeated its own mistake. It takes `--user` and `--ssh-key` now.

### Added

- `doctor` also verifies passwordless sudo on the target. Reachable is not the
  same as able to change anything, and finding that out at apply time means
  finding out halfway through a hardening run.
- `FS-04` and `FS-07` are treated as decisions rather than wave items, with a
  knowledge-base entry for `FS-07`. On a container host essentially every
  world-writable directory is inside the image store: on the machine used for
  this run, all 3622 of them were under `/var/lib/containerd`, where a mass
  chmod corrupts image layers.
- `test_check_commands.sh` validates every `systemctl` verb the checks invoke
  against the real tool's help, and asserts `SYS-03` scopes to security updates
  on all three package managers.
- `test_remediation_map.sh` asserts role defaults satisfy the thresholds the
  checks demand, so a role cannot again write a value its own checker rejects.

### Changed

- `linux_authselect_pass_max_days` default 365 to 90. CIS Ubuntu 22.04 5.5.1.2
  permits up to 365 and NIST SP 800-63B argues against forced expiry entirely;
  override the variable if your policy differs. The point is that the tool and
  its own remediation now agree on a number.

## [3.0.0]: 2026-08-23

The release that gives the toolkit a front door. Everything here was either
built or corrected while running the tool against a real 15-node estate, not
against its own tests.

### Added

- **`aartool`**, one command in front of everything. `inspect`, `advise`,
  `explain`, `plan`, `apply`, `surface`, `doctor`, `report`, `diff`, `install`.
  Neither `cyberaar-baseline.sh` nor `run-hardening.sh` is replaced and both
  stay independently usable. Two deliberate differences from what it wraps: the
  dry run is a command (`plan`) rather than a flag, and `--target` is required,
  because `run-hardening.sh` defaults to the group that is the entire inventory.
- **`aartool advise`**: turns a report into waves ordered by reachability, not
  severity. What an attacker reaches with no account, then what turns an account
  into root, then what would have stopped you noticing. Findings whose fix has a
  real operational cost are lifted into a separate "decide before you apply"
  list rather than hidden.
- **`aartool explain <ID>`**: what a check reads, the concrete path from finding
  to compromised machine, what closing it breaks, how to fix it by hand and with
  Ansible. 36 written entries; answers for all 109 IDs by falling back to the
  remediation map.
- **`aartool surface`**: the kernel attack surface as a first-class subject.
  Unprivileged user namespaces, eBPF, io_uring, userfaultfd, kexec, module
  loading, TTY line-discipline autoload, lockdown, BPF JIT hardening, SysRq.
  Two tiers, and only `safe` applies by default.
- **13 new checks**, 96 to **109**: the `KRN-01`..`KRN-12` kernel attack-surface
  family and `SYS-11`, which detects a kernel installed but not running.
- **`aartool report --out`**: one self-contained HTML file with the results
  embedded, openable offline on a machine that has never heard of this toolkit.
- **`aartool diff`**: exit `0` nothing regressed, `1` regressed, `2` not
  comparable. Refuses to compare two different hosts.
- **`--jump USER@HOST[:PORT]`** for auditing through a bastion, which is the
  shape of most estates.
- **9 kernel attack-surface toggles** in `linux_kernel_hardening_rhel9` and
  `_ubuntu`, so every `KRN` finding has a remediation path. Six default on, the
  three that break real workloads default off with the reason written beside
  them.
- **`docs/`**: `AARTOOL.md`, `ANSIBLE.md`, `BASELINE.md`, `DASHBOARD.md`,
  `CONTAINER.md`.
- **Guard tests**, each written after the defect it describes was found in
  shipped code: remediation-map validity, documentation against the CLI's own
  help, knowledge-base accuracy, distribution mapping, report escaping, version
  consistency, and a Docker-based end-to-end proof of the remote path.

### Changed

- **The repository is now `cyberaar/aartool`** (was `cyberaar-toolkit`). GitHub
  redirects the old URL permanently. The collection remains
  `cyberaar.hardening`: the repository is the product, the collection is a
  library it ships.
- **The container image is `ghcr.io/cyberaar/aartool`** and now contains
  `aartool` itself, which the `ee-hardening` image never did. The old name is
  still pushed so existing pulls keep working.
- `aartool inspect` writes reports to `./reports` by default and hands them back
  to the user who invoked `sudo`. Previously it wrote nothing without `-o`, so
  the documented two-command first run failed for every new user.
- The root README is the workflow and nothing else; the reference material moved
  to `docs/`.
- Distribution detection consults `ID_LIKE` before `ID`, so derivatives inherit
  the right role family instead of being told to switch operating system.

### Fixed

- **The JSON report claimed `"version": "4.0.0"` regardless of the script's real
  version**, which had been `4.2.0`. Hardcoded in the renderer. Anything keying
  off that field, a SIEM ingest or an auditor asking which build produced the
  evidence, was told something untrue. Now interpolated, and guarded.
- **The remote audit could not work on a hardened host and reported success
  anyway.** OpenSSH 9 `scp` speaks SFTP, and removing the `sftp` subsystem is a
  normal hardening step, so the copy failed on exactly the machines most likely
  to be running a security tool. Replaced with an `ssh`-piped `cat`, every step
  now checked, and connections multiplexed so a fleet scan does not look like a
  brute-force attempt to `fail2ban`.
- **`--ssh-opt '-J user@bastion'` never worked with `--ssh-key`.** `ssh` does not
  pass the outer connection's options to the jump hop, so hop one authenticated
  with whatever the defaults were. `--jump` builds the `ProxyCommand` correctly.
- `--ssh-key` now implies `IdentitiesOnly=yes`, so a fleet scan from a
  workstation with several keys loaded does not get that workstation banned.
- Four knowledge-base entries described the wrong check. Existence was guarded;
  topical accuracy was not. Both are now.
- The HTML report shipped invalid CSS from a `${RING_COLOR}ALPHA` typo, so the
  score ring had no glow and nothing was linting the file.
- Every audit printed a remediation command referencing `inventory/hosts.yml`,
  which has never existed.

### Security

- `agent`-side changes only. No credential handling changed in this release.

## [2.0.0]: 2026-03-12

### Added

- **`dashboard/index.html`**: single-file, zero-dependency web dashboard for visualising `cyberaar-baseline` JSON reports:
  - Fleet overview: score ring per host (green ≥ 80%, amber ≥ 60%, red < 60%), PASS/WARN/FAIL counts, sorted worst-first
  - Before/after comparison: automatic when two reports for the same host are loaded, score delta pill + side-by-side score boxes
  - Host detail slide-in panel: full 96-check table with FAIL/WARN/PASS filter
  - Copy-ready `ansible-playbook` remediation command per host
  - PDF export via browser print (header and panel hidden automatically)
  - CyberAar PNG logo embedded as base64, consistent branding with HTML baseline report
  - Works fully offline, no CDN, no npm, no build step; compatible with air-gapped environments
- **`execution-environment/Containerfile`**: Docker/Podman execution environment published to `ghcr.io/cyberaar/ee-hardening`:
  - Built on `python:3.11-slim`; includes `ansible-core`, `cyberaar.hardening`, `ansible.posix`, `community.general`
  - Playbooks embedded at `/usr/share/cyberaar/playbooks/`; `cyberaar-baseline` at `/usr/local/bin/`
  - `COLLECTION_VERSION` build arg pins exact collection release; `latest` + `vX.Y.Z` tags pushed on every GitHub release
  - Zero local Ansible install required, one `docker run` to harden a server
- **`.github/workflows/ee-build.yml`**: CI/CD for EE image; authenticates via `GITHUB_TOKEN` (no extra secrets needed)

### Changed

- **Repo structure flattened**: `automation/ansible-hardening/` → `ansible-hardening/`; `automation/scripts/` → `scripts/`; `automation/` directory removed. All workflow, README, and script path references updated.
- **`2_configure_hardening.yml`**: added explicit `ansible.builtin.setup` task with `become: false` and `tags: always` in `pre_tasks`. Fixes `ansible_os_family is undefined` error when running with `--tags <non-hardening>` (e.g. `--tags ssh`), caused by play-level `tags: [hardening]` causing `gather_facts` to be skipped while `pre_tasks` tagged `always` still execute.
- **`.gitignore`**: replaced Jekyll boilerplate with relevant entries: `.ansible/`, `*.tar.gz`, `mnt/`
- **Issue templates**: replaced content-oriented templates with technical ones: `bug-report.md` (Ansible role / baseline script bugs), `feature-request.md` (new hardening controls / baseline checks); `best-practice-suggestion.md` removed (moved to `cyberaar/Aar-Act`)
- **PR template**: reoriented to technical contributions: CIS reference field, Molecule test-plan checklist

### Fixed

- Committed Galaxy build artifact (`cyberaar-hardening-1.9.0.tar.gz`) removed from git history
- Orphaned `automation/example.md` removed
- `reports/` `.gitkeep` files removed (directory already covered by `.gitignore`)

## [1.9.1]: 2026-03-12

### Added

- **`cyberaar-baseline.sh` v4.2.0**: 3 new checks (96 total):
  - **NET-13** (CIS 3.3.1): IPv6 fully disabled, checks `net.ipv6.conf.all.disable_ipv6=1` + `default`; maps to `linux_ipv6_*`
  - **LOG-09** (CIS 4.2.1.1): journald `Storage=persistent` configured in drop-in conf; maps to `linux_journald_*`
  - **LOG-10** (CIS 4.2.1.3): journald `RateLimitBurst` configured; maps to `linux_journald_*`
  - Ansible map updated: `LOG-07` now maps to `linux_journald_*` (was `linux_auditing_*`)
- **`.github/workflows/baseline-build.yml`**: CI job that verifies `build.sh` succeeds, checks bundle is in sync with `src/`, validates bash syntax, and asserts ≥ 90 unique check IDs

### Changed

- `cyberaar-baseline.sh` / `src/main.sh`: version bumped 4.0.0 → 4.2.0 (4.1.0 was a documentation-only bump that was never reflected in the source)

## [1.9.0]: 2026-03-12

### Added

- **`linux_ipv6_rhel9` + `linux_ipv6_ubuntu`**: Disable IPv6 at kernel level (CIS 3.3.1): sysctl `net.ipv6.conf.{all,default,lo}.disable_ipv6=1` persisted to `/etc/sysctl.d/99-cis-ipv6.conf`; modprobe `options ipv6 disable=1` persisted to `/etc/modprobe.d/99-cis-ipv6.conf`; Ubuntu variant runs `update-initramfs -u -k all` to persist across kernel updates
- **`linux_journald_rhel9` + `linux_journald_ubuntu`**: systemd-journald hardening (CIS 4.2.1.x): drop-in `/etc/systemd/journald.conf.d/99-cis-journald.conf` sets persistent storage, compression, syslog forwarding, rate limiting, and disk retention limits; `/var/log/journal` created for persistent mode
- **NFS mount scan** in `linux_file_permissions_rhel9` / `linux_file_permissions_ubuntu`: new `linux_file_permissions_check_nfs_mounts` variable (default `true`) scans `/etc/fstab` for NFS entries and emits a debug warning if found (CIS 1.1.x, verify nodev/nosuid on NFS)
- **Molecule scenarios**: `ipv6` and `journald`: dual-platform (Rocky Linux 9 + Ubuntu 22.04), full converge/verify/idempotency
- **CI matrix** expanded from 29 → 31 Molecule scenarios

### Fixed

- **BUG** `linux_fail2ban_rhel9` was present in `roles/` since v1.7.0 but was **never added** to `playbooks/2_configure_hardening.yml` under the RedHat block, silently skipped on all RHEL9 runs. Role is now correctly included in the playbook.

### Changed

- `galaxy.yml`: version → 1.9.0; description updated to 51 roles (25 RHEL9 + 26 Ubuntu/Debian); tags: added `ipv6`, `journald`
- `playbooks/2_configure_hardening.yml`: added `linux_ipv6_*` (tag: `network, ipv6`) after ip_forwarding; added `linux_journald_*` (tag: `audit, logging, journald`) after auditing

## [1.8.0]: 2026-03-11

### Added

- **29 Molecule test scenarios**: full integration test coverage for all 47 roles across RHEL 9 (Rocky Linux 9) and Ubuntu 22.04 Docker containers; all 29 scenarios run in CI on every PR targeting `automation/ansible-hardening/`
- **`ansible-lint` CI job**: `.github/workflows/molecule.yml` now gates every PR with `ansible-lint roles/ playbooks/` (profile: `basic`) before running Molecule; enforces collection-wide code quality
- **`.ansible-lint` configuration**: `automation/ansible-hardening/.ansible-lint`: `profile: basic`, `var-naming[no-role-prefix]` explicitly skipped (shared variable names intentionally unprefixed so one `group_vars` entry controls both OS variants), `molecule/` excluded

### Fixed

- **BUG** `linux_bootloader_password_rhel9` / `ubuntu`: `grub2-mkpasswd-pbkdf2` received the password only once via stdin; the command requires it twice (password + confirmation). Fixed: `stdin: "{{ linux_bootloader_password }}\n{{ linux_bootloader_password }}\n"`
- **BUG** `linux_bootloader_password_rhel9` / `ubuntu`: `regex_search` pattern did not match the actual command output format. Fixed: `regex_search('grub\\.pbkdf2\\.sha512\\.\\S+')`
- **BUG** `linux_bootloader_password_rhel9`: handler `Rebuild GRUB config` was defined as a `block`: Ansible does not support blocks in handlers. Removed the invalid block; GRUB rebuild is handled inline by the existing `grub2-mkconfig` tasks
- **BUG** `linux_bootloader_password_ubuntu` / `linux_secure_boot_ubuntu`: `update-grub` fails in Docker containers (overlay filesystem). Added `failed_when: false` to the handler and to the `/boot` chmod task
- **BUG** `linux_crypto_policies_rhel9`: sshd reload loop lacked `failed_when: false`; fails in containers where sshd is not running. Fixed
- **BUG** `linux_core_dumps_ubuntu`: `systemctl daemon-reload` called via `ansible.builtin.command` (command-instead-of-module). Replaced with `ansible.builtin.systemd: daemon_reload: true`
- **BUG** `linux_tmp_mounts_ubuntu`: handler used `command: systemctl restart tmp.mount`; replaced with `ansible.builtin.systemd: name: tmp.mount / state: restarted / daemon_reload: true`
- **BUG** `playbooks/1_execute_baseline_before.yml` / `3_execute_baseline_after.yml`: fetch tasks used `ignore_errors: true`. Replaced with `failed_when: false`

### Changed

- `galaxy.yml`: version → 1.8.0
- YAML formatting standardised across all 47 role files (`yaml[new-line-at-end-of-file]`, `yaml[line-length]` violations resolved; 668 lint findings reduced to 0)

---

## [1.7.1]: 2026-03-09

### Fixed

- **BUG** `cyberaar-baseline.sh`: `get_ssh()` helper used `tail -1`: SSH uses first-match-wins so the last occurrence of a directive was returned, producing incorrect results across all 15 SSH checks. Fixed to `head -1`
- **BUG** `cyberaar-baseline.sh`: NET-12 wireless check only recognised `Soft blocked: yes` from rfkill; systems with a hardware kill switch (`Hard blocked: yes`) incorrectly reported WARN. Both states now accepted
- **BUG** `cyberaar-baseline.sh`: remote script path unquoted in SSH exec and cleanup commands in `lib/remote.sh`: defensive quoting added
- **BUG** `linux_apparmor_ubuntu`: "Set specific profiles to enforce mode" task used `changed_when: true`, reporting changed on every run even when profiles were already enforced. Now checks `aa-enforce` stdout for `Setting` to report changed only when a profile is actually transitioned
- **DOCS** `role-linux_authselect_rhel9`: added missing pwquality keys (`maxrepeat`, `maxclassrepeat`, `dictcheck`) and faillock keys (`even_deny_root`, `root_unlock_time`) to Variables tables
- **DOCS** `role-linux_bootloader_password_rhel9`: added missing `linux_single_user_auth` variable (CIS 1.4.3)
- **DOCS** `role-linux_tmp_mounts_rhel9`: added missing `linux_tmp_mounts_enabled`, `linux_home_nodev_enabled` (CIS 1.1.14), `linux_sticky_bit_enabled` (CIS 1.1.21)
- **DOCS** `role-linux_user_management_rhel9`: added 7 missing CIS 6.2.x audit variables and extended CIS Coverage section

---

## [1.7.0]: 2026-03-09

### Added

- **`linux_sudo_hardening_rhel9`**: new role: installs sudo, deploys `/etc/sudoers.d/99-cis-hardening` drop-in with `Defaults use_pty` and `Defaults logfile=` (CIS 1.3.2–1.3.3), validates with `visudo -cf`
- **`linux_cron_hardening_rhel9`**: new role: hardens cron/at directory permissions (CIS 5.1.2–5.1.7), enforces `cron.allow`/`at.allow` allow-list model (CIS 5.1.8–5.1.9), enables `crond` service (CIS 5.1.1)
- **`linux_wireless_rhel9`**: new role: disables wireless via `nmcli radio all off` (with check-mode guard), blacklists Wi-Fi kernel modules in `/etc/modprobe.d/99-cis-wireless.conf` (CIS 3.1.2)
- **`linux_sudo_hardening_ubuntu`**: Ubuntu counterpart of `linux_sudo_hardening_rhel9`: same CIS controls via `/etc/sudoers.d/99-cis-hardening` drop-in with `visudo` validation
- **`linux_cron_hardening_ubuntu`**: Ubuntu counterpart: uses `cron` service name; `cron.allow` group=`crontab` mode=`0640`; `at.allow` group=`daemon` mode=`0640` per Ubuntu package defaults
- **`linux_wireless_ubuntu`**: Ubuntu counterpart: `rfkill block wifi` as primary mechanism (no NetworkManager required), `nmcli` fallback if present, kernel module blacklist with `update-initramfs -u -k all` for persistence (CIS 3.1.2)
- **`cyberaar-baseline.sh` v4.1.0**: 5 new security checks (88 → 93 total)
  - `AUTH-15`: sudo `use_pty` enforcement (CIS 1.3.2)
  - `AUTH-16`: sudo logfile configuration (CIS 1.3.3)
  - `NET-12`: wireless interfaces disabled (rfkill + nmcli + modprobe blacklist)
  - `COMP-11`: cron service enabled and running (CIS 5.1.1)
  - `COMP-12`: `cron.allow` and `at.allow` allow-list model enforced (CIS 5.1.8–5.1.9)
- **Role documentation**: `docs/role-linux_sudo_hardening_ubuntu.md`, `docs/role-linux_cron_hardening_ubuntu.md`, `docs/role-linux_wireless_ubuntu.md`

### Changed

- `galaxy.yml`: version → 1.7.0; description updated to "47 roles (23 RHEL9, 24 Ubuntu/Debian)"; tags `sudo`, `cron`, `wireless` added
- `playbooks/2_configure_hardening.yml`: `linux_wireless_ubuntu`, `linux_sudo_hardening_ubuntu`, `linux_cron_hardening_ubuntu` added with tags `network,wireless` / `auth,sudo` / `cron`
- `src/lib/ansible_map.sh`: remediation mappings added for AUTH-15, AUTH-16, NET-12, COMP-11, COMP-12

---

## [1.6.1]: 2026-03-09

### Fixed

- **SECURITY** `cyberaar-baseline.sh`: remote temp filenames now use `openssl rand -hex 8` instead of predictable `$$` PID, eliminating symlink/race attack surface on remote hosts
- **SECURITY** `cyberaar-baseline.sh`: `chmod 600` applied to JSON and HTML output files after creation, reports contain full audit data and must not be world-readable
- **BUG** `cyberaar-baseline.sh`: `grep -c ... || echo 0` pattern produced `"0\n0"` (double-zero) when grep matched nothing, causing `[[ -eq ]]` syntax error on INT-03, LOG-04, COMP-03, COMP-04 checks, replaced with `|| true` + `${VAR:-0}` guard

### Changed

- Removed region-specific branding from script output (🇸🇳 flag emoji, French Senegal tagline); project scope is now worldwide, Senegal origin context preserved in README only
- Fixed stale version badge `v2.0.0` → `v4.0.0` in HTML report header and footer

---

## [1.6.0]: 2026-03-07

### Added

- **French translation of Linux hardening guide**: `translations/02-durcissement-serveur-linux.md`, full French version of the basic server hardening practice guide, adapted for Francophone West African public-sector context (Senegal DAF attack reference, UFW/firewalld/nftables, AppArmor/SELinux, LUKS)
- **`translations/README.md`**: guide index table and contribution instructions for French translations

### Changed

- **`cyberaar-baseline.sh` v4.0.0, `src/` multi-file architecture**: script split into `automation/scripts/src/` (14 source files across `lib/`, `checks/`, `renderers/`) assembled by `build.sh`; `add_result()` decoupled from JSON/HTML renderers via parallel result arrays (`RESULT_CATEGORY[]`, `RESULT_STATUS[]`, `RESULT_ID[]`, etc.)
- **JSON report version fixed**: baseline JSON output now correctly reports `"version": "4.0.0"` (was carrying forward `"3.0.0"`)
- **`automation/scripts/README.md`**: added "Contributing to the Script" section with `src/` layout diagram, `add_result()` architecture explanation, and edit → rebuild → test workflow
- **Root `README.md`**: collection version updated to v1.5.0, repo tree updated to show `build.sh` and `src/` subtree
- **`.gitignore`**: `CLAUDE.md` excluded from version control (local Claude Code instructions)

---

## [1.5.0]: 2026-03-06

### Added

- **Comprehensive RHEL9 role documentation**: all 21 RHEL9 role docs completely rewritten to match the Ubuntu doc format: Supported Platforms section, granular CIS benchmark references with section IDs, full variable tables with backtick-formatted names and accurate defaults, `group_vars`-style usage examples, and a "Differences from Ubuntu Counterpart" table for every role

### Changed

- `galaxy.yml`: version bumped to 1.5.0; description extended to cover Ubuntu/Debian alongside RHEL9; added tags `ubuntu`, `debian`, `apparmor`, `ufw`; fixed `documentation` URL to point to `docs/` directory
- `docs/role-linux_selinux_rhel9.md`: updated with `linux_selinux_relabel_enabled` variable, performance note, and default boolean table

---

## [1.4.0]: 2026-03-06

### Added

- **README rewrite**: full pipeline documentation: three-step baseline → harden → baseline diagram, all 42 roles in dual-OS table with CIS refs, full tag reference, inventory structure, variable precedence, sensitive variable lifecycle, report output structure
- **Ubuntu/Debian role documentation**: 21 new docs in `docs/` covering every Ubuntu role with Purpose, Supported Platforms, CIS Coverage, Variables, Usage Example, and Differences sections
- `docs/index.md` and `docs/roles-overview.md` updated for dual-OS scope

### Fixed

- **HIGH** `linux_auditing_rhel9`: YAML syntax error in `line:` value (single quotes inside single-quoted string); removed `ansible_default_ipv4.gateway` injected into `GRUB_CMDLINE_LINUX` (copy-paste artifact)
- **HIGH** `linux_auditing_rhel9`: `grub_audit_result.changed` referenced without `| default(false)`: UndefinedError when `linux_auditd_enable_boot_auditing` is false
- **HIGH** `linux_ctrl_alt_del_ubuntu`: replaced `ansible.builtin.command: "systemctl mask ..."` with `ansible.builtin.systemd: masked: true`: now idempotent and check-mode aware
- **HIGH** `linux_disable_unnecessary_services_ubuntu`: replaced `systemctl mask {{ item }}` command with `ansible.builtin.systemd: masked: true` loop
- **MEDIUM** `linux_login_banner_ubuntu`: replaced `find ... chmod a-x` command task with `ansible.builtin.file: mode: "a-x"` loop, idempotent, no more always-changed
- **MEDIUM** `linux_user_management_ubuntu`: replaced `useradd -D -f` command with `ansible.builtin.lineinfile` on `/etc/default/useradd`: idempotent
- **MEDIUM** `linux_core_dumps_ubuntu`: moved `Ensure coredump.conf.d directory exists` task before the template task, fixed ordering error that caused first-run failures
- **MEDIUM** `linux_user_management_rhel9`: narrowed empty-password lock condition from `'!'` to `'!!'`; fixed awk check; removed `remember =` from `pwquality.conf` (wrong file)
- **MEDIUM** `linux_aide_ubuntu`: fixed operator precedence `not aide_init.changed | default(false)` → `not (aide_init.changed | default(false))`
- **LOW** `linux_chrony_rhel9`: added `when: not ansible_check_mode` to `chronyc tracking` task
- **LOW** `linux_auditing_ubuntu`: removed spurious `ansible.builtin.meta: flush_handlers` task
- **LOW** `linux_crypto_policies_rhel9`: removed dead `Normalize subpolicies to dict list` task with broken Jinja2

### Changed

- `run-hardening.sh` moved to `automation/scripts/` directory
- WSL detection improved across multiple roles
- Inventory structure refactored for clearer group separation

---

## [1.3.0]: 2026-03-05

### Added

- **Unified three-step pipeline** (`0_execute_full_pipeline.yml`), single entry point that orchestrates baseline audit → hardening → post-hardening audit with automatic OS detection (`ansible_os_family`)
- **`cyberaar-baseline.sh` v3.0.0**: standalone bash audit script producing HTML and JSON security reports; integrated as steps 1 and 3 of the pipeline
- **Before/after baseline playbooks**: `1_execute_baseline_before.yml` and `3_execute_baseline_after.yml` copy the script to remote hosts, run it, and fetch HTML/JSON reports to `reports/before/<hostname>/` and `reports/after/<hostname>/`

### Fixed

- **HIGH** Multiple Ansible bugs resolved across existing RHEL9 roles (9 issues: undefined variable guards, check-mode guards, handler ordering, idempotency)
- **HIGH** WSL compatibility fixes, GRUB tasks guarded with WSL detection across `linux_auditing_ubuntu`, `linux_apparmor_ubuntu`, `linux_secure_boot_ubuntu`
- **MEDIUM** Inventory refactored, `ansible_host` derivation moved to `group_vars`; `index` variable aligned across all groups

---

## [1.2.0]: 2026-03-03

### Added

- **21 Ubuntu/Debian hardening roles**: complete CIS-aligned hardening library
  for Debian-family systems, mirroring the RHEL9 role structure:
  - `linux_ssh_hardening_ubuntu`: SSH server hardening (Protocol 2, key auth, CIS ciphers)
  - `linux_kernel_hardening_ubuntu`: sysctl hardening + module blacklisting
  - `linux_auditing_ubuntu`: auditd + 14-category audit rules + rsyslog forwarding
  - `linux_aide_ubuntu`: AIDE file integrity with template-based config
  - `linux_bootloader_password_ubuntu`: GRUB PBKDF2 password protection
  - `linux_firewall_ubuntu`: UFW hardening (replaces firewalld)
  - `linux_apparmor_ubuntu`: AppArmor enforce-all (replaces SELinux)
  - `linux_authselect_ubuntu`: PAM/pwquality/faillock hardening (replaces authselect)
  - `linux_unattended_upgrades_ubuntu`: Automatic security updates (replaces dnf-automatic)
  - `linux_chrony_ubuntu`: NTP hardening, disables systemd-timesyncd
  - `linux_login_banner_ubuntu`: Login banners, disables Ubuntu dynamic MOTD
  - `linux_crypto_policies_ubuntu`: OpenSSL + GnuTLS TLS hardening
  - `linux_disable_unnecessary_services_ubuntu`: Stop/mask 20+ unnecessary services
  - `linux_user_management_ubuntu`: System accounts, umask, inactive policy
  - `linux_fail2ban_ubuntu`: fail2ban with systemd backend
  - `linux_ip_forwarding_ubuntu`: IP forwarding sysctl with validation
  - `linux_ctrl_alt_del_ubuntu`: Mask ctrl-alt-del.target
  - `linux_core_dumps_ubuntu`: Core dump restriction (limits.d + sysctl + systemd)
  - `linux_tmp_mounts_ubuntu`: /tmp and /dev/shm mount hardening
  - `linux_secure_boot_ubuntu`: Secure Boot check + /boot permissions
  - `linux_file_permissions_ubuntu`: Critical file and directory permissions

### Fixed

- **HIGH** `linux_kernel_hardening_rhel9`: sysctl and modprobe template files
  moved from role root to `templates/` directory, fixes "template not found" on all runs
- **HIGH** `linux_auditing_rhel9`: `99-cis-audit.rules.j2` was empty, deployed
  a blank ruleset on every run, wiping all audit configuration
- **HIGH** `linux_auditing_rhel9`: GRUB cmdline `lineinfile` used
  `ansible_default_ipv4.gateway` instead of backreference, corrupting kernel params
- **MEDIUM** `linux_auditing_rhel9`: removed `audispd-plugins` package (merged
  into `audit` on RHEL9, caused dnf failure)

---

## [1.1.0]: 2026-03-01

### Added

- 10 new hardening roles for RHEL 9 family servers:
  - `linux_aide_rhel9`: File integrity monitoring (AIDE)
  - `linux_chrony_rhel9`: Secure NTP with Chrony
  - `linux_ssh_hardening_rhel9`: Deep SSH server hardening
  - `linux_tmp_mounts_rhel9`: noexec/nodev/nosuid on temp dirs
  - `linux_dnf_automatic_rhel9`: Automatic security updates
  - `linux_core_dumps_rhel9`: Restrict core dumps
  - `linux_ip_forwarding_rhel9`: Disable IP forwarding & redirects
  - `linux_login_banner_rhel9`: SSH & console banners (CyberAar branding)
  - `linux_ctrl_alt_del_rhel9`: Disable Ctrl+Alt+Del reboot
  - `linux_secure_boot_rhel9`: Enforce Secure Boot verification

- Per-role detailed documentation in `docs/` (purpose, CIS refs, vars, usage, testing, notes)
- Consistent formatting across all roles (double quotes, `when:` after `name:`, `---`/`...`)
- Updated root README with new structure, roles table, and quick-start
- LICENSE aligned to GPL-3.0 everywhere

### Changed

- Minor refinements in existing roles (banner templates with CyberAar branding in English)

### Security

- Enhanced protections: Secure Boot enforcement, core dump restrictions, IP forwarding disable

---

## [1.0.0]: 2026-02-26

### Added

- Initial release of CyberAar hardening collection for RHEL 9 family
- Main playbook: `configure_hardening_rhel9.yml`
- 11 RHEL9 hardening roles:
  - `linux_crypto_policies_rhel9`
  - `linux_authselect_rhel9`
  - `linux_kernel_hardening_rhel9` (sysctl + module blacklist)
  - `linux_auditing_rhel9` (with rsyslog forwarding)
  - `linux_firewalld_rhel9` (using `ansible.posix.firewalld`)
  - `linux_fail2ban_rhel9`
  - `linux_disable_unnecessary_services_rhel9`
  - `linux_file_permissions_rhel9`
  - `linux_selinux_rhel9` (using `ansible.posix.selinux`)
  - `linux_bootloader_password_rhel9` (secure password via env/vault)
  - `linux_user_management_rhel9`

### Security

- GRUB password uses PBKDF2 hash + environment variable / vault
- No hardcoded secrets in defaults
- `no_log` protection on sensitive tasks

### Notes

- Focused on CIS Red Hat Enterprise Linux 9 Benchmark v2.0.0
- Designed for critical infrastructure servers (Senegal government context)
- Idempotent roles with granular enable/disable variables
