# Codex CLI Compatibility for speckit-pro

**Date:** 2026-04-07
**Status:** Draft
**Author:** Racecraft Lab

## Summary

Add OpenAI Codex CLI compatibility to the speckit-pro plugin so that the same GitHub repository (`racecraft-lab/racecraft-plugins-public`) works as both a Claude Code plugin marketplace and a Codex CLI plugin marketplace. Both the coach and autopilot skills must work identically across platforms.

## Approach

Dual-manifest plugin with parallel directories for platform-specific files. Shared assets (scripts, references, templates) remain in place and are referenced via relative paths from the Codex skill files.

## Repository Structure

```
speckit-pro/
├── .claude-plugin/
│   └── plugin.json                     ← Claude Code manifest (EXISTING)
├── .codex-plugin/
│   └── plugin.json                     ← Codex manifest (NEW)
│
├── agents/                             ← Claude Code agents (EXISTING, 8 files)
│   ├── analyze-executor.md
│   ├── checklist-executor.md
│   ├── clarify-executor.md
│   ├── codebase-analyst.md
│   ├── domain-researcher.md
│   ├── implement-executor.md
│   ├── phase-executor.md
│   └── spec-context-analyst.md
│
├── codex-agents/                       ← Codex agents (NEW, 8 files + openai.yaml)
│   ├── openai.yaml                     ← Plugin-level Codex agent metadata
│   ├── analyze-executor.md
│   ├── checklist-executor.md
│   ├── clarify-executor.md
│   ├── codebase-analyst.md
│   ├── domain-researcher.md
│   ├── implement-executor.md
│   ├── phase-executor.md
│   └── spec-context-analyst.md
│
├── commands/                           ← Claude Code only (EXISTING, 5 files)
│   ├── autopilot.md
│   ├── coach.md
│   ├── resolve-pr.md
│   ├── setup.md
│   └── status.md
│
├── skills/                             ← Claude Code skills (EXISTING)
│   ├── speckit-autopilot/
│   │   ├── SKILL.md
│   │   ├── references/                 ← SHARED (both platforms)
│   │   └── scripts/                    ← SHARED
│   └── speckit-coach/
│       ├── SKILL.md
│       ├── references/                 ← SHARED
│       └── templates/                  ← SHARED
│
├── codex-skills/                       ← Codex skills (NEW)
│   ├── speckit-autopilot/
│   │   ├── SKILL.md                    ← Codex version
│   │   └── agents/
│   │       └── openai.yaml             ← Per-skill Codex metadata
│   └── speckit-coach/
│       ├── SKILL.md                    ← Codex version
│       └── agents/
│           └── openai.yaml
│
├── hooks/
│   └── hooks.json                      ← Claude Code hooks (EXISTING)
├── codex-hooks.json                    ← Codex hooks (NEW, plugin root)
│
├── tests/                              ← Test suite (EXISTING + new Codex layers)
└── .agents/
    └── plugins/
        └── marketplace.json            ← Codex marketplace registry (NEW, repo root)
```

The existing `.claude-plugin/marketplace.json` at repo root serves Claude Code. The new `.agents/plugins/marketplace.json` at repo root serves Codex. Both point at `speckit-pro/`.

## Codex Plugin Manifest

`.codex-plugin/plugin.json`:

```json
{
  "name": "speckit-pro",
  "version": "1.1.0",
  "description": "Autonomous Spec-Driven Development powered by GitHub SpecKit. Includes SDD coaching, multi-spec project management, and a fully autonomous workflow executor with multi-agent clarification consensus.",
  "author": {
    "name": "Racecraft Lab",
    "url": "https://github.com/racecraft-lab"
  },
  "repository": "https://github.com/racecraft-lab/racecraft-plugins-public",
  "license": "MIT",
  "keywords": ["speckit", "sdd", "spec-driven-development", "specification", "planning", "autopilot", "autonomous", "workflow"],
  "skills": "./codex-skills/",
  "mcpServers": "./.mcp.json",
  "interface": {
    "displayName": "SpecKit Pro",
    "shortDescription": "Spec-Driven Development with autonomous workflow execution",
    "longDescription": "Autonomous SDD powered by GitHub SpecKit. Includes methodology coaching, multi-spec project management, and a fully autonomous 7-phase workflow executor with multi-agent clarification consensus.",
    "developerName": "Racecraft Lab",
    "category": "Coding",
    "capabilities": ["Interactive", "Read", "Write"],
    "websiteURL": "https://github.com/racecraft-lab/racecraft-plugins-public",
    "defaultPrompt": "Use SpecKit Pro to coach me through Spec-Driven Development, set up a new spec, or run an autonomous SDD workflow",
    "brandColor": "#6366F1"
  }
}
```

Key differences from Claude Code manifest:
- Adds `skills` path pointing to `./codex-skills/`
- Adds `mcpServers` reference to `.mcp.json` — this file documents optional MCP dependencies (Tavily, Context7, RepoPrompt) but does not bundle servers. Users who have these configured in their environment get enhanced behavior; others use built-in fallbacks. If no MCP dependencies are needed at install time, this field can be omitted.
- Adds `interface` block for Codex marketplace display
- Same `name`, `version`, `description` — version stays in sync via release-please

## Codex Marketplace Registry

`.agents/plugins/marketplace.json` at repo root:

```json
{
  "name": "racecraft-public-plugins",
  "interface": {
    "displayName": "Racecraft Public Plugins"
  },
  "plugins": [
    {
      "name": "speckit-pro",
      "source": {
        "source": "local",
        "path": "./speckit-pro"
      },
      "policy": {
        "installation": "AVAILABLE",
        "authentication": "ON_INSTALL"
      },
      "category": "Coding"
    }
  ]
}
```

Key differences from Claude Code marketplace:
- Lives at `.agents/plugins/marketplace.json` (not `.claude-plugin/marketplace.json`)
- `source` is an object `{ "source": "local", "path": "..." }` instead of a flat string
- Adds `policy` with `installation` and `authentication` fields
- No `version` field per plugin entry — Codex reads version from `plugin.json` at install time

## Model & Effort Mapping

### Field Translation

| Claude Code Field | Value | Codex Field | Value |
|---|---|---|---|
| `model: opus` | — | `model:` | `gpt-5.4-pro` |
| `model: sonnet` | — | `model:` | `gpt-5.4` |
| `effort: max` | — | `model_reasoning_effort:` | `x_high` |
| `effort: high` | — | `model_reasoning_effort:` | `high` |
| `effort: medium` | — | `model_reasoning_effort:` | `medium` |
| `permissionMode: plan` | read-only | `sandbox_mode:` | `read-only` |
| `permissionMode: acceptEdits` | read+write | `sandbox_mode:` | `workspace-write` |
| `tools:` | explicit list | (system prompt) | instructions + MCP scoping |
| `maxTurns:` | 25-100 | (no equivalent) | — |
| `color:` | visual only | (no equivalent) | — |
| `background: true` | parallel exec | (no equivalent) | — |

### Per-Agent Mapping

| Agent | CC Model | CC Effort | Codex Model | Codex Effort | Codex Sandbox |
|---|---|---|---|---|---|
| `clarify-executor` | opus | high | gpt-5.4-pro | high | workspace-write |
| `checklist-executor` | opus | high | gpt-5.4-pro | high | workspace-write |
| `analyze-executor` | opus | high | gpt-5.4-pro | high | workspace-write |
| `implement-executor` | opus | max | gpt-5.4-pro | x_high | workspace-write |
| `phase-executor` | sonnet | medium | gpt-5.4 | medium | workspace-write |
| `codebase-analyst` | sonnet | medium | gpt-5.4 | medium | read-only |
| `spec-context-analyst` | sonnet | medium | gpt-5.4 | medium | read-only |
| `domain-researcher` | sonnet | medium | gpt-5.4 | medium | read-only |

### Tool Scoping Strategy

Claude Code scopes tools via explicit `tools:` lists in agent frontmatter. Codex achieves equivalent isolation through three layers:

1. **`sandbox_mode`** in agent frontmatter — `read-only` for analysts, `workspace-write` for executors
2. **MCP `enabled_tools`/`disabled_tools`** — per-MCP-server allow/deny lists restrict which MCP tools each agent can access
3. **System prompt instructions** — behavioral constraints as defense-in-depth

## Codex Agent Frontmatter Format

Claude Code agents use rich YAML frontmatter. Codex agents use a simpler schema:

**Claude Code** (`agents/clarify-executor.md`):
```yaml
---
name: clarify-executor
description: >
  Executes a single /speckit.clarify session...
model: opus
color: orange
tools:
  - Skill
  - Read
  - Write
  - mcp__tavily-mcp__tavily-search
  # ... full tool list
permissionMode: acceptEdits
maxTurns: 75
effort: high
---
```

**Codex** (`codex-agents/clarify-executor.md`):
```yaml
---
name: clarify-executor
description: >
  Executes a single /speckit.clarify session...
model: gpt-5.4-pro
model_reasoning_effort: high
sandbox_mode: workspace-write
---
```

## Codex Hooks

`codex-hooks.json` at plugin root:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "command -v specify >/dev/null 2>&1 || echo 'speckit-pro: WARNING — SpecKit CLI not found. Install: uv tool install specify-cli --from git+https://github.com/github/spec-kit.git'",
            "statusMessage": "Checking SpecKit CLI availability"
          }
        ]
      }
    ]
  }
}
```

Differences from Claude Code `hooks/hooks.json`:
- Lives at plugin root (not `hooks/hooks.json`) — matching the official Figma plugin pattern
- Adds `matcher: "startup"` (Codex supports `startup` vs `resume` matching)
- Adds `statusMessage` field for TUI feedback
- Same hook logic — the `specify` CLI check is platform-agnostic

## Skill Adaptation (SKILL.md)

Each platform gets its own SKILL.md files. Shared assets (references, scripts, templates) are referenced via relative paths from Codex skills.

### Tool/Invocation Translation in Skill Content

| Claude Code Reference | Codex Equivalent |
|---|---|
| `Skill("speckit.clarify")` | `$speckit-clarify` (skill sigil) |
| `Skill("speckit.specify")` | `$speckit-specify` |
| `Agent({ subagent_type: "clarify-executor" })` | Natural language: "Spawn the clarify-executor agent" |
| `Read`, `Write`, `Edit`, `Bash` | Filesystem access governed by `sandbox_mode` |
| `Grep`, `Glob` | Shell commands or MCP `file_search` |
| `WebSearch`, `WebFetch` | MCP-provided web tools or built-in web search |
| `mcp__tavily-mcp__*` | Tavily MCP tools (same if user has them configured) |
| `mcp__RepoPrompt__*` | RepoPrompt MCP tools (same if configured) |

### Content Overlap

Approximately 80% of each SKILL.md body transfers as-is. The 20% that changes:
- Tool invocation syntax
- Agent spawning patterns (Claude Code structured calls → Codex natural language delegation)
- Platform-specific instructions and fallback paths

### openai.yaml Sidecars

Each Codex skill gets `agents/openai.yaml`:

```yaml
interface:
  display_name: "SpecKit Autopilot"
  short_description: "Autonomous 7-phase SDD workflow executor"
  default_prompt: "Run a SpecKit autopilot workflow from a populated workflow file"

policy:
  allow_implicit_invocation: false

dependencies:
  tools:
    - type: mcp
      value: tavily
      description: "Web search for consensus research"
    - type: mcp
      value: context7
      description: "Library documentation lookup"
```

`allow_implicit_invocation: false` ensures autopilot only runs when explicitly requested — matching Claude Code's `user-invokable: false`.

## Release Automation

### release-please-config.json

Add the Codex `plugin.json` as an extra file:

```json
{
  "packages": {
    "speckit-pro": {
      "extra-files": [
        {
          "type": "json",
          "path": ".claude-plugin/plugin.json",
          "jsonpath": "$.version"
        },
        {
          "type": "json",
          "path": ".codex-plugin/plugin.json",
          "jsonpath": "$.version"
        }
      ]
    }
  }
}
```

### Marketplace Version Sync

The Codex marketplace schema has no per-plugin `version` field — version is read from `plugin.json` at install time. No changes needed to `scripts/sync-marketplace-versions.sh` for Codex.

### CI/CD

The `detect` job in `pr-checks.yml` already detects changed plugin directories. New Codex files inside `speckit-pro/` are caught by existing detection logic. No workflow changes needed.

## Test Strategy

### New Structural Tests (Layer 1)

| Script | Validates |
|---|---|
| `validate-codex-plugin.sh` | `.codex-plugin/plugin.json` — required fields, `interface` block, `skills` path exists |
| `validate-codex-agents.sh` | `codex-agents/*.md` — frontmatter has `name` + `description`, optional `model`/`model_reasoning_effort`/`sandbox_mode`, body exists, `openai.yaml` present |
| `validate-codex-skills.sh` | `codex-skills/*/SKILL.md` — frontmatter has `name` + `description` only, `agents/openai.yaml` sidecar exists, reference paths resolve |
| `validate-codex-hooks.sh` | `codex-hooks.json` — valid JSON, supported event names, each hook has `type: "command"` |
| `validate-codex-marketplace.sh` | `.agents/plugins/marketplace.json` — valid JSON, required fields, `source.path` resolves |

### Cross-Platform Parity Tests (Layer 1)

| Script | Validates |
|---|---|
| `validate-version-sync.sh` | Version in `.claude-plugin/plugin.json` matches `.codex-plugin/plugin.json` |
| `validate-agent-parity.sh` | Every agent in `agents/` has a corresponding file in `codex-agents/` |
| `validate-skill-parity.sh` | Every skill in `skills/` has a corresponding directory in `codex-skills/` |
| `validate-shared-references.sh` | Codex SKILL.md reference paths resolve to existing shared files |

### Tool Scoping Tests (Layer 5)

Validate Codex agents have appropriate `sandbox_mode` values:
- Read-only analysts must have `sandbox_mode: read-only`
- Write agents must have `sandbox_mode: workspace-write`

### run-all.sh Updates

```bash
bash tests/run-all.sh           # Default: CC tests only (backward compatible)
bash tests/run-all.sh --codex   # CC + Codex structural tests
bash tests/run-all.sh --all     # Everything including Codex
```

## Scope

### In Scope

1. Codex plugin manifest (`.codex-plugin/plugin.json`)
2. Codex marketplace registry (`.agents/plugins/marketplace.json`)
3. Codex agent definitions (8 `.md` files in `codex-agents/` + `openai.yaml`)
4. Codex skill files (2 `SKILL.md` files in `codex-skills/` + `openai.yaml` sidecars)
5. Codex hooks (`codex-hooks.json`)
6. Structural tests for all new Codex files
7. Cross-platform parity tests
8. Release automation updates (`release-please-config.json` extra file)
9. Shared asset path validation

### Out of Scope

- Codex trigger evals (Layer 2/3) — requires Codex CLI eval harness
- Codex-specific slash commands — Codex has no file-based commands; skills handle invocation
- Plugin-bundled MCP servers — MCP dependencies are user-environment tools
- Branding assets (`assets/` directory with icons/logos)
- Windows compatibility — Codex hooks are disabled on Windows
- `gpt-5.3-codex-spark` support — Pro-only model, not in default mapping

### Assumptions

- Users have Codex CLI v0.115+ installed (plugin marketplace support)
- Users configure their own MCP servers if they want enhanced behavior
- SpecKit CLI (`specify`) works identically regardless of which coding agent invokes it
- `agents.max_threads = 6` and `agents.max_depth = 1` are sufficient for autopilot orchestration (max 4 parallel agents in consensus rounds)

## Research Sources

- [Subagents – Codex | OpenAI Developers](https://developers.openai.com/codex/subagents)
- [Agent Skills – Codex | OpenAI Developers](https://developers.openai.com/codex/skills)
- [Build Plugins – Codex | OpenAI Developers](https://developers.openai.com/codex/plugins/build)
- [Plugins – Codex | OpenAI Developers](https://developers.openai.com/codex/plugins)
- [Hooks – Codex | OpenAI Developers](https://developers.openai.com/codex/hooks)
- [Configuration Reference – Codex | OpenAI Developers](https://developers.openai.com/codex/config-reference)
- [Agent Approvals & Security – Codex | OpenAI Developers](https://developers.openai.com/codex/agent-approvals-security)
- [Models – Codex | OpenAI Developers](https://developers.openai.com/codex/models)
- [openai/plugins (official curated repo)](https://github.com/openai/plugins) — Figma, Vercel, Box plugins as reference implementations
- [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) — OpenAI's Claude Code plugin for Codex
