# claude-skills

Open-source skills for [Claude Code](https://claude.com/claude-code) and other agent CLIs that read the [Agent Skills](https://agentskills.io/specification) format. Each skill lives in its own folder under [`skills/`](skills) and can be installed on its own. Free to use, adapt and share under the [MIT license](LICENSE).

## Skills

| Skill | What it does |
|---|---|
| [fix-vulns](#fix-vulns) | Audits and fixes vulnerable dependencies in JavaScript, Python, Go, Rust, Ruby, PHP, Java and .NET projects |
| [ghana-data-protection-policies](#ghana-data-protection-policies) | Drafts and audits privacy policies, terms and cookie policies under Ghana's Data Protection Act |

### [fix-vulns](skills/fix-vulns/SKILL.md)

Audits and fixes vulnerable dependencies in a project, in whichever ecosystems it uses: JavaScript/TypeScript (npm, pnpm, Yarn, Bun), Python (pip, uv, Poetry, Pipenv, PDM), Go, Rust, Ruby, PHP, Java/Kotlin and .NET. Full-stack repos with, say, a JavaScript frontend and a Python backend are handled together. It reads the repo's open Dependabot alerts from GitHub when they are enabled, and runs each ecosystem's own auditor too (`npm audit`, `pip-audit`, `govulncheck`, `cargo audit`, `bundle-audit`, `composer audit`, `dotnet list package --vulnerable`, with `osv-scanner` as a cross-check). For each finding it works out whether the vulnerable code can actually be reached in production, based on whether the package ships to users, whether the app uses the affected feature, and where it is hosted, then applies the smallest upgrade that installs a patched version.

It works on a dedicated branch, records the project's test, lint, typecheck and build results before changing anything so pre-existing failures are not blamed on the upgrade, re-runs them afterwards, smoke-tests the running app, and ends with a report of what was fixed, what was not and why. It never commits, pushes, merges, dismisses alerts or forces upgrades without your approval.

**Example prompts**, asked from inside the project:

- "Fix the Dependabot alerts in this repo."
- "npm audit shows two criticals. Patch what's safe to patch and tell me what's left."
- "There's a new Next.js security advisory. Are we affected, and can you upgrade us?"
- "Check the Python backend's dependencies for known vulnerabilities and fix them."

**Needs:** `git` and the project's own package manager(s). For Python, [`pip-audit`](https://github.com/pypa/pip-audit) (used through `uvx` or `pipx` if it is not installed); for other ecosystems, their auditor (the skill says which one is missing and how to install it, and asks before installing anything). [`osv-scanner`](https://google.github.io/osv-scanner/) is an optional extra cross-check. The [GitHub CLI](https://cli.github.com) (`gh`, logged in) is optional; without it, or when Dependabot alerts are disabled on the repo, the skill falls back to the local audit. It only reads alerts from GitHub and never writes to it.

### [ghana-data-protection-policies](skills/ghana-data-protection-policies/SKILL.md)

Writes and audits privacy policies, terms of service, and cookie policies for products processing personal data in Ghana, so they conform to the Data Protection Act, 2012 (Act 843). It scans the target codebase for what data is actually collected before drafting, distills the Act into a section-cited reference, and enforces plain English with no em dashes.

**Example prompts**, asked from inside the project you want a policy for:

- "Write a privacy policy for this app that complies with Ghana's Data Protection Act, Act 843."
- "We take payments and run analytics here. Draft a privacy policy, terms of service, and cookie policy for it."
- "Audit our current privacy policy against Act 843 and tell me what's missing."

**Not legal advice.** The policies this skill drafts are starting points grounded in your codebase and a summary of the Act. Have a lawyer check them, or check them against the [Data Protection Commission](https://dataprotection.org.gh)'s own guidance, before you publish, especially if your product handles special personal data or children's data.

## Using a skill

There's nothing special to type to invoke a skill. Once it's installed, describe the task in plain language, close to the wording in its description above (or in the skill's own frontmatter). The tool matches your request against the installed skills' descriptions and loads the matching one automatically before it starts working. If it doesn't seem to trigger, name the skill directly, e.g. "use the fix-vulns skill to...". In Claude Code, installed skills also show up in the slash-command menu: type `/` and the skill's name.

## Installing a skill

### Claude Code, via the plugin marketplace (recommended)

Add the marketplace once, then install the skills you want:

```
/plugin marketplace add RansfordGenesis/claude-skills
/plugin install fix-vulns@claude-skills
/plugin install ghana-data-protection-policies@claude-skills
```

To pick up new versions later, run `/plugin marketplace update claude-skills`.

### Manually, for any tool that reads the Agent Skills format

Copy the skill's folder into your tool's skills directory:

- Claude Code (personal): `~/.claude/skills/<skill-name>/`
- Claude Code (project, shared via git): `<project>/.claude/skills/<skill-name>/`
- Codex: `~/.codex/skills/<skill-name>/`
- Cross-runtime (Codex, Copilot CLI, Gemini CLI): `~/.agents/skills/<skill-name>/`

```bash
git clone https://github.com/RansfordGenesis/claude-skills.git
cp -R claude-skills/skills/fix-vulns ~/.claude/skills/
```

If you install a skill both ways, remove one copy so the tool doesn't see it twice.

## Contributing

Issues and pull requests are welcome. Each skill is a folder under `skills/` with a `SKILL.md` (frontmatter `name` and `description`, then instructions), any supporting files it references, and a `.claude-plugin/plugin.json`. Add new skills to `.claude-plugin/marketplace.json` and to the table above.

## License

[MIT](LICENSE)
