# Junco

<p align="center">
  <img src="junco.png" width="128" height="128" alt="Junco Icon" />
</p>

<h1 align="center">Junco</h1>

<p align="center">
  <strong>Free, local AI coding Agent for macOS and iOS apps</strong><br />
  Junco runs <i>on-device</i> using Apple Intelligence. No rate limits, no API keys, no subscriptions.
</p>

<p align="center">
  <a href="https://apple.com/macos"><img src="https://img.shields.io/badge/macOS-26%2B-lightgrey.svg" alt="macOS"></a>
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.0-F05138.svg" alt="Swift"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
  <a href="http://makeapullrequest.com"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg" alt="PRs Welcome"></a>
</p>

<p align="center">
  <a href="#building">Building</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="#requirements">Requirements</a>
</p>

**Junco** is an AI coding agent that runs entirely on-device using Apple Foundation Models (AFM). No API keys, no cloud, no telemetry.

**Why Junco?** Junco uses a micro-conversation pipeline to work within AFM's tiny 4K token context window — each stage (classify, plan, execute & reflect) is a separate LLM call with focused context and structured `@Generable` output. A trained CRF text classifier handles intent detection in ~10ms, and a reflexion loop stores insights for future tasks. Junco also uses a [custom Low-Rank Adaptation (LoRA) adapter](https://developer.apple.com/documentation/foundationmodels/loading-and-using-a-custom-adapter-with-foundation-models) trained on recent Swift 6.3+ permissively-licensed code snippets, public documentation, and synthetic data to help steer the on-device model.

## Quick Start

```bash
git clone https://github.com/LastByteLLC/junco.git
cd junco
swift build
swift run junco
```

Requires **macOS 26+** and **Apple Silicon** (M1+). No API keys or configuration needed — Apple Intelligence must be enabled in System Settings.

## Usage

```
junco> fix the login bug in @Sources/Auth.swift
junco> explain how the payment flow works
junco> add tests for the User model
junco> /metrics
junco> /undo
```

### Commands

| Command | Description |
| --- | --- |
| `/help` | Show all commands |
| `/clear` | Purge session context and turn history |
| `/undo` | Revert last agent changes (requires git) |
| `/metrics` | Token usage, energy estimate, call counts |
| `/reflections [query]` | Show stored reflections, optionally filtered |
| `/domain` | Detected project domain and build commands |
| `/git` | Branch and change status |
| `/context` | Multi-turn context from previous queries |
| `/pastes` | List clipboard pastes in this session |
| `exit` | End session with summary |

### Pipe Mode

```bash
echo "explain the main function" | junco --pipe --directory ./my-project
```

### `@`-File Targeting

Prefix paths with `@` to explicitly target files. Junco resolves paths and injects content into the agent's context:

```
junco> refactor @src/api/handler.ts to use async/await
```

## Architecture

Junco processes queries through a 6-stage pipeline, each a separate LLM call:

```
query → CLASSIFY → STRATEGY → PLAN → EXECUTE (2-phase) → REFLECT
         10ms       ~2s        ~2s      ~2s × N steps      ~2s
        (ML/CRF)   (AFM)      (AFM)      (AFM)            (AFM)
```

**Two-phase tool execution** prevents the small on-device model from garbling fields — Phase 1 picks the tool (`ToolChoice`, 2 fields), Phase 2 fills tool-specific params (`BashParams`, `ReadParams`, `EditParams`, etc.).

### Layers

| Layer | Purpose | Files |
| --- | --- | --- |
| **Agent** | Pipeline orchestration, session management, reflexion, skills | 13 |
| **Models** | `@Generable` structured types, token budget, config | 4 |
| **LLM** | Adapter pattern (AFM now, extensible to OpenAI-compatible) | 3 |
| **Tools** | Sandboxed shell, validated file ops, diff preview, FSEvents | 5 |
| **RAG** | Regex symbol indexer (Swift + JS), BM25 context packing | 2 |
| **Domain** | Auto-detect Swift/JS/general from marker files | 1 |
| **TUI** | ANSI output with piped fallback, terminal title control | 1 |

### Key Design Decisions

- **Micro-conversations over long context** — AFM has ~4K tokens. Each pipeline stage sees only what it needs.
- **`@Generable` structured output** — compile-time type safety, zero parsing overhead.
- **ML for classification** — CRF model trained on 9.5K examples replaces one LLM call per task.
- **Reflexion loop** — post-task reflections stored in `.junco/reflections.jsonl`, retrieved by keyword match for future similar tasks.
- **MicroSkills** — token-capped prompt modifiers (e.g., "swift-test" forces Swift Testing patterns, "explain-only" disables write tools).

## Domain Detection

Junco auto-detects your project type:

| Marker | Domain | Build | Test |
| --- | --- | --- | --- |
| `Package.swift` | Swift | `swift build` | `swift test` |
| `package.json` | JavaScript | `npm run build` | `npm test` |
| Neither | General | — | — |

Override with `.junco/config.json`:

```json
{ "domain": "swift" }
```

## Project Files

Junco creates a `.junco/` directory in your project for:

- `reflections.jsonl` — learned insights from past tasks
- `config.json` — manual domain override
- `scratchpad.json` — persistent project notes
- `skills.json` — custom micro-skills

Global state lives in `~/.junco/`:

- `junco.db` — SQLite with FTS5 for cross-project reflection search
- `models/` — compiled ML models

## Building

```bash
# Debug
swift build

# Release (2.5MB binary)
swift build -c release

# Run tests
swift test

# Install
cp .build/release/junco /usr/local/bin/
```

## Requirements

- macOS 26.0+
- Apple Silicon (M1/M2/M3/M4/M5)
- Apple Intelligence enabled
- Xcode 26+ or Swift 6.2+ toolchain

## License

MIT
