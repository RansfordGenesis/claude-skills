# claude-skills

Personal skills for [Claude Code](https://claude.com/claude-code) and other agent CLIs that read the [Agent Skills](https://agentskills.io/specification) format.

## Skills

### [ghana-data-protection-policies](skills/ghana-data-protection-policies/SKILL.md)

Writes and audits privacy policies, terms of service, and cookie policies for products processing personal data in Ghana, so they conform to the Data Protection Act, 2012 (Act 843). It scans the target codebase for what data is actually collected before drafting, distills the Act into a section-cited reference, and enforces plain English with no em dashes.

## Installing a skill

### Claude Code, via the plugin marketplace (recommended)

```
/plugin marketplace add RansfordGenesis/claude-skills
/plugin install ghana-data-protection-policies@claude-skills
```

### Manually, for any tool that reads the Agent Skills format

Copy the skill's folder into your tool's skills directory:

- Claude Code (personal): `~/.claude/skills/<skill-name>/`
- Claude Code (project, shared via git): `<project>/.claude/skills/<skill-name>/`
- Codex: `~/.codex/skills/<skill-name>/`
- Cross-runtime (Codex, Copilot CLI, Gemini CLI): `~/.agents/skills/<skill-name>/`

```bash
git clone https://github.com/RansfordGenesis/claude-skills.git
cp -R claude-skills/skills/ghana-data-protection-policies ~/.claude/skills/
```
