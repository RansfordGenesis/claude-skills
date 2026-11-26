# JavaScript and TypeScript (npm, pnpm, Yarn, Bun)

Read this when the repo has a `package.json`.

## Package manager and lockfiles

- Use the package manager the lockfile implies: `package-lock.json` → npm, `pnpm-lock.yaml` → pnpm, `yarn.lock` → Yarn, `bun.lock`/`bun.lockb` → Bun. Using a different one rewrites the whole lockfile.
- **More than one lockfile in the same folder** (common after a switch of tools): find out which one CI and the host install from (workflow files, `vercel.json`, Dockerfile, `packageManager` in `package.json`), and keep every lockfile that is used in step. npm ignores Yarn's `resolutions` and Yarn ignores npm's `overrides`, so a pin has to be written in both formats. npm 7+ updates an existing `yarn.lock` when it installs, but only for the versions it resolved; regenerate `yarn.lock` with the Yarn version named in `packageManager` (`corepack yarn install`) to be sure.
- Yarn 1's `--frozen-lockfile` can pass while a plain `yarn install` still changes the lockfile. To confirm Yarn agrees, run a normal install in a scratch copy and check that `yarn.lock` is unchanged.
- **Workspaces/monorepos**: run commands from the root, target a member with `-w <name>` (npm) or `--filter` (pnpm). An `ERESOLVE` peer conflict in one workspace can block `npm audit fix` for the whole repo; then update the named vulnerable packages within their ranges (`npm update <pkg> <pkg> ...`, never a bare `npm update`), after a `--dry-run` of the same command.
- Check the user's npm config: with `save-exact=true` (`npm config get save-exact`), `npm install pkg@^1.2.3` writes `1.2.3`. Restore the repo's existing range style in `package.json` by hand and reinstall so the lockfile matches.

## Tracing findings

- `npm ls <pkg> --all` (or `pnpm why <pkg>`, `yarn why <pkg>`) shows every installed copy and who pulls it in. Each copy counts.
- `npm audit --omit=dev` separates production packages from tooling.
- `npm view <pkg> versions --json` and `npm view <pkg>@<version> peerDependencies` before choosing a target.

## Fixing

1. **Direct dependency**: bump to the lowest patched version in the same major if one exists, keeping the pinning style (exact stays exact, `^` stays `^`).
2. **Transitive dependency**: first upgrade the parent to a release that depends on a patched copy. Otherwise a narrow override: `overrides` (npm), `pnpm.overrides`, `resolutions` (Yarn), only when the patched version satisfies, or is compatible with, the parent's declared range. List every override in the report.
3. **`npm audit fix`** (never `--force`): run `npm audit fix --dry-run` as its own command, read it, then the real fix as a separate command. Never chain them, so a failed or misparsed preview cannot let the real fix run unreviewed. Run it until it reaches a fixed point: a second pass often moves packages the first pass unblocked (e.g. `typescript-eslint`). Afterwards compare installed versions in the old and new lockfile, and confirm `package.json` changed only where you intended.
4. Never `npm audit fix --force` or a blanket `npm update`: both jump majors and upgrade unrelated packages.
5. After each change, reinstall with the lockfile's manager and confirm with `npm ls <pkg> --all` that no vulnerable copy remains.

## Framework companions

Move these in lockstep: `next` with `eslint-config-next` and `@next/*`; `react` with `react-dom` and `@types/react`/`@types/react-dom`; `vite` with `@vitejs/plugin-*` (check their `peerDependencies`) and `vitest` (vitest 4 needs vite 6+); `expo` with `expo-*` packages (a new Expo SDK is a major upgrade, use `npx expo install --fix`). If the repo has an `AGENTS.md`/`CLAUDE.md` warning that a framework version differs from what you know, read the docs it points to first.

Security releases can add hardening that breaks working code. For example, Next.js 16.4 made `next/og` refuse images fetched from private addresses, so an OG image that loaded its logo from a `localhost` URL failed the build. The fix was to read the file from disk (`readFile(join(process.cwd(), "public/..."))`) rather than switching the protection off.

## Reachability hints

- Next.js: check `middleware.ts`/`proxy.ts` auth logic, `next/og` `ImageResponse` fed user input, `images` config and `remotePatterns`, Server Actions. On Vercel, image optimisation runs on Vercel's own service, so optimiser flaws mostly do not apply; Amplify, Fly.io, Docker and `next start` run it in-process.
- PostCSS copies bundled inside `next` only process your own CSS at build time.
- Vite, esbuild and Vitest flaws affect the dev server or a running Vitest UI, not production bundles.

## Validation specifics

- Scripts to run: whatever exists among `typecheck`, `lint`, `test`, `build` in `package.json`.
- Builds that need env vars: copy the user's existing gitignored `.env.local` into the working copy (never stage it). If fonts or other network fetches time out, retry builds one at a time before blaming the upgrade.
- `npm ls` for `invalid`, `ERESOLVE`, unmet peers. `UNMET OPTIONAL DEPENDENCY` for other operating systems is normal.
- **Native binaries**: check the lockfile still lists the binaries for the build platform, usually Linux x64 (Vercel, Amplify, Netlify, Fly.io, most CI): `@img/sharp-linux-x64`, `@next/swc-linux-x64-gnu`, `lightningcss-linux-x64-gnu`, `@rollup/rollup-linux-x64-gnu` or `@rolldown/binding-linux-x64-gnu`, `@esbuild/linux-x64`. Compare against the old lockfile; a lockfile regenerated on macOS can silently drop them. A swap between equivalents (esbuild/Rollup → Rolldown after a Vite 8 upgrade) is fine.
- Runtime: `npm run build && npm run start`, then load key routes and anything touching the upgraded feature.
