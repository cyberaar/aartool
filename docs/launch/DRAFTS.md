# Launch drafts

**Nothing here has been posted or submitted. Posting is the owner's call.**

Written after 3.6.0, when `paths` made the pitch different from every other
hardening tool: not a longer list, a shorter one that says which findings
actually chain.

## 1. Show HN

**Title**

    Show HN: Aartool - which attack chains are complete on your Linux host

Second choice, if the first reads as marketing:

    Show HN: I stopped ranking security findings and started ranking attack chains

**First comment**

> I maintain a small fleet and I kept bouncing off my own audit output. 109
> findings, sorted by severity, and no way to answer the only question that
> mattered: if someone is on the network right now, what can they actually do?
>
> Severity does not answer it. A "medium" that is the only thing between an
> attacker and root matters more than three criticals that need physical
> access. So aartool reads its own audit and shows which chains are complete
> end to end on that host: a way in, a way up, a way to stay, a way to not be
> seen. Each link alone is a medium. Together they are the incident.
>
> The output names the cheapest safe link to cut in each chain, because
> breaking one link per chain is enough, and that is a much shorter list than
> "fix 109 things".
>
> It is bash and Ansible, no agent, no account, no telemetry. Audit changes
> nothing; applying is a separate command and asks you to type the target name
> back, because the dangerous mistake is the wrong target, not the wrong
> intent. Reports open offline with no remote subresources: an audit report is
> a list of a machine's weaknesses and it should not phone anyone.
>
> Honest limits. The audit reads sysctls, /proc, /etc and systemd so it runs
> almost anywhere, but the hardening roles cover the RHEL and Debian families
> and CI only proves Rocky 9 and Ubuntu 22.04. The chain definitions are a
> judgement call and I would genuinely like them argued with: they live in one
> function and a test asserts every check ID in them is real, because a typo
> silently closes a stage and makes a host look safer than it is. That bug
> existed until last week.
>
> Written while hardening a 15-node estate. Every default in it is one I run.

## 2. Launch post outline

**Angle: I stopped ranking findings and started ranking attack chains.**

1. **The wall.** 109 checks per host, and on a 15-node estate that is over
   1,600 rows of arithmetic before anyone reads one. Sorted by severity, which
   sorts by how bad a finding is in the abstract, not by what it gets you here.
   Verified single-host figure, measured on 2026-09-30: **66 findings open on
   one machine**, score 66/100.
2. **The question severity cannot answer.** On this host, tonight, what is
   reachable? A critical needing local console access is not the thing to fix
   before a medium that is the last hop to root.
3. **What changed.** Model the attacker's walk, not the finding list. Four
   chains: the front door, the local climb, the silent tenant, the pivot. A
   stage is open when any of its findings is open; a chain is complete when
   every stage is. Complete chains first, and then only the cheapest link in
   each.
4. **The number that matters.** Measured on one real host on 2026-09-30, not
   on the bundled sample: **66 open findings, 3 of 4 chains complete, 3 links
   to cut.** `paths` named SSH-03 (MaxAuthTries not restricted), KRN-06 (kexec
   allowed) and SSH-04 (TCP forwarding enabled). The fourth chain, the local
   climb, was already broken because AppArmor is enforcing, which is the point:
   one control that was already right closed a whole chain.
   The estate-wide before and after still needs a fresh 15-node run before it
   goes in a post. Do not publish an estate number that has not been measured
   this month.
5. **What it cost to get right.** The first version of the chains claimed a
   host was internet-to-root when the only escalation check on it passed: two
   password-guessing findings were sitting in the escalation stage, where
   neither can do anything. A false complete is not a harmless over-warning,
   it is the exit code a CI gate fails on. Include this. A launch post that
   admits the tool was wrong about its own headline feature is more credible
   than one that does not.
6. **Where it fits.** Not a replacement for Lynis or OpenSCAP. See the
   comparison below.
7. **Ask.** Argue with the chain definitions.

## 3. Comparison with Lynis and OpenSCAP

**Lynis: run on 2026-09-30. OpenSCAP: still not run, and nothing below claims
otherwise.**

Same host, same day, same machine state: Ubuntu 24.04, kernel 6.18 (WSL2).

| | aartool 3.6.0 | Lynis 3.0.9 |
|---|---|---|
| Score on that host | 66/100 | hardening index 67 |
| Tests run | 109 | 249 |
| Wall clock | about 90 seconds | 34 seconds |
| Raised | 9 fail, 57 warn | 2 warnings, 40 suggestions |
| What to do next | 3 links to cut, named | 40 suggestions, unordered |

**Two independent tools scoring the same machine 66 and 67 is worth saying out
loud.** It is a reasonable check that neither is inventing its number, and it
is not a point in favour of either one.

**Where Lynis wins, concretely and on this run.** It ran 249 tests to aartool's
109 and covers whole areas aartool does not look at: mail transport, databases,
PHP, LDAP, printing, SNMP, container runtimes, malware scanners. It found
`NETW-2705`, a DNS resolver problem aartool has no check for at all. It is
faster. It has a decade of field use behind its findings. Anyone who wants the
widest possible sweep of a single host should run Lynis, and aartool does not
change that.

**Where aartool is different.** Lynis produced 40 suggestions in the order its
test suite happens to run them. aartool produced 66 open findings and then said
which three to close, because it models the chains those findings sit in rather
than the findings alone. And every one of those three maps to an Ansible role
that will apply it, with a dry run first. Lynis deliberately does not remediate.

**OpenSCAP.** Not installed, not run, so there is no honest column for it here.
What can be said without running it: it produces formal SCAP profile evidence
that auditors accept, and aartool does not. Before publishing any OpenSCAP
claim, run it on the same host the same way.

**Be specific about losing.** Lynis finds things aartool does not, on this run,
by name. OpenSCAP produces evidence aartool cannot. Saying so is what makes the
rest credible.

## 4. Awesome-list submissions

Each needs the repo to have a stable release and a README that opens with the
demo. Both true as of 3.6.0.

| List | Section | Entry |
|---|---|---|
| `awesome-linux-hardening` | Tools / Auditing | audit with attack-chain analysis, plus matching Ansible roles |
| `awesome-sysadmin` | Security | lead with "audit, plan, apply, prove", not with the chains |
| `awesome-ansible` | Roles and collections | the `cyberaar.hardening` collection, 52 roles, not the CLI |
| `awesome-security` | Endpoint / Host | the SARIF output is the hook here, since the audience is tooling integrators |

One PR at a time, not four at once. Several of these lists reject entries that
arrive in a batch from a new account, and a rejection on the first one is worth
learning from before spending the other three.

## 5. Reddit variants

Both are drafts. Neither has been posted. Both subreddits remove posts that
read as marketing, so each leads with the problem and names the limits before
the link.

**r/linuxadmin**

> Title: I stopped sorting hardening findings by severity and started sorting
> them by whether they chain
>
> I run a small fleet and my own audit output had become wallpaper. 109 checks
> per host, sorted by severity, and it never answered the question I actually
> had: if someone is on the network tonight, what can they reach?
>
> Severity cannot answer that. A critical needing console access is not more
> urgent than a medium that happens to be the last hop to root.
>
> So the tool now reads its own audit and reports which attack chains are
> complete end to end on that host: a way in, a way up, a way to stay, a way to
> not be seen. On my workstation this morning: 66 findings open, 3 of 4 chains
> complete, and 3 links to cut. Not 66 things. 3.
>
> Bash and Ansible, no agent, no account, no telemetry. The audit changes
> nothing and does not need to be installed to try: there is a bundled sample.
>
> Limits, up front: 109 checks against Lynis's 249, and I ran both on the same
> box today. Lynis found a DNS problem I do not check for at all. The hardening
> roles cover RHEL 9 and Debian/Ubuntu, and CI only proves Rocky 9 and Ubuntu
> 22.04.
>
> I would most like the chain definitions argued with. They are a judgement
> call, they live in one function, and getting them wrong makes a host look
> safer than it is.

**r/devops**

> Title: Making a hardening audit fail CI on the thing that actually matters
>
> Hardening scanners give you a score and a list. Neither is a gate: a score
> goes up and down for reasons nobody wants to argue about in a pull request,
> and a list has no threshold that is not arbitrary.
>
> What I wanted was a gate with a meaning: fail while a complete attack chain
> exists on this host. So `aartool paths` exits 1 while any chain is complete
> and 0 when none is, and 2 when it could not read the report, which matters
> more than it sounds: exit 1 used to mean both "a chain is complete" and "I
> could not parse this", so a gate configured not to fail on chains was also
> passing reports the tool had failed to read.
>
> There is a composite GitHub Action, SARIF output for the code scanning tab,
> and Prometheus text output for node_exporter's textfile collector.
>
> Limits: two distros proven in CI, and the chain model is mine and arguable.

## 6. Five post thread

Drafted, not posted. Each post stands alone; the thread does not require the
previous one to make sense.

1. A hardening audit gave me 109 findings on one machine, 66 of them open.
   Sorted by severity. Severity ranks how bad a finding is in the abstract. It
   cannot tell you what an attacker on your network tonight can actually
   reach. Those are different questions and only one of them is urgent.

2. An attacker does not exploit a list. They walk a chain: a way in, a way up,
   a way to stay, a way to not be seen. Each link on its own is a "medium".
   Together they are the incident. So the tool now reports chains, not just
   findings.

3. On my own workstation this morning: 66 findings open, 3 of 4 chains
   complete. The tool named 3 links to cut. Breaking one link breaks a chain,
   so the work is 3 changes, not 66. The fourth chain was already broken
   because AppArmor is enforcing.

4. The version before this one was wrong about its own headline feature. Two
   password-guessing findings were sitting in the privilege-escalation stage,
   where neither can do anything, so a host with every escalation check passing
   still reported internet-to-root. A false complete is not a harmless
   over-warning: it is the exit code a CI gate fails on.

5. It is bash and Ansible. No agent, no account, no telemetry. The audit
   changes nothing, applying is a separate command, and reports open offline
   with no remote subresources, because an audit report is a list of a
   machine's weaknesses and it should not phone anyone. Argue with the chain
   definitions.
