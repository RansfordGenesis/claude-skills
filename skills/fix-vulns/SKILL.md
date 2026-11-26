---
name: fix-vulns
description: Audit and remediate vulnerable dependencies in the current repository, in any ecosystem (JavaScript/TypeScript via npm, pnpm, Yarn or Bun; Python via pip, uv, Poetry, Pipenv or PDM; Go, Rust, Ruby, PHP, Java/Kotlin, .NET), on a dedicated branch, with before/after validation and a written report, never committing or pushing without approval. Use this whenever the user asks to fix, patch, remediate, triage or review security alerts, Dependabot alerts, vulnerable packages, "npm audit" or "pip-audit" output, a specific CVE or GHSA, or a framework security advisory (e.g. a Next.js, Django or FastAPI flaw), or says things like "fix the vulns", "upgrade X to the patched version", "clear the security alerts", "check the backend dependencies", even if they do not mention Dependabot by name.
---

# Dependency vulnerability remediation

The goal is to make the project measurably safer without breaking it, and to leave the user with an honest picture of what was fixed, what was not, and why. A clean audit is not the goal in itself: an alert that was dismissed, suppressed, or "fixed" by a change that does not reach the installed tree is worse than one that is openly reported as unresolved.

## Ecosystem guides

The phases below apply to every ecosystem. The commands differ, so for each ecosystem the repo uses, read its guide before Phase 1:

| Repo contains | Read |
|---|---|
| `package.json` | `references/javascript.md` |
| `requirements*.txt`, `pyproject.toml`, `uv.lock`, `poetry.lock`, `Pipfile.lock`, `pdm.lock`, `setup.py` | `references/python.md` |
| `go.mod`, `Cargo.lock`, `Gemfile.lock`, `composer.lock`, `pom.xml`, `build.gradle(.kts)`, `*.csproj`, Dockerfiles, workflow files | `references/other-ecosystems.md` (the matching section) |

Full-stack repos usually have more than one (a JavaScript frontend and a Python backend, a Lambda folder, infrastructure code). Treat each manifest directory as its own unit with its own baseline, fixes and validation, and report them together.

## Ground rules

These hold for every run unless the user explicitly says otherwise:

- Work on a dedicated branch. Never commit, push, merge, or deploy without the user's explicit approval in this conversation. Leave the changes uncommitted on the branch and say how to commit them.
- Do not make unrelated code changes. If a fix needs code changes (a breaking API in a new version), keep them minimal and call each one out in the report.
- Do not dismiss, ignore, or suppress alerts to make a report look clean: no audit allowlists or ignore files (`audit-ci` allowlists, `.npmrc` `audit=false`, `pip-audit --ignore-vuln`, `cargo audit --ignore`, `.bundler-audit.yml` ignores, `<NoWarn>` for NuGet audit, Composer `audit.ignore`), no Dependabot dismissals.
- Upgrade only what a finding requires. Never run a blanket update (`npm update`, `npm audit fix --force`, `uv lock --upgrade`, `poetry update`, `bundle update`, `composer update`, `go get -u ./...`, `cargo update`) with no package named.
- Only call something resolved when the installed dependency tree and a fresh audit both confirm it.
- Write the report in plain, specific language without em dashes; use commas, colons, or parentheses.

## Phase 0: Set up

1. Confirm you are in a git repo and check `git status --porcelain`. If tracked files are modified or staged, stop and ask; mixing the user's uncommitted work into a security branch makes it hard to review. Untracked files (notes, screenshots) are fine to leave in place, as long as you later stage only the files this run changed, by name, never with `git add -A` or `git add .`.
   - If the user is on a feature branch or has local changes and you are working on several repos, a separate working copy avoids disturbing them: `git worktree add -b security/deps-YYYY-MM-DD /tmp/<repo> origin/<default>`. Copy any gitignored env files the build needs into it (never stage them).
2. Check where the code actually deploys from. Run `git remote -v` and `gh repo view --json isFork,parent`: if `origin` is a fork, the site may deploy from the parent repo, and a fix merged into the fork never reaches production. Note what you find for the report.
3. Find every manifest and lockfile (monorepos and full-stack repos have several; `scripts/collect_alerts.sh` lists them). Use the tool each lockfile implies, never a different one, or you will rewrite the whole lockfile. The ecosystem guide says which tool goes with which file.
4. Create the branch from the current default branch: `git switch -c security/deps-YYYY-MM-DD`.
5. **Record a baseline before touching anything.** For each unit, run the project's existing test, lint, typecheck, and build commands (from `package.json` scripts, `Makefile`, `pyproject.toml`/`tox.ini`/`noxfile.py`, CI workflow files, or the ecosystem's standard commands in its guide) and save the results. Pre-existing failures are common; without a baseline you cannot tell whether the upgrade caused a failure, and you will either blame the upgrade wrongly or hide a real regression. If a baseline fails for an environmental reason (missing env file, network timeout, parallel builds competing), fix the environment and re-run it before recording it.

## Phase 1: Audit

### Collect the findings

Run `scripts/collect_alerts.sh` from this skill's directory (pass the repo path). It prints open GitHub Dependabot alerts, then finds every manifest in the repo and runs the matching auditor per directory (npm/pnpm/Yarn/Bun audit, pip-audit, govulncheck, cargo audit, bundle-audit, composer audit, dotnet, osv-scanner). When an auditor is not installed it prints `MISSING` with an install hint; it never installs anything globally, but runs pip-audit, govulncheck and osv-scanner through `uvx` or `go run` when those are available. If a tool is missing and the ecosystem matters, ask the user before installing it.

Dependabot alerts are often disabled on a repo (HTTP 403 "Dependabot alerts are disabled"); in that case the local audit is the source of truth, and say so in the report along with a suggestion to enable alerts in the repo's Settings → Code security. If both sources are available, use both: Dependabot may know about manifests the local audit skips, and the local audit reflects the actual lockfile on this branch.

When a manifest is not fully pinned (an unpinned `requirements.txt`, a `pyproject.toml` with no lockfile, a Gradle build without a lockfile), the audit reflects what would be installed today, not necessarily what is deployed. Say which you audited.

### Establish facts for each vulnerability

For each finding, record: ecosystem, package, installed version(s), advisory id (GHSA, CVE, PYSEC, RUSTSEC, GO-…), severity, short description, direct or transitive (and via which parent), affected range, first patched version. Each ecosystem guide lists the command that shows who pulls a package in. A package can be installed several times at different versions; each copy counts.

### Judge real-world relevance

Do not treat every alert as equally urgent. For each one, decide whether the vulnerable code can actually be reached, and explain the reasoning in a sentence:

- **Runtime vs tooling:** is the package in the production bundle, server, image or function, or only in dev, build, test or infrastructure tooling? Dev-only flaws still matter (CI, developer machines) but rarely affect visitors.
- **Feature use:** does the app use the vulnerable feature? Grep for the API named in the advisory (a parser fed untrusted input, a middleware auth check, a multipart upload handler, an image or PDF library fed uploads). Some tools answer this directly: `govulncheck` reports which findings your code actually calls.
- **Hosting:** where does it run? A platform can change exposure (e.g. Vercel serves Next.js image optimisation from its own service; Amplify, Fly.io, Docker, or `next start` run it in-process; a Lambda behind API Gateway sees only what the gateway passes). Check `vercel.json`, `fly.toml`, `amplify.yml`, Dockerfiles, `serverless.yml`, `template.yaml` (SAM), CDK/Terraform code and deployment notes in the repo. Say when you could not confirm.
- **Input source:** can an untrusted visitor reach the vulnerable path, or only an admin or the build?

Rank: critical/high and reachable first, then critical/high unreachable, then the rest.

### Check for breaking changes before upgrading

For each planned upgrade, note whether it crosses a major version, and read the changelog or release notes for anything in between (the registry's version list, the package's GitHub releases). Framework packages need their companions moved in lockstep; each ecosystem guide lists the usual sets. Also check the runtime: a patched release may need a newer language version (Node, Python, Go, Rust MSRV, PHP, .NET), so compare against the version the app is deployed on.

Do not assume a minor or patch release is safe. Security releases often add hardening that breaks existing code (for example, Next.js 16.4 made `next/og` refuse images fetched from private addresses, so an OG image loading its logo from a `localhost` URL started failing the build). The build and a runtime check are the real test; when they fail, read the framework's upgrade guide and apply the documented fix rather than switching the protection off.

## Phase 2: Remediation

Fix in priority order, and prefer the least disruptive change that actually installs a patched version:

1. **Direct dependency:** bump it to the lowest patched version in the same major if one exists, else the lowest patched major, and keep the existing pinning style (exact stays exact, a range stays a range).
2. **Transitive dependency:** first try upgrading the parent that pulls it in to a version that depends on a patched copy, or updating only that package within the parent's declared range. If neither works, a targeted override or constraint is acceptable (the guide names the mechanism for each tool), scoped as narrowly as possible, and only when the patched version satisfies, or is compatible with, the parent's declared range. List every override in the report so the user can remove it later.
3. Preview before applying wherever the tool supports it (`--dry-run`), as a separate command from the real change, so a failed or misparsed preview can never let the real change run unreviewed. Afterwards, diff the lockfile and confirm the manifest changed only where you intended.
4. After each change, reinstall from the lockfile and confirm with the ecosystem's tree command that no vulnerable copy remains.
5. If something cannot be fixed safely (no patched release, the only fix is a major that breaks the app, a peer-dependency conflict, a new runtime version the host does not offer), leave it, and record why plus a concrete mitigation (config change, input validation or size limits, disabling the feature, replacing an unmaintained library, a WAF rule, or "tooling only, low exposure").

## Phase 3: Validation

1. Re-run the same test, lint, typecheck, and build commands as the baseline and compare. A failure that matches the baseline exactly is pre-existing; any new one is a regression to fix or report.
2. Check for conflicts and deprecations with the ecosystem's checker (`npm ls`, `pip check`/`uv pip check`, `go mod verify`, `cargo tree -d`, `composer validate`, `dotnet restore` warnings) and install warnings about deprecated packages.
3. Check the lockfile still resolves for the platform the app is built and run on, usually Linux x64 or arm64 (Vercel, Amplify, Netlify, Fly.io, Docker, Lambda, most CI): native binaries for JavaScript, `manylinux` wheels for Python. A lockfile regenerated on macOS can silently drop them, and the build then fails only in deployment. The guides say what to look for.
4. Verify the app still runs where practical: start it and load a few key routes or invoke a handler, including any that touch the upgraded feature (an image through the optimiser, a protected route through middleware, a file upload, a PDF export). Stop the server afterwards.
5. Re-run the audit and `scripts/collect_alerts.sh`. Note that Dependabot alerts only close after the fix reaches the default branch, so on an unpushed branch the local audit is the evidence.
6. Show `git diff --stat` so the scope of the change is visible.

## Phase 4: Report

Present the report in chat using this structure. Keep it plain and specific; the user should be able to decide whether to approve the commit from this alone. For a repo with several units (frontend, backend, infrastructure), keep one report with an ecosystem column rather than one report per unit.

```
## Dependency security report: <repo> (<branch>)

**Source of findings:** Dependabot (N open alerts) / local audit (<tools used>) / both. <note if Dependabot was disabled, a tool was missing, or a manifest was not pinned>
**Hosting:** <what you found and how confident>
**Deploys from:** <origin repo, or its parent if origin is a fork>

### Vulnerabilities found
| Ecosystem | Package | Installed | Advisory | Severity | Direct/transitive (via) | Patched in | Reachable? |

### Resolved
| Ecosystem | Package | From → To | How (direct bump / parent bump / override) | Confirmed by |

### Not resolved
| Ecosystem | Package | Severity | Why not | Recommended mitigation |

### Breaking changes and compatibility notes

### Validation
| Unit | Check | Baseline | After | Notes |
(tests, lint, typecheck, build, runtime smoke test, audit counts by severity)

### Follow-up
- Proposed commit message, and the commands to commit and push if the user approves (staging only the changed files by name, and pushing to the repo the site deploys from).
- Anything needing the repo owner (e.g. enabling Dependabot, an org-owned repo, installing an auditor).
```

End by asking whether to commit, and do nothing further until the user answers.
