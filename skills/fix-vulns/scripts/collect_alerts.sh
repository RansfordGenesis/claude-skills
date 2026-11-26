#!/usr/bin/env bash
# Collect open vulnerability findings for a repo, across ecosystems.
# Usage: collect_alerts.sh [repo-path]
#
# 1. Prints open GitHub Dependabot alerts (if enabled and accessible).
# 2. Finds every manifest/lockfile in the repo (monorepos included) and runs
#    the matching auditor for each directory:
#      JavaScript  npm / pnpm / yarn / bun audit
#      Python      pip-audit (requirements*.txt, uv.lock, pyproject.toml),
#                  osv-scanner for poetry.lock / Pipfile.lock / pdm.lock
#      Go          govulncheck
#      Rust        cargo audit
#      Ruby        bundle-audit
#      PHP         composer audit
#      .NET        dotnet list package --vulnerable
#      Java        osv-scanner (Maven / Gradle)
# 3. Runs osv-scanner over the whole repo, if installed, as a cross-check.
#
# Missing tools are reported as MISSING with an install hint; nothing is
# installed globally. If uvx or go is available, pip-audit, govulncheck and
# osv-scanner are run through them without a permanent install.
set -u
root=$(cd "${1:-.}" && pwd) || exit 1
cd "$root" || exit 1

have() { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n== %s ==\n' "$*"; }
missing() { echo "MISSING: $1 (install: $2)"; }

# ---------------------------------------------------------------- Dependabot
section "Dependabot alerts (GitHub)"
if have gh && git remote get-url origin >/dev/null 2>&1; then
  out=$(gh api --paginate "repos/{owner}/{repo}/dependabot/alerts?state=open&per_page=100" \
    --jq '.[] | [.number, .security_advisory.severity, .dependency.package.ecosystem,
      .dependency.package.name, .dependency.manifest_path,
      .dependency.relationship // "unknown",
      .security_vulnerability.vulnerable_version_range,
      (.security_vulnerability.first_patched_version.identifier // "none"),
      .security_advisory.ghsa_id, (.security_advisory.cve_id // "-"),
      .security_advisory.summary] | @tsv' 2>&1)
  if [ $? -eq 0 ]; then
    if [ -z "$out" ]; then echo "(no open alerts)"; else
      printf '#\tseverity\tecosystem\tpackage\tmanifest\trelationship\tvulnerable\tpatched\tghsa\tcve\tsummary\n'
      echo "$out"
    fi
  else
    echo "UNAVAILABLE: $(echo "$out" | head -1)"
  fi
else
  echo "UNAVAILABLE: gh not installed or no git remote"
fi

# ------------------------------------------------------- manifest discovery
# Tracked files in a git repo (respects .gitignore), else find, skipping
# dependency and build folders either way.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  files=$(git ls-files)
else
  files=$(find . -type f | sed 's|^\./||')
fi
files=$(printf '%s\n' "$files" | grep -vE '(^|/)(node_modules|\.venv|venv|vendor|target|dist|build|\.git)/')

# Directories containing a file whose path ends in the given regex.
dirs_with() { printf '%s\n' "$files" | grep -E "(^|/)$1\$" | sed -E 's|/?[^/]*$||; s|^$|.|' | sort -u; }

# ---------------------------------------------------------------- helpers
pip_audit_cmd() {
  if have pip-audit; then echo "pip-audit"
  elif python3 -c 'import pip_audit' >/dev/null 2>&1; then echo "python3 -m pip_audit"
  elif have uvx; then echo "uvx --quiet pip-audit"
  elif have pipx; then echo "pipx run pip-audit"
  fi
}
osv_cmd() {
  if have osv-scanner; then echo "osv-scanner"
  elif have go; then echo "go run github.com/google/osv-scanner/v2/cmd/osv-scanner@latest"
  fi
}

# Audit a fully pinned requirements file without installing anything.
pip_audit_pinned() {
  err=$(mktemp)
  $pa -r "$1" --no-deps --disable-pip -f json 2>"$err" | fmt_pip_audit
  grep -qiE 'error|traceback' "$err" && { echo "pip-audit stderr:"; tail -n 5 "$err"; }
  rm -f "$err"
}
# Resolve an unpinned requirements file or pyproject.toml, then audit it.
# Uses uv's resolver when present (no virtualenv needed); otherwise lets
# pip-audit resolve in a temporary virtualenv.
audit_resolved() {
  if have uv; then
    tmp=$(mktemp)
    extra=""; [ "$(basename "$1")" = pyproject.toml ] && extra="--all-extras"
    if uv pip compile "$1" $extra --no-header --no-annotate -q -o "$tmp" 2>/dev/null; then
      echo "(resolved with uv pip compile$( [ -n "$extra" ] && echo ", all extras" ))"
      pip_audit_pinned "$tmp"
    else
      echo "uv could not resolve $1:"; uv pip compile "$1" $extra -q 2>&1 | tail -n 5
    fi
    rm -f "$tmp"
  else
    err=$(mktemp)
    if [ "$(basename "$1")" = pyproject.toml ]; then $pa . -f json 2>"$err" | fmt_pip_audit
    else $pa -r "$1" -f json 2>"$err" | fmt_pip_audit; fi
    grep -qiE 'error|traceback' "$err" && { echo "pip-audit stderr:"; tail -n 5 "$err"; }
    rm -f "$err"
  fi
}

# pip-audit JSON on stdin -> table
fmt_pip_audit() {
  python3 -c '
import json, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw[raw.index("{"):])
except Exception:
    print("pip-audit produced no JSON:", raw.strip()[:1500] or "(empty)"); sys.exit(0)
deps = d.get("dependencies", [])
skipped = [x for x in deps if x.get("skip_reason")]
rows, seen = [], set()
for x in deps:
    for v in x.get("vulns", []):
        key = (x["name"].lower(), x.get("version"), v.get("id"))
        if key not in seen:
            seen.add(key); rows.append((x["name"], x.get("version", "?"), v))
print("packages scanned: %d, skipped: %d, findings: %d" % (len(deps), len(skipped), len(rows)))
for x in skipped[:10]:
    print("  skipped %s: %s" % (x["name"], x["skip_reason"][:100]))
if rows:
    print("package\tinstalled\tadvisory\taliases\tfixed in\tsummary")
for name, ver, v in rows:
    print("\t".join([name, ver, v.get("id", "?"), ",".join(v.get("aliases", [])) or "-",
                     ",".join(v.get("fix_versions", [])) or "none",
                     (v.get("description") or "").replace("\n", " ")[:90]]))
'
}

# ---------------------------------------------------------------- JavaScript
audit_js() {
  cd "$1" || return
  locks=$(ls package-lock.json npm-shrinkwrap.json pnpm-lock.yaml yarn.lock bun.lock bun.lockb 2>/dev/null | tr '\n' ' ')
  if   [ -f pnpm-lock.yaml ]; then pm=pnpm
  elif [ -f yarn.lock ];      then pm=yarn
  elif [ -f bun.lock ] || [ -f bun.lockb ]; then pm=bun
  elif [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then pm=npm
  else echo "package.json without a lockfile here (a workspace member, or the audit is not reproducible)"; return; fi
  [ "$(echo $locks | wc -w)" -gt 1 ] && echo "NOTE: several lockfiles here ($locks). Fix every one that CI or the host installs from."
  echo "package manager: $pm"
  if [ "$pm" = npm ] || [ -f package-lock.json ]; then
    [ "$pm" = npm ] || echo "-- package-lock.json (npm) --"
    have npm || { missing npm "install Node.js"; return; }
    npm audit --package-lock-only --json 2>/dev/null | node -e '
      const a = JSON.parse(require("fs").readFileSync(0, "utf8"));
      const m = a.metadata?.vulnerabilities || {};
      console.log("totals:", JSON.stringify(m));
      console.log(["severity","package","direct","range","fixAvailable","advisories"].join("\t"));
      const order = {critical:0, high:1, moderate:2, low:3, info:4};
      Object.values(a.vulnerabilities || {})
        .sort((x, y) => order[x.severity] - order[y.severity])
        .forEach(v => {
          const adv = v.via.map(x => typeof x === "string" ? "via " + x
            : (x.url || "").split("/").pop() + " " + x.title).join(" | ");
          const fix = v.fixAvailable === true ? "yes"
            : v.fixAvailable ? `${v.fixAvailable.name}@${v.fixAvailable.version}${v.fixAvailable.isSemVerMajor ? " (MAJOR)" : ""}` : "no";
          console.log([v.severity, v.name, v.isDirect ? "direct" : "transitive", v.range, fix, adv].join("\t"));
        });'
    echo "-- production-only totals (npm audit --omit=dev) --"
    npm audit --package-lock-only --omit=dev --json 2>/dev/null | node -e '
      const a = JSON.parse(require("fs").readFileSync(0, "utf8"));
      console.log(JSON.stringify(a.metadata?.vulnerabilities || {}));'
  fi
  if [ "$pm" != npm ]; then
    echo "-- $pm lockfile --"
    case $pm in
      pnpm) if have pnpm; then pnpm audit; else missing pnpm "corepack enable"; fi ;;
      yarn) if have yarn; then yarn npm audit --all --recursive 2>/dev/null || yarn audit; else missing yarn "corepack enable"; fi ;;
      bun)  if have bun; then bun audit; else missing bun "https://bun.sh"; fi ;;
    esac
  fi
}

# ---------------------------------------------------------------- Python
audit_python() {
  cd "$1" || return
  pa=$(pip_audit_cmd); osv=$(osv_cmd); covered=0
  if [ -f uv.lock ]; then
    covered=1; echo "source: uv.lock (uv export, then pip-audit)"
    if ! have uv; then missing uv "https://docs.astral.sh/uv/"
    elif [ -z "$pa" ]; then missing pip-audit "uv tool install pip-audit, or pipx install pip-audit"
    else
      tmp=$(mktemp)
      uv export --frozen --format requirements-txt --no-hashes --no-emit-project --all-groups -q > "$tmp" 2>/dev/null \
        || uv export --frozen --format requirements-txt --no-hashes --no-emit-project -q > "$tmp"
      pip_audit_pinned "$tmp"; rm -f "$tmp"
    fi
  fi
  for lock in poetry.lock Pipfile.lock pdm.lock; do
    [ -f "$lock" ] || continue
    covered=1; echo "source: $lock (osv-scanner)"
    if [ -n "$osv" ]; then $osv scan source --lockfile "$lock" 2>&1
    else missing osv-scanner "brew install osv-scanner, or go install github.com/google/osv-scanner/v2/cmd/osv-scanner@latest"; fi
  done
  for r in requirements*.txt requirements/*.txt; do
    [ -f "$r" ] || continue
    covered=1; echo "source: $r (pip-audit)"
    if [ -z "$pa" ]; then missing pip-audit "pipx install pip-audit, or uv tool install pip-audit"; continue; fi
    if grep -vE '^[[:space:]]*(#|-|$)' "$r" | grep -qvE '==|@ '; then
      echo "NOTE: $r has unpinned lines; they are resolved to today's versions, which may differ from what is deployed."
    fi
    # Resolve even pinned files: a file that pins only direct packages would
    # otherwise hide every transitive one. Existing pins are kept as-is.
    audit_resolved "$r"
  done
  if [ $covered -eq 0 ] && [ -f pyproject.toml ]; then
    echo "source: pyproject.toml without a lockfile (resolved to today's versions; not reproducible)"
    if [ -n "$pa" ]; then audit_resolved pyproject.toml; else missing pip-audit "pipx install pip-audit"; fi
  fi
}

# ---------------------------------------------------------------- others
audit_go() {
  cd "$1" || return
  if have govulncheck; then govulncheck ./... 2>&1
  elif have go; then go run golang.org/x/vuln/cmd/govulncheck@latest ./... 2>&1
  else missing govulncheck "go install golang.org/x/vuln/cmd/govulncheck@latest"; fi
}
audit_rust() {
  cd "$1" || return
  if have cargo && cargo audit --version >/dev/null 2>&1; then cargo audit 2>&1
  else missing cargo-audit "cargo install cargo-audit --locked"; fi
}
audit_ruby() {
  cd "$1" || return
  if have bundle-audit; then bundle-audit check --update 2>&1
  elif have bundler-audit; then bundler-audit check --update 2>&1
  else missing bundler-audit "gem install bundler-audit"; fi
}
audit_php() {
  cd "$1" || return
  if have composer; then composer audit --locked --format=table 2>&1
  else missing composer "https://getcomposer.org"; fi
}
audit_dotnet() {
  cd "$1" || return
  if have dotnet; then dotnet list package --vulnerable --include-transitive 2>&1
  else missing dotnet "https://dotnet.microsoft.com/download"; fi
}
audit_java() {
  cd "$1" || return
  osv=$(osv_cmd)
  if [ -n "$osv" ]; then $osv scan source -r . 2>&1 | tail -n 60
  else missing osv-scanner "brew install osv-scanner"; fi
  echo "Resolved tree: mvn dependency:tree (Maven) or ./gradlew dependencies (Gradle); Gradle builds without a lockfile can only be audited after resolution."
}

# ---------------------------------------------------------------- run
found=0
run_each() { # ecosystem fn  (directories on stdin)
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    found=1; section "$1: $d"; ( "$2" "$root/$d" )
  done
}
run_each JavaScript audit_js < <(dirs_with 'package\.json')
run_each Python audit_python < <( { dirs_with 'requirements[^/]*\.txt'; dirs_with 'pyproject\.toml'; \
    dirs_with 'uv\.lock'; dirs_with 'poetry\.lock'; dirs_with 'Pipfile\.lock'; dirs_with 'pdm\.lock'; } \
    | sed -E 's#(^|/)requirements$##; s#^$#.#' | sort -u)
run_each Go audit_go < <(dirs_with 'go\.mod')
run_each Rust audit_rust < <(dirs_with 'Cargo\.lock')
run_each Ruby audit_ruby < <(dirs_with 'Gemfile\.lock')
run_each PHP audit_php < <(dirs_with 'composer\.lock')
run_each .NET audit_dotnet < <(dirs_with '[^/]*\.(csproj|fsproj|vbproj)' )
run_each Java audit_java < <( { dirs_with 'pom\.xml'; dirs_with 'build\.gradle(\.kts)?'; } | sort -u)
if [ $found -eq 0 ]; then section "Local audit"; echo "No supported manifest found under $root"; fi

# ------------------------------------------------------------ cross-check
section "osv-scanner (whole repo cross-check)"
if have osv-scanner; then osv-scanner scan source -r . 2>&1 | tail -n 60
else echo "skipped: osv-scanner not installed (optional: brew install osv-scanner)"; fi
