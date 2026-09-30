# Design: `aartool undo`

Status: **proposal, not approved, no code written.** Written because the
question "can I put it back" is the first one an operator asks about a tool
that edits `sshd_config`, and today the honest answer is "restore from your
own backup".

## What it is

`apply` snapshots every file it is about to change, before changing it. `undo`
puts them back.

```
aartool apply --target web-01 --user ubuntu --only ssh
aartool undo  --target web-01 --user ubuntu --last
```

## What is snapshotted

Three kinds of state, and they are not equally recoverable. That asymmetry is
the whole design.

| Kind | Example | Snapshot | Restore |
|---|---|---|---|
| Edited files | `/etc/ssh/sshd_config`, `/etc/login.defs`, `/etc/audit/rules.d/*` | copy plus mode, owner, SELinux context | write back, then restart the unit that owns it |
| Dropped-in files | `/etc/sysctl.d/99-aartool.conf`, `/etc/audit/plugins.d/*` | record that the path did not exist | delete it, then reload |
| Unit state | a service enabled, masked or stopped | `systemctl is-enabled` / `is-active` before the change | set it back |

The set comes from the roles themselves, not from a hand-kept list. Ansible
already reports every file it touched in its own output, and each role declares
its files in `defaults/main.yml`. **A hand-maintained list of "files aartool
changes" would drift the moment a role gains a task**, and a snapshot that
misses a file is worse than no snapshot: the operator believes they can go
back.

Proposed mechanism: run `apply` with a callback plugin that records every
`file`, `template`, `lineinfile`, `copy` and `systemd` task result, and take
the snapshot from that. It is derived from what actually ran, which is the same
argument that put `wave` in the JSON rather than letting consumers reimplement
it.

## Where snapshots live

`/var/lib/aartool/undo/<timestamp>/` on the **target**, not the controller.

- On the target, because a restore must work when the controller is gone or
  the network is down, which is one of the situations that makes someone want
  to undo.
- Not `/tmp`: cleared on reboot, and a reboot is exactly what a bad sysctl
  change makes you do.
- Owned `root:root`, mode `0700`. A snapshot of `/etc/shadow`-adjacent files
  with loose permissions is a new vulnerability introduced by a safety feature.

**Surviving a package upgrade:** nothing under `/var/lib` is touched by a
package upgrade of aartool, because aartool is not installed as a package on
the target at all; it is copied there for the run. The real risk is the
opposite one: a snapshot taken by 3.6.0 being restored by 4.0.0 after the
format changed. So each snapshot carries a `manifest.json` with a
`format_version`, and `undo` refuses a format it does not know rather than
guessing. It prints where the files are so a human can do it by hand.

## What cannot be undone

This list is the point of the design, and it belongs in `--help`, not only
here. A tool that says "undo" and silently does three quarters of it is worse
than one that does not offer it.

- **Package installs.** `aide`, `auditd`, `fail2ban`, `chrony`. Removing them
  could break something installed for another reason, and a package that was
  already present must not be removed at all. `undo` reports what was installed
  and leaves it.
- **Deleted or locked accounts**, and password ageing already applied to
  existing users. `chage` rewrites shadow fields with no record of the previous
  value unless it was captured first; capturing it means snapshotting
  `/etc/shadow`, which is a decision to take deliberately and not by accident.
- **Anything a restarted service did in between.** Restarting `sshd` drops
  sessions; restarting `auditd` loses the events in its buffer.
- **Firewall rules already in the running kernel** where the role wrote them
  live rather than to a file.
- **A bootloader password**, which is hashed into the grub config by a tool that
  does not take it back out.

## Interaction with `--target` and the typed confirmation

`undo` is a writing command, so it takes the same road as `apply`: `--target`
is required, and the operator types the target name back. The reason is
stronger here, not weaker. An `undo` aimed at the wrong target does not
"restore" anything; it **applies one host's old configuration to another
host**, which is a worse outcome than the mistaken `apply` the confirmation
was built for.

`undo --last` is the common case. `undo --snapshot <timestamp>` for a specific
one. `undo --list` prints what exists, and changes nothing.

## Proving it works

The loop, on a throwaway host, and it has to be a real one:

```
aartool doctor  --target t --user u
sudo aartool inspect --host t --user u -o ./before
aartool plan    --target t --user u --only ssh
aartool apply   --target t --user u --only ssh
sudo aartool inspect --host t --user u -o ./after
aartool diff ./before/*.json ./after/*.json     # must show the change
aartool undo    --target t --user u --last
sudo aartool inspect --host t --user u -o ./restored
aartool diff ./before/*.json ./restored/*.json  # must show NOTHING
```

That last `diff` is the assertion, and it is the reason `diff` already exits
non-zero on a regression: the test already exists, `undo` just has to satisfy
it.

**It is not enough.** `diff` compares check results, and two different
configurations can produce the same results. A file restored with the right
content but the wrong mode, or a service left disabled that was enabled, can
pass. So the proof also needs a byte-level comparison of every file in the
manifest, and `systemctl is-enabled` for every unit touched, both taken before
and after. `scripts/tests/proof-remote.sh` already stands up a bastion and a
private target with Docker and is where this belongs.

## Risks, stated plainly

1. **A partial snapshot is the dangerous failure.** If the callback misses a
   task, `undo` reports success having restored most of a config. Mitigation:
   the manifest records a checksum of every file both before and after the
   apply; `undo` verifies the after-checksum still matches before restoring,
   and refuses the whole snapshot if any file changed underneath it. Refusing
   is correct: something else edited that file, and overwriting it would
   destroy a third party's change.
2. **Undo is itself a change**, so it needs its own snapshot, or an operator
   cannot undo an undo. Snapshot before restoring.
3. **Disk.** A snapshot of `/etc` files is small, but an unbounded directory of
   them is not. Keep the last N, default 5, prune oldest, and say so in the
   output.
4. **It invites carelessness.** "I can always undo" is how a change gets
   applied to production without a plan. The counterweight already exists and
   should not be softened: `plan` stays a separate command, and the typed
   target confirmation stays.
5. **It is a new root-owned data store on every audited host.** That is a real
   increase in what aartool leaves behind on a machine, and it should be
   opt-in: `apply --snapshot` rather than snapshotting by default, until it has
   been run on enough real hosts to be trusted.

## What I would build first

Not the full design. `apply --snapshot` writing the manifest and the copies,
plus `undo --list`, and nothing that restores. That puts the hard half, deriving
the complete file set from what actually ran, in front of real hosts while the
only risk is wasted disk. Restoring comes after the manifests have been correct
on real machines for a while.
