# The offline dashboard

A single HTML file that renders audit reports with no server, no build step and
no external requests, so it works on an isolated network.

It is built for the person who has to form a judgement about an estate, not for
the person who ran the scan. Panels, in the order an auditor asks the questions:

| panel | the question it answers |
|---|---|
| Stat row | How big is this estate, how is it doing, how much is outstanding |
| **Attack paths** | Which chains an attacker can walk end to end, on how many hosts, and the smallest change that breaks each. The same chains and logic as `aartool paths` over several reports |
| **Score by host** | Which machine do I open first. Sorted worst first, click to open |
| Where the findings are | Which area is weak across the whole estate, not just one host |
| **Fix once, help most hosts** | Which single finding, fixed once, clears the most machines |
| Host drawer | What to fix first on this machine, in `aartool advise` wave order, with the commands |

Remediation is expressed as `aartool` commands throughout, scoped with `--only`
from the `remediation_tags` the report carries. Anything whose fix has a real
operational cost is marked **needs a decision** and kept out of the run-it-now
sequence, exactly as `aartool advise` does.

`aartool report --out fleet.html` bakes results straight into a copy of it,
producing one file you can email; see [AARTOOL.md](AARTOOL.md#report). This
document covers using the dashboard by hand.

---

## Using it by hand
`dashboard/index.html` is a single-file, zero-dependency web dashboard for visualising baseline reports across your entire fleet. No install, no server, no internet connection required.

### Features

| Feature | Description |
|---|---|
| Fleet score | A gauge and the number, given more room than anything else on the page because it is the one figure a reader repeats afterwards |
| Stat row | FAIL / WARN / PASS, how many hosts are below 60, how many findings need a decision |
| Attack paths | Four chains (front door, local climb, silent tenant, pivot) drawn as stage pipelines. A stage is shaded by how many of the hosts shown have it open, a chain is **Complete on N of M** when every stage is open, and the smallest set of findings whose closure breaks it on all of those hosts is listed with a chip per affected host. Mirrored from `aartool paths`; a guard fails the build if the two drift |
| Score by host | One row per host, worst first: name, score, failure counts, a threshold-coloured bar and a **View details** button. Selecting it opens everything about that machine |
| How exposed is the estate | Open findings distributed across the four reachability waves. A tall wave 1 means exposure from outside; a tall wave 3 means you would not find out if there were |
| Estate heatmap | Hosts down, categories across. A red **column** is a policy problem across the fleet, a red **row** is one bad machine. Select any cell to open that host |
| Where the findings are | FAIL / WARN / PASS per category across every host shown |
| Score trend | A sparkline per host in the drawer, drawn only when there is more than one audit, because a single point is not a trend |
| Fix once, help most hosts | The findings ranked by how many machines they affect. The answer to "what is the single most useful thing to do this week" |
| Sort, scope and search | Sort by score, failures, name or movement. Narrow to hosts below 60 or with failures. Search host, OS, check ID or text |
| Host drawer | First audit against latest with the delta, the plan in `aartool advise` wave order, the aartool commands, and every check with a filter |
| aartool remediation | `aartool plan` and `aartool apply` scoped with `--only`, built from the `remediation_tags` in the report so the dashboard carries no copy of the map |
| Needs a decision | Findings whose fix breaks something real are listed separately and left out of the run-it-now commands, as `aartool advise` does |
| Before / after | Load a pre- and post-hardening report for the same host and the movement is worked out for you |
| PDF export | Browser print to PDF produces a document, not a screenshot of a website: a cover block stating scope, audit window, check counts and fleet score; the light palette from cyberaar.io so the accent is legible on paper; table headers that repeat across pages; and a per-host **Open findings** section that does not exist on screen, because on screen those live in the drawer and a printed summary with no findings in it is a scorecard rather than a report |
| Fully offline | No CDN, no npm, no build step, no network of any kind. A test asserts the file references nothing outside itself |

---

### Step 1: Produce reports

```bash
sudo aartool inspect                                  # this machine
aartool inspect --host 10.0.1.10 --user admin         # one remote host
aartool inspect --inventory inventory/hosts           # a whole estate
```

Reports land in `./reports` as HTML and JSON. The dashboard reads the JSON.

For a before-and-after on one host, audit it, apply hardening, then audit it
again. The dashboard works the movement out from the timestamps; you do not
have to label anything.

```bash
sudo aartool inspect                      # before
aartool apply --target myserver --user admin --only ssh
sudo aartool inspect                      # after
```

---

### Step 2: Open the dashboard

**Linux / macOS:**
```bash
xdg-open dashboard/index.html         # Linux
open dashboard/index.html             # macOS
```

**WSL2 (Windows Subsystem for Linux):**
```bash
# Option A: open via Windows Explorer
explorer.exe dashboard/index.html

# Option B: get the Windows path and paste into browser
wslpath -w $(pwd)/dashboard/index.html
# Output: \\wsl$\Ubuntu\...\dashboard\index.html
# Paste that path into Chrome / Edge address bar
```

**Any platform, serve locally:**
```bash
python3 -m http.server 8080 --directory dashboard/
# Then open http://localhost:8080 in your browser
```

---

### Step 3: Load reports

1. Click **Load Reports** (top right) or drag & drop `.json` files onto the drop zone
2. The dashboard groups reports by `host` field, load reports from multiple hosts at once
3. For before/after comparison: load two reports for the same host, the dashboard detects them automatically by date and shows the score delta

**Where to find reports after an Ansible pipeline run:**
```
ansible-hardening/reports/before/<hostname>/report.json   ← pre-hardening
ansible-hardening/reports/after/<hostname>/report.json    ← post-hardening
```

---

### Step 4: Explore

- **Start at Score by host.** Worst first. That is the machine to open.
- **Select a bar** to open the drawer: the plan in wave order, the aartool
  commands, and every check with a filter.
- **Read Fix once, help most hosts** before opening anything. One finding that
  affects twelve machines is worth more of your week than three that affect one.
- **Watch for "needs a decision".** Those are the fixes that break something
  real, and they are deliberately not in the commands you are given to run.
- **Export PDF**: the button top right, then your browser's print dialog.
  What comes out is meant to be attached to an engagement report: a cover block
  saying what was audited and when, the fleet evidence, then every host's open
  findings in reachability order with the `aartool explain` command for each.
  Roughly one page per two hosts.

> Full reference: [`dashboard/README.md`](../dashboard/README.md)

---
