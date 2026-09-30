# Growth notes: why someone would star this, and how they find it

Written after a full read of the repository. Opinionated on purpose.

## What is already unusual (say it louder)

1. **`explain` states what closing a finding breaks**, and "not on this machine"
   is a supported answer. No other hardening tool argues both sides.
2. **The loop**: audit, ordered plan, apply, `diff` proving only what you
   intended moved. Lynis and OpenSCAP stop at step 1.
3. **Zero-dependency audit** that runs on an air-gapped box (`curl` one file).
4. **Real-estate evidence** in the README: bugs found on 15 live nodes.

## Shipped in this change

- `aartool demo`: the front door. Thirty seconds, no root, no install of
  anything else. A star is decided in the first minute; before this, the first
  minute needed a Linux box and `sudo`.
- `aartool paths`: findings as **attack chains**, with the one link to cut.
  This is the "first time I have seen this" feature: it reframes an audit from
  "you have 57 warnings" to "here are the 3 chains an attacker completes, cut
  one link each".
- `aartool badge`: a self-contained SVG for READMEs. Every repo that shows it is
  an ad, and it needs no third-party service.

## Next, in order of expected return

1. **Terminal recording at the top of the README.** An asciinema/`vhs` loop of
   `demo`. Highest single lever; the tool is visual and the README is text.
2. **`--format sarif`** so findings appear in GitHub code scanning, and a
   ready-made GitHub Action (`uses: cyberaar/aartool-action`) that runs
   `inspect` on a runner and gates on `paths`. Puts the tool in the CI pages
   platform engineers already read.
3. **Prometheus textfile output** (`aartool inspect --prom`) and a Grafana
   dashboard JSON: posture over time, alert on `paths` regressions.
4. **Undo**: `aartool apply` snapshots touched files and `aartool undo` restores
   them. Removes the number-one objection to a tool that edits `sshd_config`.
5. **Kubernetes node mode**: a DaemonSet/`kubectl debug node` recipe that
   audits every node and aggregates into the existing offline dashboard.
6. **Share card**: `aartool report --card` renders a PNG of score plus chains
   (with `--anonymise`) built for a post.

## Distribution

- Submit to awesome-selfhosted-adjacent lists: awesome-linux-hardening,
  awesome-sysadmin, awesome-ansible, awesome-security.
- Launch post angle (not "another hardening tool"): *"I stopped ranking
  findings and started ranking attack chains."* Show `paths` output. Lead with
  the 15-node estate story and the bug the audit found in its own remediation.
- Post a head-to-head: same host through Lynis, OpenSCAP and `advise` + `paths`,
  honestly, including where the others win. The README's honesty section is an
  asset; keep it.
- Ship a Debian/Ubuntu PPA-style repo (done) plus Homebrew (Linuxbrew), Nix and
  AUR entries: each is a discovery surface.
- Add GitHub topics: `linux-hardening`, `cis-benchmark`, `ansible`, `devsecops`,
  `security-audit`, `platform-engineering`.

## Audit findings to fix

- `test_aartool.sh` "rule is 40 characters wide" fails when `COLUMNS` is set
  wide (got 120): the test should pin `COLUMNS` instead of inheriting it.
- `test_aartool.sh` "surface --apply needs root or a tty" fails when the suite
  itself runs as root; it should assert the no-tty message in that case.
- `test_docs.sh` French-text guard is locale dependent: `grep -P` on the
  emoji in `renderers/html.sh` matches byte `0xef` outside a UTF-8 locale. Run
  it with `LC_ALL=C.UTF-8` or match on code points.
- `demo-audit.json` still carries French remediation text (fixture is older
  than the English-only decision); harmless for `paths`/`advise`, but
  regenerate it before `demo` ever renders remediation.
- `advise` keeps its own copy of the report parser; move it onto
  `lib/records.sh`.
