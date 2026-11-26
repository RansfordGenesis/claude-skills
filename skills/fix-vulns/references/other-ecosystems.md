# Other ecosystems: Go, Rust, Ruby, PHP, Java/Kotlin, .NET, containers, CI

Read the section for each ecosystem the repo uses. The phases, ground rules and report in `SKILL.md` stay the same; this file only supplies the tool commands and the pitfalls.

A universal cross-check for all of them is [osv-scanner](https://google.github.io/osv-scanner/): `osv-scanner scan source -r .` reads most lockfiles (Go, Rust, Ruby, PHP, Maven, Gradle, NuGet, Python, npm). Use the ecosystem's own tool as the primary source where one exists, because some of them (govulncheck, cargo audit) know more about reachability or yanked crates.

## Go (`go.mod`, `go.sum`)

- **Audit**: `govulncheck ./...` (run it without installing via `go run golang.org/x/vuln/cmd/govulncheck@latest ./...`). It does call-graph analysis: "Your code is affected by N vulnerabilities" lists only the ones your code can reach; the others are in modules you require but never call. Use that directly in the reachability column, and `govulncheck -show verbose ./...` for the detail.
- **Standard library findings** are fixed by a newer Go toolchain, not a module bump: raise the `go` / `toolchain` line in `go.mod`, the Go version in the Dockerfile (`FROM golang:1.xx`) and in CI.
- **Fix**: `go get <module>@v<patched>` then `go mod tidy`. For a transitive module, the same `go get` raises the minimum version (Go uses minimal version selection, so the requirement lands in `go.mod` as `// indirect`). Avoid `go get -u ./...` (upgrades everything). A major version is a different import path (`/v2`), so a major bump means code changes.
- `replace` directives in `go.mod` override everything; check them before assuming a bump took effect, and do not add one to dodge an advisory.
- **Trace**: `go mod why -m <module>`, `go mod graph | grep <module>`.
- **Validate**: `go build ./...`, `go vet ./...`, `go test ./...`, and the project's linter (`golangci-lint run`) if configured.

## Rust (`Cargo.toml`, `Cargo.lock`)

- **Audit**: `cargo audit` (install: `cargo install cargo-audit --locked`); it also flags yanked and unmaintained crates ("warning" entries). `cargo deny check advisories` if the repo already uses cargo-deny.
- **Fix**: transitive or within the declared range: `cargo update -p <crate> --precise <version>` (or `cargo update -p <crate>`). Direct beyond the range: edit `Cargo.toml`. Duplicate versions of a crate are common; `cargo tree -i <crate>` shows who pulls each one. Avoid a bare `cargo update`.
- Libraries do not ship `Cargo.lock` to users; for a library, a fix means raising the minimum version in `Cargo.toml`.
- **Validate**: `cargo build --locked`, `cargo test`, `cargo clippy` if used. Check MSRV (`rust-version` in `Cargo.toml`): a patched crate may need a newer compiler.

## Ruby (`Gemfile`, `Gemfile.lock`)

- **Audit**: `bundle-audit check --update` (install: `gem install bundler-audit`); it also checks the Ruby version in some setups. `bundle exec rails -v` and `.ruby-version` for runtime.
- **Fix**: `bundle update --conservative <gem>` updates only that gem (and only the dependencies it must). Without `--conservative`, Bundler also updates the gem's dependencies. Avoid a bare `bundle update`. Edit the `Gemfile` constraint only if it blocks the patched version.
- Rails moves as a set: `rails`, `actionpack`, `activerecord`, `activesupport`, etc. share a version; update with `bundle update --conservative rails`.
- **Validate**: `bundle exec rspec` / `bin/rails test`, `bundle exec rubocop` if used, `bin/rails runner 'puts :ok'` and a quick `bin/rails server` smoke test.

## PHP (`composer.json`, `composer.lock`)

- **Audit**: `composer audit --locked` (built into Composer 2.4+). Recent Composer versions can refuse to install packages with known advisories; do not turn that off (`audit.block-insecure`) to get an install through.
- **Fix**: `composer update <vendor/package> --with-dependencies` (or `--with-all-dependencies` if a dependency's constraint also needs to move). Preview with `--dry-run`. Avoid a bare `composer update`.
- Frameworks move as a set: Laravel `laravel/framework` with `illuminate/*`, Symfony components share a minor (`symfony/*` with `extra.symfony.require`).
- Check `config.platform.php` and the deployed PHP version before choosing a target.
- **Validate**: `composer validate`, `vendor/bin/phpunit` / `php artisan test`, `vendor/bin/phpstan` if used, `php artisan about` or a smoke request.

## Java / Kotlin (Maven `pom.xml`, Gradle `build.gradle(.kts)`)

- **Resolved tree first**: Maven `mvn -q dependency:tree -Dincludes=<groupId>:<artifactId>`; Gradle `./gradlew dependencies --configuration runtimeClasspath` and `./gradlew dependencyInsight --dependency <name> --configuration runtimeClasspath`. Without a Gradle lockfile (`gradle.lockfile`), the build file alone does not say what is used.
- **Audit**: Dependabot (if enabled), `osv-scanner scan source -r .` (reads `pom.xml` and Gradle lockfiles), or OWASP Dependency-Check (`mvn org.owasp:dependency-check-maven:check`), which is slow on first run because it downloads the NVD data.
- **Fix**: direct dependency: bump the version (often a property like `<jackson.version>`). Transitive: Maven `<dependencyManagement>` entry pinning the patched version; Gradle `constraints { implementation("g:a:ver") { because("CVE-...") } }`. Prefer bumping a BOM when the library is managed by one (Spring Boot, Jackson, Netty, AWS SDK BOMs): upgrade the BOM to a patch release instead of overriding single artifacts, so the family stays consistent.
- Spring Boot: the patched version of a managed library usually arrives in the next Spring Boot patch release; check that first.
- **Validate**: `mvn -q verify` / `./gradlew build`, and re-run `dependency:tree` to confirm the resolved version changed.

## .NET (`*.csproj`, `packages.lock.json`, `Directory.Packages.props`)

- **Audit**: `dotnet list package --vulnerable --include-transitive` (needs a restore first: `dotnet restore`). NuGet audit warnings (NU1901–NU1904) during restore show the same data; do not suppress them with `<NoWarn>` or `NuGetAuditSuppress`.
- **Fix**: direct: `dotnet add <project> package <Id> --version <patched>`. Central package management (`Directory.Packages.props` with `ManagePackageVersionsCentrally`): change the version there. Transitive: add a direct `PackageReference` (or, with central management, enable `CentralPackageTransitivePinningEnabled` and add a `PackageVersion`) at the patched version.
- If `packages.lock.json` exists, regenerate it with `dotnet restore --force-evaluate` and commit it.
- **Validate**: `dotnet build -c Release`, `dotnet test`, and a run of the app.

## Containers, CI and infrastructure

These are only in scope if the user asked for them or Dependabot reports them, but mention them in the report when they are obviously out of date.

- **Docker base images**: `docker scout cves <image>` or `trivy image <image>`. Fix by moving to a patched tag of the same base (e.g. `python:3.12-slim` rebuilt, `node:22-alpine` → current patch), and rebuild; OS packages inside the image are fixed by the base image, not by the app's lockfile.
- **GitHub Actions**: Dependabot reports vulnerable actions under the `github-actions` ecosystem. Bump the action version (ideally pinned to a full commit SHA with a version comment); check the action's release notes for input changes.
- **Terraform providers/modules**: bump the version constraint and run `terraform init -upgrade` then `terraform plan` (no `apply` without the user's approval).
