#!/usr/bin/env bash
# Dashboard guards.
#
# The dashboard is the artefact an auditor is handed, often as a single file on
# a USB stick. Three things about it can break silently:
#
#   1. It duplicates advise's wave ordering, because it has to work with no
#      shell available. Two places that must agree, with nothing checking that
#      they do, is how this repository has been bitten three times already.
#   2. `aartool report --out` injects into it and calls one function by name.
#      Rename that function and every bundled report renders an empty page,
#      with the error only in the browser console.
#   3. It must reach the network for nothing. One stray CDN link and it stops
#      working on the isolated network it exists for.
#
# Run: bash scripts/tests/test_dashboard.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
DASH=../dashboard/index.html
ADVISE=aartool-src/cmd/advise.sh

PASS=0 FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$*"; }

[[ -f "$DASH" ]] || { echo "FAIL  $DASH is missing"; exit 1; }

# ── It must not reach the network ────────────────────────────────────────────
strays=$(grep -oP '(?:src|href)\s*=\s*["'"'"'](?!data:)[^"'"'"']+' "$DASH" || true)
if [[ -z "$strays" ]]; then ok; else
  bad "the dashboard references something outside itself, so it will not work offline:"
  printf '%s\n' "$strays" | sed 's/^/        /'
fi

# ── The contract report.sh depends on ────────────────────────────────────────
grep -q 'function renderAll' "$DASH" && ok \
  || bad "renderAll() is gone; aartool report --out injects data and calls it by name, and a bundled report would render nothing"

for sym in 'const DB' 'function openDrawer' 'function render()'; do
  grep -q "$sym" "$DASH" && ok || bad "the dashboard no longer defines '$sym'"
done

# ── Remediation goes through aartool, not a raw playbook ─────────────────────
for phrase in 'aartool plan' 'aartool apply' 'aartool explain' 'aartool advise' 'aartool inspect'; do
  grep -qF "$phrase" "$DASH" && ok || bad "the dashboard never mentions '$phrase'"
done
# The host row is a button that opens everything else. Before the redesign
# nothing said so, and the drill-down was a feature you had to already know
# about. If the visible call to action goes, that regression is silent.
grep -qF 'View details' "$DASH" && ok \
  || bad "the host row has no visible 'View details' affordance; a clickable row that does not look clickable is a hidden feature"

for phrase in 'ansible-playbook' 'Ansible Remediation'; do
  if grep -qF "$phrase" "$DASH"; then
    bad "the dashboard still tells auditors to run '$phrase'; remediation goes through aartool"
  else ok; fi
done

# ── CyberAar palette ─────────────────────────────────────────────────────────
# The same tokens as cyberaar.io. An auditor who has seen the site should
# recognise this as the same product, and a score colour should mean the same
# thing in both places.
for token in '#080d1a' '#0d1526' '#00e5b0' '#f59e0b' '#ef4444' '#94a3b8'; do
  grep -qF "$token" "$DASH" && ok || bad "palette token $token missing; the dashboard has drifted from the CyberAar colours"
done

# ── The wave tables must match advise ────────────────────────────────────────
# advise.sh is the source of truth for the ordering. The dashboard mirrors it
# because it has no shell to call. Compare the ID sets rather than the syntax.
adv_decide=$(sed -n '/_advise_costly() {/,/^}/p' "$ADVISE" \
  | grep -oP '^\s+\K[A-Z]+-[0-9|A-Z-]*(?=\))' | tr '|' '\n' | grep -oP '[A-Z]+-[0-9]+' | sort -u)
dash_decide=$(sed -n "/^const DECIDE = new Set(\[/,/\]);/p" "$DASH" \
  | grep -oP "'\K[A-Z]+-[0-9]+" | sort -u)

only_adv=$(comm -23 <(printf '%s\n' "$adv_decide") <(printf '%s\n' "$dash_decide"))
only_dash=$(comm -13 <(printf '%s\n' "$adv_decide") <(printf '%s\n' "$dash_decide"))
if [[ -z "$only_adv" && -z "$only_dash" ]]; then
  ok
  printf '  decision list matches advise: %d ids\n' "$(printf '%s\n' "$adv_decide" | grep -c .)"
else
  [[ -n "$only_adv"  ]] && bad "advise treats these as needing a decision and the dashboard does not: $(echo $only_adv)"
  [[ -n "$only_dash" ]] && bad "the dashboard treats these as needing a decision and advise does not: $(echo $only_dash)"
fi

# Wave 2's explicit id list is the part most likely to drift, since the rest is
# prefix matching that reads the same in both languages.
adv_w2=$(sed -n '/_advise_wave() {/,/^}/p' "$ADVISE" \
  | grep -A2 'KRN-\*|AUTH-\*' | grep -oP 'SYS-[0-9]+|FS-[0-9]+' | sort -u)
dash_w2=$(sed -n '/title: .Account to root/,/includes(id)/p' "$DASH" \
  | grep -oP "'\K(SYS|FS)-[0-9]+" | sort -u)
missing=$(comm -23 <(printf '%s\n' "$adv_w2") <(printf '%s\n' "$dash_w2"))
if [[ -z "$missing" ]]; then ok
else bad "wave assignment drifted; advise names these and the dashboard does not: $(echo $missing)"; fi

# ── It has to actually render ────────────────────────────────────────────────
# Static checks cannot catch a runtime error in a template literal. Render the
# whole thing against a real captured report, with a stub DOM.
if command -v node >/dev/null 2>&1; then
  _js=$(mktemp --suffix=.js); trap 'rm -f "$_js"' EXIT
  sed -n '/<script>/,/<\/script>/p' "$DASH" | sed '1d;$d' > "$_js"
  if node --check "$_js" 2>/dev/null; then ok
  else bad "the dashboard's JavaScript does not parse: $(node --check "$_js" 2>&1 | head -2)"; fi

  out=$(node -e '
    const store={};
    const mk=id=>({id,_html:"",_text:"",style:{},classList:{add(){},remove(){},contains:()=>false},
      set innerHTML(v){this._html=v},get innerHTML(){return this._html},
      set textContent(v){this._text=v},get textContent(){return this._text},
      value:id==="sortSel"?"score":id==="scopeSel"?"all":"",
      addEventListener(){},focus(){},cloneNode(){return this},querySelectorAll:()=>[],
      appendChild(){},removeChild(){},setAttribute(){},select(){},remove(){}});
    global.document={getElementById:id=>(store[id]||=mk(id)),querySelectorAll:()=>[],
      querySelector:()=>mk("q"),addEventListener(){},createElement:()=>mk("t"),
      body:{style:{},appendChild(){},removeChild(){}},execCommand:()=>true};
    global.window={isSecureContext:false,print(){}}; global.navigator={};
    global.FileReader=class{}; global.alert=m=>{throw new Error("alert: "+m)};
    global.__s=store;
    const fs=require("fs");
    const js=fs.readFileSync(process.argv[1],"utf8").match(/<script>([\s\S]*)<\/script>/)[1];
    const probe=`;(function(){
      const r=JSON.parse(require("fs").readFileSync(process.argv[2],"utf8")).cyberaar_baseline;
      DB[r.host]=[r]; renderAll();
      for (const h of Object.keys(DB)) openDrawer(h);
      const all=Object.values(__s).map(e=>e._html||"").join("");
      console.log(["statRow","chains","hostBars","waveDist","catBars","heatmap","commonTbl","drawerB"]
        .map(id=>id+":"+((__s[id]&&__s[id]._html)||"").length).join(" "));
      if (!all.includes("aartool plan")) { console.log("NOCMD"); }
    })();`;
    eval(js+probe);
  ' "$DASH" tests/fixtures/audit-fixture.json 2>&1) || out="ERROR: $out"

  # ── The HTML REPORT must not reach the network either ─────────────────────
  # The dashboard was guarded from the start; the report renderer was not, and
  # for a long time every report it wrote carried
  #   <link href="https://fonts.googleapis.com/css2?family=Syne...">
  # An audit report is a list of a machine's weaknesses. Loading a stylesheet
  # from a third party hands that party the IP and referrer of whoever opens it,
  # including reports scrubbed with --anonymise precisely so they could leave
  # the estate. It also made "opens offline" untrue.
  #
  # Anchors are fine: following a link is the reader's decision. Subresources
  # are not: those are fetched whether the reader wants it or not.
  RENDERER=src/renderers/html.sh
  subres=$(grep -oPi '<(?:link|script|img|iframe|source)\b[^>]*\b(?:src|href)\s*=\s*"[^"]*"' "$RENDERER" \
           | grep -Pi '"\s*(?:https?:)?//' || true)
  cssres=$(grep -oPi '(?:@import|url\()\s*["\x27]?\s*(?:https?:)?//[^)"\x27]*' "$RENDERER" || true)
  if [[ -z "$subres" && -z "$cssres" ]]; then
    ok
  else
    bad "the HTML report loads something over the network, so it does not open offline:"
    printf '%s\n%s\n' "$subres" "$cssres" | grep -v '^$' | sed 's/^/        /'
  fi

  # ── No colour outside the token block ─────────────────────────────────────
  # The palette port replaced the hex literals and missed the same colours
  # written as rgba(): rgba(0,194,168,...) is the old teal and
  # rgba(126,211,72,...) the old lime, so borders, glows and table hovers stayed
  # off-palette and did not follow @media print. A colour in decimal is still a
  # colour outside the palette.
  #
  # Every colour must be declared in :root or @media print and used through
  # var(). Anything else is a literal somebody will forget to theme.
  # Scanned line by line over the ORIGINAL file, so a reported line number is
  # the line to open. An earlier version blanked the token blocks first and lost
  # 111 lines doing it, then still 10 after a fix, and pointed at line 173 for a
  # problem on line 255. A guard that sends you to the wrong line is only
  # slightly better than no guard.
  #
  # Skipped: the :root blocks, where colours are declared, and comments, which
  # name colours in prose and cannot reach a document.
  strays=$(perl -ne '
      if (/:root\s*\{/)      { $root = 1 }
      if ($root && /\}/)      { $root = 0; next }
      next if $root;
      if (m{/\*})            { $cmt = 1 }
      my $was = $cmt;
      if ($cmt && m{\*/})     { $cmt = 0 }
      next if $was;
      next if /^\s*#/;
      print "$.:$_" if /#[0-9a-fA-F]{3,8}\b|rgba?\([0-9]/;
    ' "$RENDERER" || true)
  if [[ -z "$strays" ]]; then ok; else
    bad "colour literals outside the token block; they cannot follow the print theme:"
    printf '%s\n' "$strays" | head -12 | sed 's/^/        /'
  fi

  # ── The report is in one language, and it is English ──────────────────────
  # It declared lang="fr" and printed CRITIQUE / FAIBLE / MOYEN as the score
  # label, either side of English check names and English remediation, and
  # computed a French check name into a variable it never rendered. That reads
  # as a bug rather than as a translation. If a French report is ever wanted it
  # should be a mode, not four leftover strings.
  lang=$(grep -oP '<html lang="\K[a-z]+' "$RENDERER" | head -1)
  [[ "$lang" == "en" ]] && ok || bad "the HTML report declares lang=\"$lang\"; its content is English"

  # The first version of this check was a denylist of five French verbs, and it
  # missed "Ajoutez --check --diff pour simuler", a French column header, and a
  # bilingual button label, all of which a reader found in the first report they
  # opened. A denylist only ever catches the words you already knew about.
  #
  # Look at the prose instead: strip CSS, JS and shell interpolation, take the
  # text a reader actually sees, and flag common French function words. Those do
  # not appear in English text, and unlike accents they survive an author
  # writing without them.
  fr_words='pour|une|dans|avec|sur|tout|toute|cette|aux|les|des|est|sont|vers|selon|ainsi|chaque|leur|entre|sans|plus|corriger|simuler|commande|fichier|serveur|noyau|mot de passe'
  # Delimiters matter here: s{...} treats } as the closing delimiter, so a
  # [^}] class inside it ends the pattern early and perl dies. The first version
  # did exactly that, printed a regex error, produced an empty $prose, and the
  # check reported ok on nothing. Hence the length assertion below.
  prose=$(perl -0777 -ne '
      s|<style.*?</style>||gs; s|<script.*?</script>||gs;   # not prose
      s|\$\{[^}]*\}| |g;                                    # shell interpolation
      s|<[^>]+>| |g;                                        # tags
      print;
    ' "$RENDERER")

  # A guard reading an empty string passes forever. Assert there is prose to
  # search before believing the search found nothing.
  if (( ${#prose} > 2000 )); then ok; else
    bad "extracted only ${#prose} characters of prose from $RENDERER; the extraction is broken, so the French check below proves nothing"
  fi

  frstr=$(printf '%s' "$prose" | grep -oiP "\\b($fr_words)\\b" | sort | uniq -c | sort -rn || true)
  if [[ -z "$frstr" ]]; then ok; else
    bad "French words appear in the report's prose, which is otherwise English:"
    printf '%s\n' "$frstr" | sed 's/^/        /'
  fi

  # The check families are the other place French reached a reader.
  frchk=$(grep -nP '"(CRITIQUE|FAIBLE|MOYEN|EXCELLENT)"|\b(Auditez|Installez|Initialisez|Corrigez|Vérifiez|Ajoutez|Configurez|Activez|Désactivez)\b' \
          src/checks/*.sh 2>/dev/null || true)
  if [[ -z "$frchk" ]]; then ok; else
    bad "French strings in check output:"
    printf '%s\n' "$frchk" | sed 's/^/        /'
  fi

  # ── The JSON root key was renamed cyberaar_baseline -> aartool ────────────
  # Both must load. The old name is in every report anybody already has on disk,
  # and a dashboard that silently ignores them shows an empty page rather than
  # an error: exactly the failure mode --redact once produced. Assert the
  # resolution the loader actually performs, not the key this fixture happens
  # to carry.
  keyprobe=$(node -e '
    const fs=require("fs");
    const doc=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
    const legacy=doc.cyberaar_baseline;
    if(!legacy) { console.log("FIXTURE-NOT-LEGACY"); process.exit(0); }
    const modern={aartool:legacy};
    const pick=j=>j.aartool||j.cyberaar_baseline;
    const a=pick(doc), b=pick(modern);
    console.log((a&&a.host?"legacy-ok":"legacy-FAIL")+" "+(b&&b.host?"modern-ok":"modern-FAIL"));
  ' tests/fixtures/audit-fixture.json 2>&1) || keyprobe="ERROR: $keyprobe"
  if [[ "$keyprobe" == "legacy-ok modern-ok" ]]; then ok; else
    bad "dashboard key resolution: want 'legacy-ok modern-ok', got '$keyprobe'"
  fi

  if [[ "$out" == ERROR:* || "$out" == *NOCMD* ]]; then
    bad "the dashboard threw while rendering a real report: ${out:0:300}"
  else
    ok
    printf '  rendered a real report: %s\n' "$out"
    empties=$(grep -oP ':\K0(?= |$)' <<<"$out" | wc -l)
    [[ "$empties" -eq 0 ]] && ok || bad "$empties dashboard panel(s) rendered empty from a real report"
  fi
else
  printf 'SKIP  node not available, render test not run\n'
fi

# ── The attack chains must match `aartool paths`, stage by stage ─────────────
# The dashboard mirrors _paths_chains because it has no shell to call. A chain
# that says one thing on the terminal and another in the panel is the same bug
# as a wave table that drifted, and this repository has been bitten by that
# before. Compare names, intros, labels, reasons and ids.
PATHS=aartool-src/cmd/paths.sh
if command -v node >/dev/null 2>&1; then
  sh_chains=$(sed -n "/cat <<'CHAINS'/,/^CHAINS/p" "$PATHS" | sed '1d;$d')
  js_chains=$(node -e '
    const fs=require("fs");
    const src=fs.readFileSync(process.argv[1],"utf8");
    const m=src.match(/const CHAINS = (\[[\s\S]*?\n\]);/);
    if(!m){console.log("NO-CHAINS");process.exit(0);}
    const C=eval(m[1]);
    for(const c of C){
      console.log(["CHAIN",c.name,c.intro].join("|"));
      for(const s of c.stages) console.log(["STAGE",s.label,s.why,s.ids.join(",")].join("|"));
    }
  ' "$DASH" 2>&1)
  # A guard comparing two empty strings passes forever.
  if (( ${#sh_chains} > 500 )); then ok; else
    bad "extracted only ${#sh_chains} characters of chain definitions from $PATHS; the extraction is broken"
  fi
  if [[ "$sh_chains" == "$js_chains" ]]; then
    ok; printf '  attack chains match paths: %d stages\n' "$(grep -c '^STAGE' <<<"$sh_chains")"
  else
    bad "the dashboard's CHAINS drifted from _paths_chains in $PATHS:"
    diff <(printf '%s\n' "$sh_chains") <(printf '%s\n' "$js_chains") | head -8 | sed 's/^/        /'
  fi

  # ── The panel says the right thing about a small estate ───────────────────
  # Two hosts built from the real fixture: the second has the MAC stage closed,
  # so "the local climb" must be complete on exactly one of the two.
  _paths_js=$(mktemp --suffix=.js)
  cat > "$_paths_js" <<'NODE'
const store={};
const mk=id=>({id,_html:"",_text:"",style:{},classList:{add(){},remove(){},contains:()=>false},
  set innerHTML(v){this._html=v},get innerHTML(){return this._html},
  set textContent(v){this._text=v},get textContent(){return this._text},
  value:id==="sortSel"?"score":id==="scopeSel"?"all":"",
  addEventListener(){},focus(){},cloneNode(){return this},querySelectorAll:()=>[],
  appendChild(){},removeChild(){},setAttribute(){},select(){},remove(){}});
global.document={getElementById:id=>(store[id]||=mk(id)),querySelectorAll:()=>[],
  querySelector:()=>mk("q"),addEventListener(){},createElement:()=>mk("t"),
  body:{style:{},appendChild(){},removeChild(){}},execCommand:()=>true};
global.window={isSecureContext:false,print(){}}; global.navigator={};
global.FileReader=class{}; global.alert=m=>{throw new Error("alert: "+m)};
const fs=require("fs");
const js=fs.readFileSync(process.argv[2],"utf8").match(/<script>([\s\S]*)<\/script>/)[1];
const base=JSON.parse(fs.readFileSync(process.argv[3],"utf8")).cyberaar_baseline;
const probe=`;(function(){
  const a=JSON.parse(JSON.stringify(base)); a.host="web-01";
  const b=JSON.parse(JSON.stringify(base)); b.host="web-02";
  b.results.forEach(r=>{ if(r.id==="SYS-04") r.status="PASS"; });
  DB["web-01"]=[a]; DB["web-02"]=[b]; renderAll();
  console.log(store.chains._html);
})();`;
eval(js+probe);
NODE
  panel=$(node "$_paths_js" "$DASH" tests/fixtures/audit-fixture.json 2>&1) || panel="ERROR: $panel"
  rm -f "$_paths_js"
  if (( ${#panel} > 500 )); then ok; else bad "the attack paths panel rendered only ${#panel} characters: ${panel:0:200}"; fi
  grep -q 'Complete on 1 of 2' <<<"$panel" && ok \
    || bad "with the MAC stage closed on one of two hosts, the local climb should read 'Complete on 1 of 2'"
  grep -q 'Complete on 2 of 2' <<<"$panel" && ok \
    || bad "a chain open on both hosts should read 'Complete on 2 of 2'"
  grep -q 'open on 1 of 2' <<<"$panel" && ok \
    || bad "the partly open stage should read 'open on 1 of 2'"
  grep -q 'needs a decision' <<<"$panel" && ok \
    || bad "the smallest-change line lost its 'needs a decision' flag"
else
  printf 'SKIP  node not available, chain tests not run\n'
fi

# ── Anonymising must not break the document it anonymises ────────────────────
# --redact is a literal global substitution over the whole JSON, and the
# report's structural keys are strings in that same document. `--redact
# cyberaar` rewrote every "cyberaar_baseline" key, the bootstrap found no
# reports, and the output was a valid HTML file showing an empty page. Valid,
# openable, and containing nothing.
if command -v node >/dev/null 2>&1 && [[ -f tests/fixtures/audit-fixture.json ]]; then
  _tmp=$(mktemp -d); trap 'rm -rf "$_tmp"' EXIT

  if bash ./aartool report tests/fixtures/audit-fixture.json --anonymise \
       --out "$_tmp/anon.html" >/dev/null 2>&1; then
    ok
    n=$(grep -c '"cyberaar_baseline"' "$_tmp/anon.html" || true)
    [[ "$n" -ge 1 ]] && ok || bad "the anonymised output lost its schema key, so it renders empty"

    data=$(sed -n '/Injected by aartool/,$p' "$_tmp/anon.html")
    if grep -q '"host":[[:space:]]*"server-' <<<"$data"; then ok
    else bad "the anonymised output did not rename the host"; fi
    if grep -q 'proof-target-01\|fixture-web-01' <<<"$data"; then
      bad "the original hostname survived anonymising"
    else ok; fi
  else
    bad "aartool report --anonymise failed on the fixture"
  fi

  # And the refusal that prevents the schema-key case entirely.
  if bash ./aartool report tests/fixtures/audit-fixture.json --anonymise \
       --redact cyberaar --out "$_tmp/bad.html" >/dev/null 2>&1; then
    bad "--redact cyberaar was accepted; it rewrites the report's own schema key and the output renders nothing"
  else ok; fi
fi

# ── Print ────────────────────────────────────────────────────────────────────
# Print-to-PDF is how an audit leaves the browser and enters an engagement
# report. The old print block hid the chrome and inverted the background, which
# produces a screenshot of a website. These assert the pieces that make it a
# document instead, because nobody prints the dashboard during development and
# a regression here would be found by a client.
grep -q '@page' "$DASH" && ok || bad "no @page rule; the PDF has no defined paper size or margins"
grep -q 'id="printCover"'    "$DASH" && ok || bad "no print cover block; the PDF would not say what was audited or when"
grep -q 'id="printFindings"' "$DASH" && ok || bad "no per-host findings section; the PDF would be a scorecard with no findings in it"
grep -q 'display: table-header-group' "$DASH" && ok \
  || bad "table headers do not repeat across pages, so columns lose their labels after the first break"

# The accent at #00e5b0 is 1.4:1 on white and unreadable printed. The light
# palette from the website is what the print block must switch to.
# grep -q closes the pipe on its first match, sed takes SIGPIPE, and under
# `set -o pipefail` the pipeline reports failure even though the match
# succeeded. Count instead of short-circuiting.
_accent=$(sed -n '/@media print/,/^    }$/p' "$DASH" | grep -c '#0F766E' || true)
if [[ "${_accent:-0}" -gt 0 ]]; then ok
else bad "print does not switch to the light-ground accent; #00e5b0 is 1.4:1 on white"; fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
