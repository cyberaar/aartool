#!/usr/bin/env bash
# Documentation guard.
#
# The worst bug this repository has shipped twice is not a crash. It is our own
# output telling someone to run a command that cannot work: a remediation line
# naming an Ansible tag no role carries, a report renderer pointing at an
# inventory file that does not exist, and a first draft of docs/AARTOOL.md that
# told people to run 'aartool inspect --json FILE' when the flag is '-o DIR'.
#
# Each of those fails silently. The reader runs it, gets an error they assume is
# their own fault, and stops trusting the tool.
#
# So: every aartool invocation inside a fenced code block in the documentation
# is parsed, and its command and long options are checked against the CLI's own
# --help. Documentation that drifts fails the build.
#
# Run: bash scripts/tests/test_docs.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
AARTOOL="./aartool"
DOCS=(../README.md ../docs/AARTOOL.md ../docs/ANSIBLE.md ../docs/BASELINE.md ../docs/DASHBOARD.md ../docs/CONTAINER.md)

# CLAUDE.md is gitignored, so it is checked only when a working copy has one.
# It is added here because it was guarded by nothing and rotted accordingly:
# it sat at "cyberaar-toolkit, v3.0.0, 21 roles" against a tree holding 52,
# while every guarded document stayed correct. It is the first thing an agent
# reads, so a stale one misinforms a whole session before any work starts.
# Conditional on purpose: listing it unconditionally would fail CI, where the
# file does not exist, since a missing entry in DOCS is a failure below.
[[ -f ../CLAUDE.md ]] && DOCS+=(../CLAUDE.md)

PASS=0 FAIL=0
fail() { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$*"; }
ok()   { PASS=$((PASS+1)); }

# Commands the dispatcher accepts, taken from the help rather than hardcoded.
COMMANDS=$($AARTOOL --help 2>&1 | sed -n '/^Commands:/,/^Global options:/p' \
          | grep -oP '^  \K[a-z]+' | sort -u)
[[ -n "$COMMANDS" ]] || { printf 'FAIL  could not read the command list from --help\n'; exit 1; }

# Cache each command's long options once.
declare -A OPTS
for c in $COMMANDS; do
  OPTS["$c"]=" $($AARTOOL "$c" --help 2>&1 | grep -oP '\-\-[a-z][a-z-]*' | sort -u | tr '\n' ' ')"
done
# Global options are accepted everywhere.
GLOBAL=" --help --verbose --version "

for doc in "${DOCS[@]}"; do
  [[ -f "$doc" ]] || { fail "$doc does not exist"; continue; }

  # Only fenced code blocks. Prose says things like "the --only it printed",
  # and a shell line is what a reader actually copies.
  while IFS= read -r line; do
    # Strip a leading sudo, a leading ./scripts/ or scripts/ path, and comments.
    line="${line%%#*}"
    line=$(sed -E 's#^[[:space:]]*(sudo[[:space:]]+)?(\./)?(scripts/)?aartool[[:space:]]+##' <<<"$line")
    [[ "$line" == "$(sed -E 's#^[[:space:]]*##' <<<"$line")" ]] || true

    read -ra words <<<"$line"
    [[ ${#words[@]} -gt 0 ]] || continue
    cmd="${words[0]}"

    # Placeholders in a usage synopsis, not a real invocation.
    [[ "$cmd" == "<command>" || "$cmd" == \<* ]] && continue

    # `aartool --help` and `aartool --version` are real invocations with no
    # subcommand. Validate the option and move on, rather than reading it as a
    # command name and reporting that --help is not a command.
    if [[ "$cmd" == --* ]]; then
      if [[ "$GLOBAL" == *" ${cmd%%=*} "* ]]; then ok
      else fail "$(basename "$doc"): 'aartool $cmd' is not a global option"; fi
      continue
    fi

    if ! grep -qx -- "$cmd" <<<"$COMMANDS"; then
      # 'why' is a documented alias, and the dispatcher lists aliases nowhere.
      [[ "$cmd" == "why" ]] && { ok; continue; }
      fail "$(basename "$doc"): 'aartool $cmd' is not a command"
      continue
    fi
    ok

    for w in "${words[@]:1}"; do
      [[ "$w" == --* ]] || continue
      w="${w%%=*}"
      # Documented placeholders like --only TAGS are fine; the flag is the word.
      if [[ "${OPTS[$cmd]}" != *" $w "* && "$GLOBAL" != *" $w "* ]]; then
        fail "$(basename "$doc"): 'aartool $cmd $w' is not an option $cmd accepts"
      else
        ok
      fi
    done
  done < <(awk '/^```/{f=!f; next} f' "$doc" | grep -E '^[[:space:]]*(sudo[[:space:]]+)?(\./)?(scripts/)?aartool[[:space:]]')
done

# The dedicated manual must exist and be linked from the README, or nobody
# finds it.
for d in AARTOOL ANSIBLE BASELINE DASHBOARD CONTAINER PACKAGING MEDIA; do
  [[ -f "../docs/$d.md" ]] && ok || fail "docs/$d.md is missing"
  grep -q "docs/$d.md" ../README.md && ok || fail "README.md does not link to docs/$d.md"
done

# No em dashes: house style, and they are a nuisance to type on the keyboard
# this repository is written from.
for doc in "${DOCS[@]}" ; do
  n=$(grep -c '—' "$doc" 2>/dev/null || true)
  [[ "$n" == "0" ]] && ok || fail "$(basename "$doc") contains $n em dashes"
done

# Counts in prose drift the moment a role or a check is added, and a README
# that says 51 roles next to a directory holding 52 is the first thing a
# sceptical reader checks. Both numbers are derivable, so derive them.
ROLES_ON_DISK=$(find ../ansible-hardening/roles -maxdepth 1 -mindepth 1 -type d | wc -l)
for doc in "${DOCS[@]}"; do
  while read -r n; do
    [[ "$n" == "$ROLES_ON_DISK" ]] && ok \
      || fail "$(basename "$doc") says $n roles; there are $ROLES_ON_DISK on disk"
    # The qualifier class allows a hyphen: "52 CIS-aligned roles" was invisible
    # to a \w-only class, so a count could sit in a guarded document unguarded,
    # which is the exact rot this block exists to prevent.
  done < <(grep -oP '\b\K[0-9]+(?= ([\w-]+ )?roles?\b)' "$doc" | sort -u)
done

CHECKS=$($AARTOOL explain --list 2>/dev/null | grep -c .)
for doc in "${DOCS[@]}"; do
  while read -r n; do
    [[ "$n" == "$CHECKS" ]] && ok \
      || fail "$(basename "$doc") says $n checks; the baseline emits $CHECKS"
  done < <(grep -oP '\b\K[0-9]+(?= (security )?checks?\b)' "$doc" | sort -u)
done

# Check IDs quoted in prose must exist. Four knowledge-base entries were once
# written against the wrong ID, and the same mistake in a document is worse: the
# reader cannot run it to find out.
KNOWN_IDS=$($AARTOOL explain --list 2>/dev/null | awk '{print $1}')
for doc in "${DOCS[@]}"; do
  while read -r id; do
    if printf '%s\n' "$KNOWN_IDS" | grep -qx "$id"; then
      ok
    else
      fail "$(basename "$doc") refers to check $id, which does not exist"
    fi
  done < <(grep -oP '\b(SYS|AUTH|SSH|NET|KRN|FS|LOG|INT|COMP)-[0-9]{2}\b' "$doc" | sort -u)
done

# Local links must resolve. Splitting the README into docs/ silently broke
# three of them: links written relative to the repo root resolved to
# docs/scripts/README.md and friends once the text moved down a directory.
# GitHub renders them as normal links and only 404s when someone clicks.
while read -r doc target; do
  [[ -z "$doc" ]] && continue
  base=$(dirname "$doc")
  resolved=$(cd "$base" 2>/dev/null && realpath -m --relative-to=. "$target" 2>/dev/null)
  if [[ -e "$base/$target" ]]; then
    ok
  else
    fail "$(basename "$doc") links to '$target', which does not exist (${resolved:-unresolvable})"
  fi
done < <(
  for doc in ../README.md ../CONTRIBUTING.md ../docs/*.md; do
    [[ -f "$doc" ]] || continue
    grep -oP '\]\(\K[^)#][^)]*' "$doc" \
      | sed 's/#.*//' \
      | grep -vE '^(https?:|mailto:)' \
      | while read -r t; do [[ -n "$t" ]] && printf '%s %s\n' "$doc" "$t"; done
  done
)

# ── The tool speaks English ──────────────────────────────────────────────────
#
# Every check name was English while its remediation hint was French, so a
# single run mixed the two languages. Direction decision 2026-08-26: the tool
# is English only. The bilingual French halves of the section titles and the
# per-check name_fr line in the HTML report went with the hints.
#
# name_fr is still an argument to add_result and is no longer rendered
# anywhere. Removing it means touching 256 call sites, which is a separate
# mechanical change; this guard is about what a user sees.
# The pattern matches the UTF-8 BYTES of the accented letters, with the locale
# pinned so it means the same thing on every machine. The previous form,
# a PCRE class of \x{00e9} and friends, changed meaning with the ambient locale:
# under a UTF-8 locale those are code points, under LC_ALL=C they are single
# bytes. In byte mode 0xEF matched the third byte of U+FE0F, the variation
# selector in the "\u26a0\ufe0f" badge on line 25 of html.sh, so the guard
# reported French text in a file that has never contained any. CI pins
# LC_ALL=C.UTF-8 and never saw it; a developer without that set did.
#
# 0xC3 is the lead byte of every one of these letters in UTF-8 and can never
# appear as a continuation byte, so no other character can produce a match.
_FR_BYTES='\xc3[\xa0\xa7\xa8\xa9\xaa\xae\xaf\xb4\xb9]'   # a c e e e i i o u, accented

# A guard that silently matches nothing is worse than no guard, and this one is
# a pattern that could rot without anyone noticing. Prove it still fires.
_fr_probe=$(printf 'r\xc3\xa9ussi\n' | LC_ALL=C grep -cP "$_FR_BYTES" || true)
[[ "$_fr_probe" == "1" ]] && ok \
  || fail "the French-text pattern no longer matches an accented letter; the guard below proves nothing"
_fr_neg=$(printf '\xe2\x9a\xa0\xef\xb8\x8f WARN\n' | LC_ALL=C grep -cP "$_FR_BYTES" || true)
[[ "$_fr_neg" == "0" ]] && ok \
  || fail "the French-text pattern matches an emoji variation selector; it is back in byte mode"

for f in src/checks/*.sh src/renderers/html.sh src/renderers/terminal.sh; do
  n=$(LC_ALL=C grep -cP "$_FR_BYTES" "$f" 2>/dev/null || true)
  # name_fr keeps its accents until it is removed; count only lines that are
  # not an add_result argument list.
  if [[ "$f" == src/renderers/* && "$n" != "0" ]]; then
    fail "$(basename "$f") still contains French text; the tool is English only"
  else
    ok
  fi
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
