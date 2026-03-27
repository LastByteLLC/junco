# Security Policy

## Supported Versions

| Version | Supported |
|---|---|
| 0.3.x | Current |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it privately via GitHub Security Advisories rather than opening a public issue.

## Security Model

Junco executes shell commands and modifies files on behalf of the user. The following safeguards are in place:

### Shell Execution
- **Blocked commands**: `rm -rf /`, `sudo`, `shutdown`, `reboot`, `dd if=`, fork bombs, and others defined in `Config.blockedShellPatterns`
- **Timeout**: All commands timeout after 30 seconds (configurable via `Config.bashTimeout`)
- **Working directory**: Commands execute within the project directory

### File Operations
- **Path containment**: All file paths are resolved and verified to be within the project directory. Symlinks are fully resolved to prevent traversal.
- **Sensitive file blocking**: Writes to `.env`, `credentials.json`, `.p12`, `.pem`, and `.key` files are refused (configurable via `Config.sensitiveFilePatterns`)

### LLM Safety
- All inference runs on-device via Apple Foundation Models. No data leaves the machine.
- Structured output (`@Generable`) constrains LLM responses to predefined types.
- User input is sanitized before prompt injection (ANSI stripping, whitespace collapsing).

### Data Storage
- Reflections stored in project-local `.junco/reflections.jsonl`
- SQLite database at `~/.junco/junco.db` uses parameterized queries throughout
- No telemetry, no network calls, no analytics
