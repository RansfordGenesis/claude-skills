#!/usr/bin/env bash
# Collect open vulnerability findings for a repo.
# Usage: collect_alerts.sh [repo-path]
# Prints Dependabot alerts (if enabled and accessible) and the local
# package-manager audit, each as a tab-separated table.
set -u
cd "${1:-.}" || exit 1

echo "== Dependabot alerts (GitHub) =="
if command -v gh >/dev/null && git remote get-url origin >/dev/null 2>&1; then
  out=$(gh api --paginate "repos/{owner}/{repo}/dependabot/alerts?state=open&per_page=100" \
    --jq '.[] | [.number, .security_advisory.severity, .dependency.package.name,
      .dependency.manifest_path, .dependency.relationship // "unknown",
      .security_vulnerability.vulnerable_version_range,
      (.security_vulnerability.first_patched_version.identifier // "none"),
      .security_advisory.ghsa_id, (.security_advisory.cve_id // "-"),
      .security_advisory.summary] | @tsv' 2>&1)
  if [ $? -eq 0 ]; then
    if [ -z "$out" ]; then echo "(no open alerts)"; else
      printf '#\tseverity\tpackage\tmanifest\trelationship\tvulnerable\tpatched\tghsa\tcve\tsummary\n'
      echo "$out"
    fi
  else
    echo "UNAVAILABLE: $(echo "$out" | head -1)"
  fi
else
  echo "UNAVAILABLE: gh not installed or no git remote"
fi

echo
echo "== Local audit =="
if   [ -f pnpm-lock.yaml ]; then pm=pnpm
elif [ -f yarn.lock ];      then pm=yarn
elif [ -f bun.lock ] || [ -f bun.lockb ]; then pm=bun
elif [ -f package-lock.json ]; then pm=npm
else echo "No JS lockfile found at $(pwd)"; exit 0; fi
echo "package manager: $pm"

if [ "$pm" = npm ]; then
  npm audit --json 2>/dev/null | node -e '
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
  echo
  echo "-- production-only totals (npm audit --omit=dev) --"
  npm audit --omit=dev --json 2>/dev/null | node -e '
    const a = JSON.parse(require("fs").readFileSync(0, "utf8"));
    console.log(JSON.stringify(a.metadata?.vulnerabilities || {}));'
else
  case $pm in
    pnpm) pnpm audit ;;
    yarn) yarn npm audit --all --recursive 2>/dev/null || yarn audit ;;
    bun)  bun audit ;;
  esac
fi
