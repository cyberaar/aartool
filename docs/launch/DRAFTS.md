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

1. **The wall.** A 15-node estate, 109 checks each. Roughly 1,600 findings.
   Sorted by severity, which sorts by how bad the finding is in the abstract,
   not by what it gets you here.
2. **The question severity cannot answer.** On this host, tonight, what is
   reachable? A critical needing local console access is not the thing to fix
   before a medium that is the last hop to root.
3. **What changed.** Model the attacker's walk, not the finding list. Four
   chains: the front door, the local climb, the silent tenant, the pivot. A
   stage is open when any of its findings is open; a chain is complete when
   every stage is. Complete chains first, and then only the cheapest link in
   each.
4. **The number that matters.** "Fix 109 things" became "cut four links". Show
   the real before and after from the estate.
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

**Not yet run. Do not publish this section until it has been.**

Neither tool is installed on the build machine, so any comparison written now
would be from documentation, and a comparison written from documentation is
the kind of claim that gets a launch post correctly torn apart.

What the comparison has to be: all three run on the **same host**, same day,
output kept. For each, record what it found that the others did not, how long
it took, and what it made the operator do next.

Expected shape, to be confirmed or corrected by the run:

| | aartool | Lynis | OpenSCAP |
|---|---|---|---|
| Where it wins | chains, ordered remediation, matching Ansible roles | breadth, maturity, plugins, years of field use | formal SCAP profiles, compliance evidence auditors accept |
| Where it loses | far younger, narrower check set, two distros proven in CI | no remediation, no machine-readable chain model | heavyweight, profile-bound, hard to read output |

**Be specific about losing.** Lynis has a decade of hardening knowledge and
finds things aartool does not. OpenSCAP produces evidence an auditor will
accept and aartool does not. Saying so is what makes the win credible.

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
