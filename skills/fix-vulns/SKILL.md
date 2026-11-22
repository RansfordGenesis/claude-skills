---
name: fix-vulns
description: Audit and remediate vulnerable dependencies in the current repository (Dependabot alerts, npm/pnpm/yarn/bun audit findings, CVEs, GHSAs), on a dedicated branch, with before/after validation and a written report, never committing or pushing without approval. Use this whenever the user asks to fix, patch, remediate, triage or review security alerts, Dependabot alerts, vulnerable packages, "npm audit" output, a specific CVE, or a framework security advisory (e.g. a Next.js or React flaw), or says things like "fix the vulns", "upgrade X to the patched version", "clear the security alerts", even if they do not mention Dependabot by name.
---

# Dependency vulnerability remediation

The goal is to make the project measurably safer without breaking it, and to leave the user with an honest picture of what was fixed, what was not, and why. A clean audit is not the goal in itself: an alert that was dismissed, suppressed, or "fixed" by a change that does not reach the installed tree is worse than one that is openly reported as unresolved.

## Ground rules

These hold for every run unless the user explicitly says otherwise:

- Work on a dedicated branch. Never commit, push, merge, or deploy without the user's explicit approval in this conversation. Leave the changes uncommitted on the branch and say how to commit them.
- Do not make unrelated code changes. If a fix needs code changes (a breaking API in a new version), keep them minimal and call each one out in the report.
- Do not dismiss, ignore, or suppress alerts (no `audit-ci` allowlists, no `.npmrc` `audit=false`, no Dependabot dismissals) to make a report look clean.
- Only call something resolved when the installed dependency tree and a fresh audit both confirm it.
- Write the report in plain, specific language without em dashes; use commas, colons, or parentheses.

## Phase 0: Set up

1. Confirm you are in a git repo and check `git status --porcelain`. If tracked files are modified or staged, stop and ask; mixing the user's uncommitted work into a security branch makes it hard to review. Untracked files (notes, screenshots) are fine to leave in place, as long as you later stage only the files this run changed, by name, never with `git add -A` or `git add .`.
2. Check where the code actually deploys from. Run `git remote -v` and `gh repo view --json isFork,parent`: if `origin` is a fork, the site may deploy from the parent repo, and a fix merged into the fork never reaches production. Note what you find for the report.
3. Find every manifest and lockfile (monorepos have several): `package.json` + `package-lock.json` / `pnpm-lock.yaml` / `yarn.lock` / `bun.lock(b)`. Use the package manager the lockfile implies, never a different one, or you will rewrite the whole lockfile.
4. Create the branch from the current default branch: `git switch -c security/deps-YYYY-MM-DD`.
5. **Record a baseline before touching anything.** Run the project's existing test, lint, typecheck, and build scripts (whatever exists in `package.json` scripts) and save the results. Pre-existing failures are common; without a baseline you cannot tell whether the upgrade caused a failure, and you will either blame the upgrade wrongly or hide a real regression.

## Phase 1: Audit

### Collect the findings

Run `scripts/collect_alerts.sh` from this skill's directory (pass the repo path). It tries GitHub Dependabot first and falls back to the package manager's audit, printing a normalised table. Dependabot alerts are often disabled on a repo (HTTP 403 "Dependabot alerts are disabled"); in that case the local audit is the source of truth, and say so in the report along with a suggestion to enable alerts in the repo's Settings → Code security.

If both sources are available, use both: Dependabot may know about manifests the local audit skips, and the local audit reflects the actual lockfile on this branch.

### Establish facts for each vulnerability

For each finding, record: package, installed version(s), GHSA/CVE id, severity, short description, direct or transitive (and via which parent), affected range, first patched version. `npm ls <pkg> --all` (or `pnpm why`, `yarn why`) shows every installed copy and who pulls it in. A package can be installed several times at different versions; each copy counts.

### Judge real-world relevance

Do not treat every alert as equally urgent. For each one, decide whether the vulnerable code can actually be reached, and explain the reasoning in a sentence:

- **Runtime vs tooling:** is the package in the production bundle/server, or only in dev, build, or test tooling (`npm ls --omit=dev` helps)? Dev-only flaws still matter (CI, developer machines) but rarely affect visitors.
- **Feature use:** does the app use the vulnerable feature? Grep for the API named in the advisory (e.g. `next/og` `ImageResponse` fed user input, `middleware.ts` auth checks, `images` config / `remotePatterns`, a parser fed untrusted input).
- **Hosting:** where does it run? A platform can change exposure (e.g. Vercel serves Next.js image optimisation from its own service; Amplify, Fly.io, Docker, or `next start` run it in-process). Check `vercel.json`, `fly.toml`, `amplify.yml`, Dockerfiles, and deployment notes in the repo. Say when you could not confirm.
- **Input source:** can an untrusted visitor reach the vulnerable path, or only an admin or the build?

Rank: critical/high and reachable first, then critical/high unreachable, then the rest.

### Check for breaking changes before upgrading

For each planned upgrade, note whether it crosses a major version, and read the changelog or release notes for anything in between (`npm view <pkg> versions`, the package's GitHub releases). Framework packages need their companions moved in lockstep, for example `next` with `eslint-config-next` and `@next/*`, `react` with `react-dom` and `@types/react`. If the repo has an `AGENTS.md`/`CLAUDE.md` warning that a framework version differs from what you know, read the bundled docs it points to before changing code.

Do not assume a minor or patch release is safe. Security releases often add hardening that breaks existing code (for example, Next.js 16.4 made `next/og` refuse images fetched from private addresses, so an OG image loading its logo from a `localhost` URL started failing the build). The build and a runtime check are the real test; when they fail, read the framework's upgrade guide and apply the documented fix rather than switching the protection off.

## Phase 2: Remediation

Fix in priority order, and prefer the least disruptive change that actually installs a patched version:

1. **Direct dependency:** bump it to the lowest patched version in the same major if one exists, else the lowest patched major, and keep the existing pinning style (exact stays exact, `^` stays `^`).
2. **Transitive dependency:** first try upgrading the parent that pulls it in to a version that depends on a patched copy. If the parent has no such release, a targeted override is acceptable (`overrides` for npm, `pnpm.overrides`, `resolutions` for yarn), scoped as narrowly as possible, and only when the patched version satisfies, or is compatible with, the parent's declared range. List every override in the report so the user can remove it later.
3. If you use `npm audit fix` (never `--force`), run it as two separate commands: first `npm audit fix --dry-run` on its own, read the result, then the real fix. Do not chain them in one shell command, so that a failed or misparsed preview can never let the real fix run unreviewed. Afterwards, compare installed versions in the old and new lockfile and confirm `package.json` changed only where you intended.
4. Avoid `npm audit fix --force` and blanket `npm update`: they upgrade unrelated packages and can jump majors silently, which violates the "no unrelated upgrades" rule.
5. After each change, reinstall with the lockfile's package manager and confirm with `npm ls <pkg> --all` that no vulnerable copy remains.
6. If something cannot be fixed safely (no patched release, the only fix is a major that breaks the app, a peer-dependency conflict), leave it, and record why plus a concrete mitigation (config change, input validation, disabling the feature, a WAF rule, or "tooling only, low exposure").

## Phase 3: Validation

1. Re-run the same test, lint, typecheck, and build commands as the baseline and compare. A failure that matches the baseline exactly is pre-existing; any new one is a regression to fix or report.
2. Check for conflicts and deprecations: `npm ls` (look for `invalid`, `ERESOLVE`, unmet peers) and install warnings about deprecated packages. `UNMET OPTIONAL DEPENDENCY` lines for other operating systems are normal.
3. Check the lockfile still lists the native binaries for the platform the app is built on, usually Linux x64 for Vercel, Amplify, Netlify, Fly.io and most CI (for example `@img/sharp-linux-x64`, `@next/swc-linux-x64-gnu`, `lightningcss-linux-x64-gnu`). A lockfile regenerated on macOS can silently drop them, and the build then fails only in deployment.
4. Verify the app still runs where practical: start it (`npm run start` after build, or the dev server) and load a few key routes, including any that touch the upgraded feature (e.g. an image URL through the optimiser, a protected route through middleware). Stop the server afterwards.
5. Re-run the audit and `scripts/collect_alerts.sh`. Note that Dependabot alerts only close after the fix reaches the default branch, so on an unpushed branch the local audit is the evidence.
6. Show `git diff --stat` so the scope of the change is visible.

## Phase 4: Report

Present the report in chat using this structure. Keep it plain and specific; the user should be able to decide whether to approve the commit from this alone.

```
## Dependency security report: <repo> (<branch>)

**Source of findings:** Dependabot (N open alerts) / npm audit / both. <note if Dependabot was disabled>
**Hosting:** <what you found and how confident>
**Deploys from:** <origin repo, or its parent if origin is a fork>

### Vulnerabilities found
| Package | Installed | Advisory | Severity | Direct/transitive (via) | Patched in | Reachable? |

### Resolved
| Package | From → To | How (direct bump / parent bump / override) | Confirmed by |

### Not resolved
| Package | Severity | Why not | Recommended mitigation |

### Breaking changes and compatibility notes

### Validation
| Check | Baseline | After | Notes |
(tests, lint, typecheck, build, runtime smoke test, audit counts by severity)

### Follow-up
- Proposed commit message, and the commands to commit and push if the user approves (staging only the changed files by name, and pushing to the repo the site deploys from).
- Anything needing the repo owner (e.g. enabling Dependabot, an org-owned repo).
```

End by asking whether to commit, and do nothing further until the user answers.
