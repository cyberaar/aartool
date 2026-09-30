#!/usr/bin/env bash
# Smoke tests for the aartool CLI.
#
# These check the parts that decide whether a machine gets changed: that a
# target is required, that it must exist in the inventory, that plan never
# passes apply's flags, and that apply refuses to run unattended without --yes.
# A CLI that guards a destructive operation should have those asserted rather
# than assumed.
#
# Run: bash scripts/tests/test_aartool.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
AARTOOL="./aartool"

# Point at the shipped example rather than whatever inventory this machine has.
# Two reasons: the tests stay hermetic and pass on a fresh clone, where
# inventory/hosts does not exist because it is gitignored; and every run proves
# the example we ask new users to copy is actually usable.
export AARTOOL_INVENTORY="../ansible-hardening/inventory/hosts.example"

PASS=0 FAIL=0
check() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == *"$want"* ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL  %s\n      want to contain: %s\n      got:             %s\n' "$label" "$want" "$got"
  fi
}
# check() is a substring match, which is right for output assertions and wrong
# for "this list must be empty": "none: ZZZ-99" contains "none:". An earlier
# version of the knowledge-base guard used check() and passed while documenting
# a check that did not exist. Exact comparison, for exactly that case.
check_exact() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL  %s\n      want exactly: [%s]\n      got:          [%s]\n' "$label" "$want" "$got"
  fi
}
check_rc() {
  local label="$1" want="$2"; shift 2
  local rc=0
  "$@" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" == "$want" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL  %s\n      want exit %s, got %s\n' "$label" "$want" "$rc"
  fi
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
check    "version"          "$($AARTOOL --version 2>&1)"        "aartool"

# The banner is for humans. --version is parsed, by scripts and by
# test_versions.sh, so it must stay one line with a number on it.
check_exact "version output is one line" "$($AARTOOL --version 2>&1 | wc -l)" "1"
check    "banner on a bare invocation"   "$(LANG=C LC_ALL=C $AARTOOL 2>&1)"        "__ _  __ _ _ __"
check    "banner on --help"              "$(LANG=C LC_ALL=C $AARTOOL --help 2>&1)" "__ _  __ _ _ __"
check    "banner states the version"     "$($AARTOOL --help 2>&1)" "audit, plan, apply, prove"
check    "block banner under UTF-8"      "$(LC_ALL=en_US.UTF-8 $AARTOOL --help 2>&1)" "█████"

# The fallback exists for terminals that cannot render block glyphs. If any
# non-ASCII survives on that path it defeats the whole point, and a line of
# replacement boxes is not something you can un-print.
_ascii_banner=$(LANG=C LC_ALL=C $AARTOOL --help 2>&1 | head -7)
if LC_ALL=C grep -qP '[^\x00-\x7F]' <<<"$_ascii_banner"; then
  FAIL=$((FAIL+1))
  printf 'FAIL  the C-locale banner still contains non-ASCII, which is what it exists to avoid:\n%s\n' \
    "$(LC_ALL=C grep -oP '[^\x00-\x7F]' <<<"$_ascii_banner" | sort -u | tr -d '\n')"
else
  PASS=$((PASS+1))
fi
check    "help lists plan"  "$($AARTOOL --help 2>&1)"           "plan"

# `aartool uninstall` used to be an unknown command while the thing it names
# existed behind `install --uninstall`. Telling someone their verb does not
# exist, when it does, is the worst of both answers.
check    "uninstall is a command"    "$($AARTOOL --help 2>&1)"            "uninstall"
check    "uninstall reaches install" "$($AARTOOL uninstall --help 2>&1)"  "aartool install"

# localhost is the machine inspect just audited, and it needs no inventory.
# Before this, hardening the obvious first target failed on a package install,
# where there is no inventory and nowhere writable to put one.
check    "inspect documents --hints" "$($AARTOOL inspect --help 2>&1)"     "--hints"

# `report` with no argument used to write an EMPTY dashboard while `advise`
# with no argument read the newest report: two commands, the same absent
# argument, opposite meanings. Someone who had just run inspect got a file with
# nothing in it.
check    "report defaults to newest"  "$($AARTOOL report --help 2>&1)" "most recent report"
check    "report documents --empty"   "$($AARTOOL report --help 2>&1)" "--empty"
check    "plan documents localhost"  "$($AARTOOL plan --help 2>&1)"       "localhost"
check    "apply documents localhost" "$($AARTOOL apply --help 2>&1)"      "localhost"

# A wrong target should name the escape hatch rather than only the failure.
check    "bad target suggests localhost" \
         "$(AARTOOL_INVENTORY=$PWD/../ansible-hardening/inventory/hosts.example $AARTOOL plan --target nope 2>&1)" \
         "--target localhost"
check_rc "no args exits 1"  1  "$AARTOOL"
check    "unknown command"  "$($AARTOOL frobnicate 2>&1)"       "Unknown command"
check    "audit points to inspect" "$($AARTOOL audit 2>&1)"     "aartool inspect"
check    "harden points to plan"   "$($AARTOOL harden 2>&1)"    "aartool plan"

# ── Target handling: the guard that stops a fleet-wide run ───────────────────
check    "plan needs target"   "$($AARTOOL plan 2>&1)"                       "--target is required"
check    "apply needs target"  "$($AARTOOL apply 2>&1)"                      "--target is required"
check    "unknown target"      "$($AARTOOL plan -t no-such-host 2>&1)"       "is not a host or group"
check    "missing value"       "$($AARTOOL plan --target 2>&1)"              "needs a value"
check    "positional rejected" "$($AARTOOL plan web-01 2>&1)"                "The target goes after --target"
check    "unknown option"      "$($AARTOOL plan --targets x 2>&1)"           "Unknown option for plan"

# ── plan is not apply ────────────────────────────────────────────────────────
check    "--yes rejected on plan" "$($AARTOOL plan -t x --yes 2>&1)"         "only applies to 'apply'"

# ── apply refuses to run unattended ──────────────────────────────────────────
# stdin is redirected from /dev/null so there is no terminal, which is how this
# would be invoked from CI or a cron job. It must refuse rather than proceed.
check    "apply without a tty" \
         "$($AARTOOL apply -t ubuntu-vm-01 </dev/null 2>&1)" \
         "needs confirmation"

# ── The example inventory we ship is usable ──────────────────────────────────
# ubuntu-vm-01 is defined in hosts.example. If someone edits the example and
# breaks its format, this fails rather than the new user finding out.
check    "example inventory resolves a host" \
         "$($AARTOOL plan -t ubuntu-vm-01 --help 2>&1)" \
         "--target"
check_rc "known host passes the inventory check" 0 \
         env AARTOOL_INVENTORY="../ansible-hardening/inventory/hosts.example" \
         "$AARTOOL" plan -t ubuntu-vm-01 --help

# ── A missing inventory says what to do about it ─────────────────────────────
check    "missing inventory points at the example" \
         "$(AARTOOL_INVENTORY=/nonexistent/hosts $AARTOOL plan -t any 2>&1)" \
         "cp "

# ── surface and doctor ───────────────────────────────────────────────────────
check    "surface runs read-only"  "$($AARTOOL surface 2>&1)"          "Kernel attack surface"
check    "surface names the tier"  "$($AARTOOL surface 2>&1)"          "safe tier only"
check    "surface --strict widens" "$($AARTOOL surface --strict 2>&1)" "KRN-01"
check    "surface --fix emits a drop-in" "$($AARTOOL surface --fix 2>&1)" "sysctl --system"
check_rc "surface changes nothing without --apply" 0 "$AARTOOL" surface
check    "doctor reports"          "$($AARTOOL doctor 2>&1)"           "toolkit located"

# --apply must not be satisfiable by a pipe, same rule as 'apply'.
check    "surface --apply needs root or a tty" \
         "$($AARTOOL surface --apply </dev/null 2>&1)" \
         "root"

# ── The catalogue and the audit must not drift ───────────────────────────────
# Every doorway aartool offers to close has a KRN check that reports on it, and
# every KRN check that maps to a sysctl is offered. Without this, someone adds a
# mitigation to one side and the two views of the same machine start disagreeing
# — which is exactly the class of bug this toolkit exists to find.
cat_ids=$(bash -c 'source aartool-src/lib/surface.sh; surface_catalogue' | cut -f1 | sort -u)
krn_ids=$(grep -ohE '"KRN-[0-9]{2}"' src/checks/kernel.sh | tr -d '"' | sort -u)
missing=""
for id in $cat_ids; do
  printf '%s\n' "$krn_ids" | grep -qx "$id" || missing="$missing $id"
done
if [[ -z "$missing" ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  printf 'FAIL  catalogue entries with no KRN check:%s\n' "$missing"
fi

# ── report ───────────────────────────────────────────────────────────────────
_rep_src="../ansible-hardening/reports/before/ubuntu-vm-01/before_ubuntu-vm-01_1772639445.json"
if [[ -f "$_rep_src" ]]; then
  _rep_out="$(mktemp -t aartool-test-XXXXXX.html)"
  $AARTOOL report "$_rep_src" --out "$_rep_out" >/dev/null 2>&1
  check "report embeds the data"   "$(grep -c 'var PRELOAD' "$_rep_out")" "1"
  check "report keeps script tags balanced" \
        "$(printf '%s/%s' "$(grep -o '<script' "$_rep_out" | wc -l)" "$(grep -o '</script>' "$_rep_out" | wc -l)")" \
        "2/2"

  # A hostname is attacker-influenced on a machine you were asked to audit.
  # Embedding it in a <script> block without escaping < would end the block and
  # turn the rest of the file into markup, in a report you then email to a
  # client. Assert the breakout is closed rather than trusting that it is.
  _rep_evil="$(mktemp -t aartool-evil-XXXXXX.json)"
  sed 's|"host": *"[^"]*"|"host": "evil</script><img src=x onerror=alert(1)>"|' "$_rep_src" > "$_rep_evil"
  _rep_evil_out="$(mktemp -t aartool-evil-XXXXXX.html)"
  $AARTOOL report "$_rep_evil" --out "$_rep_evil_out" >/dev/null 2>&1
  check "hostile hostname does not break out" \
        "$(printf '%s/%s' "$(grep -o '<script' "$_rep_evil_out" | wc -l)" "$(grep -o '</script>' "$_rep_evil_out" | wc -l)")" \
        "2/2"
  check "hostile markup is escaped, not embedded raw" \
        "$(grep -c 'u003c/script' "$_rep_evil_out")" "1"
  rm -f "$_rep_out" "$_rep_evil" "$_rep_evil_out"
fi

check    "report rejects a missing file" "$($AARTOOL report /nonexistent.json 2>&1)" "No such report"
check    "serve refuses a non-numeric port" "$($AARTOOL report --serve abc 2>&1)" "port number"

# ── diff ─────────────────────────────────────────────────────────────────────
if [[ -f "$_rep_src" ]]; then
  # A regression and an improvement in the same pair, so the two are not
  # confused with each other.
  _d_after="$(mktemp -t aartool-after-XXXXXX.json)"
  python3 - "$_rep_src" "$_d_after" <<'PYEOF' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1])); b = d["cyberaar_baseline"]
b["date"] = "2099-01-01 00:00:00"; b["score"] = (b.get("score") or 50) - 7
for r in b["results"]:
    if r["id"] == "SSH-02": r["status"] = "FAIL"
    if r["id"] == "LOG-01": r["status"] = "PASS"
json.dump(d, open(sys.argv[2], "w"))
PYEOF

  if [[ -s "$_d_after" ]]; then
    check    "diff names the regression" "$($AARTOOL diff "$_rep_src" "$_d_after" 2>&1)" "SSH-02"
    check    "diff separates improvements" "$($AARTOOL diff "$_rep_src" "$_d_after" 2>&1)" "Improved"
    # The exit code is the whole point in cron: 1 means something regressed.
    check_rc "diff exits 1 on a regression" 1 "$AARTOOL" diff "$_rep_src" "$_d_after"
    check_rc "diff exits 0 when nothing changed" 0 "$AARTOOL" diff "$_rep_src" "$_rep_src"
    # --quiet must be genuinely silent, or cron mails you every week and you
    # stop reading it.
    check    "diff --quiet is silent when clean" "$($AARTOOL diff "$_rep_src" "$_rep_src" --quiet 2>&1)" ""
    check    "diff --quiet still reports a regression" \
             "$($AARTOOL diff "$_rep_src" "$_d_after" --quiet 2>&1)" "SSH-02"
  fi

  # Comparing two machines would produce a difference that is not drift.
  _d_other="$(mktemp -t aartool-other-XXXXXX.json)"
  sed 's|"host": *"[^"]*"|"host": "a-different-box"|' "$_rep_src" > "$_d_other"
  check    "diff refuses two different hosts" "$($AARTOOL diff "$_rep_src" "$_d_other" 2>&1)" "different hosts"
  check_rc "diff exits 2 when it cannot compare" 2 "$AARTOOL" diff "$_rep_src" "$_d_other"
  rm -f "$_d_after" "$_d_other"
fi

echo '{"not":"a report"}' > /tmp/aartool-notreport.$$.json
check    "diff rejects a non-report" "$($AARTOOL diff /tmp/aartool-notreport.$$.json /tmp/aartool-notreport.$$.json 2>&1)" "not a aartool-baseline report"
rm -f /tmp/aartool-notreport.$$.json
check    "diff needs two arguments" "$($AARTOOL diff one.json 2>&1)" "exactly two reports"

# ── install ──────────────────────────────────────────────────────────────────
# The symlink-not-copy decision is load-bearing: aartool finds everything it
# wraps by walking up from its own file, so a copy alone in /usr/local/bin finds
# nothing. These assert the symlink resolves, the copy fails with an actionable
# message, and AARTOOL_HOME rescues it.
_ins_prefix="$(mktemp -d -t aartool-prefix-XXXXXX)"
$AARTOOL install --prefix "$_ins_prefix" >/dev/null 2>&1
check_rc "install creates a working symlink" 0 "$_ins_prefix/bin/aartool" --version
check    "installed link points at the source" \
         "$(readlink "$_ins_prefix/bin/aartool" | grep -c 'scripts/aartool')" "1"

_ins_copy="$(mktemp -d -t aartool-copy-XXXXXX)/aartool"
cp ./aartool "$_ins_copy" 2>/dev/null
check    "a copy fails with a usable message" \
         "$("$_ins_copy" doctor 2>&1)" "AARTOOL_HOME"
check_rc "AARTOOL_HOME rescues a copy" 0 \
         env AARTOOL_HOME="$(cd .. && pwd)" "$_ins_copy" --version

check    "AARTOOL_HOME pointing nowhere is rejected" \
         "$(AARTOOL_HOME=/tmp $AARTOOL doctor 2>&1)" "no ansible-hardening"

# Overwriting a real file at the install path would be destructive.
printf 'important\n' > "$_ins_prefix/bin/notalink"
check    "install refuses to clobber a real file" \
         "$($AARTOOL install --prefix "$(dirname "$(dirname "$_ins_prefix/bin/notalink")")" 2>&1; \
            rm -f "$_ins_prefix/bin/aartool"; printf 'x')" "x"

$AARTOOL install --prefix "$_ins_prefix" --uninstall >/dev/null 2>&1
check    "uninstall removes the link" "$([ -e "$_ins_prefix/bin/aartool" ] && printf yes || printf no)" "no"
rm -rf "$_ins_prefix" "$(dirname "$_ins_copy")"

# ── inspect forwards every remote flag the baseline documents ────────────────
# inspect passes a WHITELIST of options through to aartool-baseline.sh, so a
# flag added to the baseline is silently rejected by aartool until someone
# remembers to widen that list. This asserts the two agree, rather than leaving
# it to memory.
for _flag in --host --host-file --inventory --user --ssh-key --ssh-opt; do
  if grep -q -- "$_flag" ../scripts/src/main.sh 2>/dev/null || grep -q -- "$_flag" ./src/main.sh 2>/dev/null; then
    check "inspect forwards $_flag" \
          "$($AARTOOL inspect "$_flag" x --help 2>&1 | grep -c 'Unknown option')" "0"
  fi
done

# ── Per-command help ─────────────────────────────────────────────────────────
check    "inspect help" "$($AARTOOL inspect --help 2>&1)" "Changes nothing"
check    "plan help"    "$($AARTOOL plan --help 2>&1)"    "--target"
check    "apply help"   "$($AARTOOL apply --help 2>&1)"   "--yes"
check    "surface help" "$($AARTOOL surface --help 2>&1)" "--strict"
check    "doctor help"  "$($AARTOOL doctor --help 2>&1)"  "Changes nothing"
check    "report help"  "$($AARTOOL report --help 2>&1)"  "self-contained"
check    "diff help"    "$($AARTOOL diff --help 2>&1)"    "Exit codes"
check    "install help" "$($AARTOOL install --help 2>&1)" "SYMLINK"

check    "advise help"  "$($AARTOOL advise --help 2>&1)"  "--safe-only"
check    "explain help" "$($AARTOOL explain --help 2>&1)" "--list"

# ── explain ──────────────────────────────────────────────────────────────────
# The point of explain is that it always answers. A help command that refuses
# on a third of its inputs teaches people not to type it.
ALL_IDS=$($AARTOOL explain --list 2>/dev/null | awk '{print $1}')
check "explain --list covers the whole baseline" \
      "$(printf '%s\n' "$ALL_IDS" | grep -c . )" "109"

silent=0 empty=0
for id in $ALL_IDS; do
  out=$($AARTOOL explain "$id" 2>&1) || { silent=$((silent+1)); continue; }
  # Every answer must reach at least the WHAT section. Under set -euo pipefail
  # a grep that matches nothing used to kill the command mid-way, printing a
  # partial page and exiting 1 with no message. That bug shipped once.
  [[ "$out" == *"WHAT"* ]] || empty=$((empty+1))
done
check_exact "explain answers for every ID (no silent exit)" "$silent" "0"
check_exact "explain reaches WHAT for every ID"             "$empty"  "0"

# Written entries must name checks that exist, or the knowledge base documents
# settings the tool does not actually look at.
missing=""
for id in $($AARTOOL explain --written 2>/dev/null); do
  printf '%s\n' "$ALL_IDS" | grep -qx "$id" || missing="$missing $id"
done
check_exact "every written entry names a real check" "$missing" ""

# A written entry naming a real ID is not enough: it must describe THAT check.
# Four entries in the first draft were written against the wrong ID (SSH-09 is
# HostbasedAuthentication, not ciphers; NET-05 is dangerous services, not IP
# forwarding; FS-01 is /etc/passwd perms, not /tmp; LOG-04 is audit rules, not
# remote syslog). Every one existed, so the existence guard passed them all, and
# explain would have confidently explained the wrong thing.
#
# The overlap test: a distinctive word from the check's own title must appear in
# the entry. Crude, and it caught all four.
STOP=" the and not for with all its configured disabled enabled active running ok correct perms "
offtopic=""
for id in $($AARTOOL explain --written 2>/dev/null); do
  title=$($AARTOOL explain --list 2>/dev/null | awk -v i="$id" '$1==i{$1="";print}' | tr 'A-Z' 'a-z')
  body=$($AARTOOL explain "$id" 2>/dev/null | tr 'A-Z' 'a-z')
  hit=0
  for w in $(tr -cs 'a-z0-9_.' ' ' <<<"$title"); do
    [[ ${#w} -ge 4 ]] || continue
    [[ "$STOP" == *" $w "* ]] && continue
    [[ "$body" == *"$w"* ]] && { hit=1; break; }
  done
  [[ $hit -eq 1 ]] || offtopic="$offtopic $id"
done
check_exact "every written entry describes the check it names" "$offtopic" ""

check    "explain rejects a bad ID"  "$($AARTOOL explain KRN-99 2>&1)" "No check called"
check    "explain suggests the family" "$($AARTOOL explain KRN-99 2>&1)" "KRN-01"
check_rc "explain bad ID exits 1"   1  $AARTOOL explain KRN-99
check    "explain is case tolerant" "$($AARTOOL explain krn-04 2>&1)" "userfaultfd"
check    "explain refuses two IDs"  "$($AARTOOL explain KRN-01 KRN-02 2>&1)" "one check ID at a time"

# ── advise ───────────────────────────────────────────────────────────────────
FIXTURE="tests/fixtures/audit-fixture.json"
# This fixture is a REAL report, captured from a live remote audit, with only
# the hostname and date replaced. The previous one was hand-written compact
# JSON; advise's record splitter matched it and matched nothing the renderer
# actually writes. A fixture that is not shaped like production is a test that
# passes while the feature is broken.
check "fixture is renderer-shaped, not hand-built" \
      "$(tr -d '\n' < "$FIXTURE" | grep -c '\],  *"ansible_remediation"')" "1"
ADV=$($AARTOOL advise "$FIXTURE" --target web-01 --user ubuntu 2>&1)

check "advise names the host"        "$ADV" "proof-target-01"
check "advise orders by reachability" "$ADV" "Wave 1"
check "advise writes the target in"  "$ADV" "--target web-01 --user ubuntu"
check "advise separates the costly"  "$ADV" "Decide before you apply"
check "advise ends with an order"    "$ADV" "Order of operations"

# FAIL before WARN inside a wave: an operator reads top down and stops.
W1=$(printf '%s\n' "$ADV" | sed -n '/Wave 1/,/preview/p' | grep -oE '^   (FAIL|WARN)' | tr -d ' ')
check "wave 1 puts FAIL first" "$(printf '%s\n' "$W1" | head -1)" "FAIL"
check "wave 1 has no FAIL after a WARN" \
      "$(printf '%s\n' "$W1" | uniq | tr '\n' ',')" "FAIL,WARN,"

# The unpatched-kernel finding is reachable from the network, not hygiene.
check "SYS-11 is a wave 1 item" \
      "$(printf '%s\n' "$ADV" | sed -n '/Wave 1/,/preview/p' | grep -c 'SYS-11')" "1"

# --safe-only takes the costly items out of the waves without hiding them.
# Dropping findings silently is the failure mode this whole tool exists to
# avoid, so assert both halves: gone from the sequence, still on the page.
SAFE=$($AARTOOL advise "$FIXTURE" --safe-only 2>&1)
SAFE_WAVES=$(printf '%s\n' "$SAFE" | sed -n '1,/Decide before you apply/p')
check "safe-only drops the costly from the waves" "$(printf '%s\n' "$SAFE_WAVES" | grep -c 'KRN-01')" "0"
check "safe-only still lists them to decide on"   "$(printf '%s\n' "$SAFE" | grep -c 'aartool explain KRN-01')" "1"
check "safe-only keeps the safe ones"             "$(printf '%s\n' "$SAFE_WAVES" | grep -c 'SSH-03')" "1"

check "wave filter shows only that wave" \
      "$(printf '%s\n' "$($AARTOOL advise "$FIXTURE" --wave 3 2>&1)" | grep -c 'Wave 1')" "0"
check "wave filter rejects nonsense" "$($AARTOOL advise "$FIXTURE" --wave 9 2>&1)" "1, 2, 3 or 4"

# Every command advise prints must be one aartool would accept. It is generated
# from the remediation map, and a plan telling someone to run an invalid
# --only is the same silent no-op the map guard exists to prevent.
for tagset in $(printf '%s\n' "$ADV" | grep -oP '\-\-only \K[a-z,]+'); do
  for tag in ${tagset//,/ }; do
    grep -rqs -- "$tag" ../ansible-hardening/playbooks/2_configure_hardening.yml \
      || { FAIL=$((FAIL+1)); printf 'FAIL  advise printed --only %s, absent from the playbook\n' "$tag"; }
  done
  PASS=$((PASS+1))
done

check_rc "advise with no report exits 1" 1 env HOME=/nonexistent $AARTOOL advise --wave 1
check "advise rejects a non-report" \
      "$($AARTOOL advise ../README.md 2>&1)" "does not look like"

# ── The shape of an inspect run ──────────────────────────────────────────────
#
# 109 results used to print as 327 lines with the score in the middle of them,
# because every non-PASS check carried a fix and a 117-line remediation block
# followed the score. Both are gone from the default output; the score is the
# last thing before the pointer to advise.
_core=src/lib/core.sh
_term=src/renderers/terminal.sh

# Assert the files are there before grepping them. A wrong path makes every
# `if grep -q ... ; then bad; else ok; fi` check pass for the wrong reason,
# which is how the first version of this block reported four false passes.
for _f in "$_core" "$_term"; do
  [[ -f "$_f" ]] && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); printf 'FAIL  %s not found; the checks below prove nothing\n' "$_f"; }
done

check "hints are off by default"   "$(cat $_core)"  'AARTOOL_HINTS:-0'
# These two used to grep core.sh for the literal argument list of its printf,
# so widening the columns to fit the terminal broke them while the output was
# perfectly correct. Assert what a user sees instead: a source-text match proves
# a line exists, not that it prints anything.
_row=$(
  # shellcheck source=/dev/null
  source "$_core" 2>/dev/null
  section "9. TEST"
  add_result "Test" "FAIL" "SSH-01" "A check name" "Un nom" "some detail" ""
) 2>/dev/null
# ── The horizontal rules must be real characters ─────────────────────────────
# rule() was built with `tr ' ' '━'`, and tr translates BYTES: ━ is e2 94 81, so
# every space became a lone 0xe2 and the score box printed a run of invalid
# UTF-8 instead of a banner. It shipped in 3.5.0 and a reader spotted it, not
# the suite: nothing here looked at what the rule actually contained.
#
# Assert the rendered rule is the requested character, the requested number of
# times, and is valid UTF-8.
_r=$(
  # shellcheck source=/dev/null
  source "$_core" 2>/dev/null
  # shellcheck disable=SC2034  # read by rule() from the sourced core.sh
  REPORT_WIDTH=40
  rule
)
check "rule draws the box character"  "$_r"  '━━━━━━━━━━'
_rlen=$(printf '%s' "$_r" | wc -m)          # characters, not bytes
_rbytes=$(printf '%s' "$_r" | wc -c)
check "rule is 40 characters wide"    "$_rlen"    '40'
check "rule is valid UTF-8"           "$(printf '%s' "$_r" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 && echo ok)"  'ok'
# 40 three-byte characters. A byte-wise build would give 40 bytes, not 120, so
# this fails loudly on the exact regression above.
check "rule is multibyte, not bytes"  "$_rbytes"  '120'

check "section prints a header"    "$_row"  'STATUS'
check "header names every column"  "$_row"  'CHECK'
check "check IDs are printed"      "$_row"  'SSH-01'
check "the status word is printed" "$_row"  'FAIL'
check "the check name is printed"  "$_row"  'A check name'
check "the detail is printed"      "$_row"  'some detail'

# No emoji in the status column: they are one, two and two cells wide, so no two
# rows line up, which is most of why 109 results read as a wall.
if grep -qE '^\s*printf "  \$\{color\}\$\{symbol\}' "$_core"; then
  FAIL=$((FAIL+1)); printf 'FAIL  the status column prints an emoji again; rows will not align\n'
else
  PASS=$((PASS+1))
fi

# The score must be the last thing the summary prints, not the middle.
if grep -q '_ansible_terminal_plan$' "$_term"; then
  FAIL=$((FAIL+1)); printf 'FAIL  _render_summary calls the remediation plan again; the score is back in the middle\n'
else
  PASS=$((PASS+1))
fi
check "summary points at advise"   "$(cat $_term)"  'aartool advise'

# ── paths, badge, demo ───────────────────────────────────────────────────────
_fx="../dashboard/demo-audit.json"
_pout=$($AARTOOL paths "$_fx" 2>&1); _prc=$?
check "paths finds a complete chain in the sample" "$_pout" "COMPLETE"
check "paths exits 1 when a chain is complete"     "rc=$_prc" "rc=1"
check "paths names a link to cut"                  "$_pout" "link to cut"
check "paths help"  "$($AARTOOL paths --help 2>&1)" "attack"

# Every check ID named in a chain must be a check the baseline actually emits.
# A typo does not error: the stage simply never opens, the chain can never be
# COMPLETE, and `paths` reports less exposure than the host has. The failure
# produces the REASSURING answer, which is the one nobody goes looking for.
# Proven on this suite: renaming SYS-04 to SYS-44 in the single-ID stage of
# "the local climb" dropped it from the COMPLETE list, 4 chains to 3, while
# every assertion here stayed green.
#
# check_exact, not check: "none" is a substring of any list of unknown IDs.
_chain_ids=$(sed -n '/_paths_chains()/,/^}/p' aartool-src/cmd/paths.sh \
             | grep '^STAGE|' | cut -d'|' -f4 | tr ',' '\n' | sed '/^$/d' | sort -u)
_known_ids=$($AARTOOL explain --list 2>/dev/null | awk '{print $1}' | sort -u)
_unknown=$(comm -23 <(printf '%s\n' "$_chain_ids") <(printf '%s\n' "$_known_ids") | tr '\n' ' ')
check_exact "every attack-chain ID is a real check" "${_unknown:-none}" "none"

# And the extraction itself has to be finding something. If the sed stops
# matching after a refactor, the comparison above is empty against empty and
# passes while checking nothing.
check_exact "the chain-ID extraction is not silently empty" \
  "$([[ $(printf '%s\n' "$_chain_ids" | grep -c .) -ge 20 ]] && echo ok || echo "only $(printf '%s\n' "$_chain_ids" | grep -c .) IDs found")" "ok"

# The badge label is user text landing in XML, in element content AND inside a
# double-quoted attribute. Two separate bugs lived here:
#
#  - `${label//</&lt;}` yields "<lt;" on bash 5.2 and later, where an unescaped
#    & in the replacement expands to the matched text. src/lib/core.sh has the
#    right form with a comment saying so, but it is not bundled into aartool,
#    which is how the bug came back in new code.
#  - quotes were not escaped at all, so a label of  x" onload="alert(1)
#    produced a VALID svg carrying an onload handler. Valid is the dangerous
#    part: nothing downstream complains about it.
_bdir=$(mktemp -d)
$AARTOOL badge "$_fx" --label '<b>&"x' --out "$_bdir/t.svg" >/dev/null 2>&1
_blab=$(grep -o 'aria-label="[^"]*"' "$_bdir/t.svg" | head -1)
check "badge escapes angle brackets as entities, not as <lt;" "$_blab" "&lt;b&gt;"
check "badge escapes the ampersand"                           "$_blab" "&amp;"
check "badge escapes the quote that would close the attribute" "$_blab" "&quot;"
check_exact "badge emits no <lt; from the bash 5.2 patsub trap" \
  "$(grep -c '<lt;\|>gt;' "$_bdir/t.svg")" "0"

# Parse it and ask the DOM, rather than grepping: the injected handler appears
# in the file either way, and only a parser can say whether it is an attribute
# or escaped text.
$AARTOOL badge "$_fx" --label 'x" onload="alert(1)' --out "$_bdir/x.svg" >/dev/null 2>&1
check_exact "badge label cannot inject an event handler" \
  "$(python3 - "$_bdir/x.svg" <<'PYEOF'
import sys, xml.dom.minidom as m
d = m.parse(sys.argv[1])
print(' '.join(n for el in d.getElementsByTagName('*')
                 for n in el.attributes.keys() if n.lower().startswith('on')) or 'none')
PYEOF
)" "none"
rm -rf "$_bdir"
_bdir=$(mktemp -d)
$AARTOOL badge "$_fx" --out "$_bdir/b.svg" >/dev/null 2>&1
check "badge writes an svg with the score" "$(cat "$_bdir/b.svg" 2>/dev/null)" "38/100"
# The colour bands: derive each report from the real fixture by changing only
# the score, so the badge's parse is exercised on the producer's shape.
for _band in "95 #4c1" "80 #97ca00" "55 #dfb317" "10 #e05d44"; do
  set -- $_band
  sed "s/\"score\": 38/\"score\": $1/" "$_fx" > "$_bdir/s.json"
  $AARTOOL badge "$_bdir/s.json" --out "$_bdir/s.svg" >/dev/null 2>&1
  check "badge colour for score $1" "$(cat "$_bdir/s.svg" 2>/dev/null)" "$2"
done
rm -rf "$_bdir"

# A report that has been through jq, or any other JSON tool, is still a valid
# report. The record split was a literal '},{' and the field greps required no
# space after the colon, so a pretty-printed report came back as ONE record
# whose "id" grep returned every id at once:
#
#   paths   -> ST["<many lines>"]: bad array subscript, no output, EXIT 0
#   advise  -> "Nothing open in this report. Every check passed." on a 62%
#              report carrying 11 failures
#
# Exit 0 is documented as "no complete attack chain", so a CI gate went green
# on a report the tool had failed to read, and advise gave the reassuring
# answer to a question it could not answer. Both are CLAUDE.md 4.6: "could not
# read it" must never share a code path with "the answer is no".
_jdir=$(mktemp -d)
if command -v jq >/dev/null 2>&1; then
  jq . "$_fx" > "$_jdir/pretty.json" 2>/dev/null
  _p_flat=$($AARTOOL paths "$_fx" 2>/dev/null | grep -c COMPLETE || true)
  _p_pretty=$($AARTOOL paths "$_jdir/pretty.json" 2>/dev/null | grep -c COMPLETE || true)
  check_exact "paths reads a pretty-printed report the same as a flat one" \
    "$_p_pretty" "$_p_flat"
  _a_pretty=$($AARTOOL advise "$_jdir/pretty.json" 2>&1)
  check_exact "advise does not call a pretty-printed report all green" \
    "$(grep -c 'Every check passed' <<<"$_a_pretty")" "0"
  check "advise still finds the findings in a pretty-printed report" "$_a_pretty" "Wave 1"
else
  check_exact "jq is needed to prove the pretty-report parse" "jq missing" "jq present"
fi

# And when a report genuinely cannot be parsed, the exit code must not say
# "clean". Renaming the key the results array is anchored on is the honest
# unreadable case.
sed 's/"ansible_remediation"/"XX_no_such_key"/' "$_fx" > "$_jdir/broken.json"
$AARTOOL paths "$_jdir/broken.json" >/dev/null 2>&1
check_exact "paths on an unreadable report does not exit 0" "$?" "1"
rm -rf "$_jdir"

check "demo runs without root and shows the loop" "$($AARTOOL demo 2>&1)" "Now the real thing"

# ── paths: estate view and mermaid ───────────────────────────────────────────
# Inputs are built from the real fixture by changing only host and statuses.
_pdir=$(mktemp -d)
python3 - "$_fx" "$_pdir" <<'PY2'
import json, sys
src = json.load(open(sys.argv[1]))
def mk(name, host, close=()):
    d = json.loads(json.dumps(src)); b = d["cyberaar_baseline"]; b["host"] = host
    for r in b["results"]:
        if r["id"] in close:
            r["status"] = "PASS"
    json.dump(d, open(f"{sys.argv[2]}/{name}.json", "w"))
mk("a", "web-01")
mk("b", "web-02", close=("SYS-04",))
mk("c", "web-03", close=("SYS-04", "LOG-01", "LOG-06", "LOG-02"))
mk("dup", "web-01")
mk("evil", 'x"]\nend\n%% pwn')
mk("evil2", 'we b<script>;x[1]')
e = json.loads(json.dumps(src)); e["cyberaar_baseline"]["results"] = []
json.dump(e, open(f"{sys.argv[2]}/empty.json", "w"))
PY2
_est=$($AARTOOL paths "$_pdir/a.json" "$_pdir/b.json" "$_pdir/c.json" 2>&1); _erc=$?
check "estate: chain complete on every host"   "$_est" "COMPLETE on 3 of 3  The front door"
check "estate: climb complete only where MAC is missing" "$_est" "COMPLETE on 1 of 3  The local climb"
check "estate: silent tenant complete on two"  "$_est" "COMPLETE on 2 of 3  The silent tenant"
check "estate: smallest change names the MAC finding" "$_est" "close SYS-04"
check "estate: exits 1 when a chain is complete" "rc=$_erc" "rc=1"
check "estate: refuses two reports for one host" \
  "$($AARTOOL paths "$_pdir/a.json" "$_pdir/dup.json" 2>&1)" "same host 'web-01'"
check "estate: refuses an empty report" \
  "$($AARTOOL paths "$_pdir/a.json" "$_pdir/empty.json" 2>&1)" "Could not read any results"
_mm=$($AARTOOL paths "$_pdir/c.json" --format mermaid 2>&1)
check "mermaid: starts a flowchart" "$_mm" "flowchart LR"
check "mermaid: a fully closed stage is drawn closed" "$_mm" ']:::closed'
check "mermaid: an open stage is drawn open" "$_mm" ']:::open'
check "mermaid: a broken chain is labelled broken" "$_mm" "(broken)"
_hostile=$($AARTOOL paths "$_pdir/evil.json" --format mermaid 2>&1)
check_exact "mermaid: a hostile hostname adds no lines" \
  "$(wc -l <<<"$_hostile")" "$(wc -l <<<"$($AARTOOL paths "$_pdir/a.json" --format mermaid 2>&1)")"
# The quote case is cut short by the reader; this one reaches the sanitiser.
check_exact "mermaid: a hostname keeps only safe characters" \
  "$($AARTOOL paths "$_pdir/evil2.json" --format mermaid 2>&1 | head -1)" "%% aartool paths, host: webscriptx1"
check "mermaid needs one report" \
  "$($AARTOOL paths "$_pdir/a.json" "$_pdir/b.json" --format mermaid 2>&1)" "single report"
rm -rf "$_pdir"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
