# Contributing

Thanks for your interest in contributing to **grafana-log-analyzer**!

## Getting Started

1. Fork and clone the repo
2. Copy `grafana_api_token.example.yml` to `grafana_api_token.yml` and fill in your Grafana credentials
3. Run the tool:
   ```bash
   ruby bin/grafana-log-analyzer --help
   ```

## Project Structure

```
bin/grafana-log-analyzer           # CLI entry point
lib/grafana_log_analyzer.rb        # Main module
lib/grafana_log_analyzer/
  client.rb                        # HTTP client (basic auth)
  loki.rb                          # Loki query_range API wrapper
  log_parser.rb                    # Log parsing utilities
  analyzer.rb                      # Main analysis engine
  version.rb                       # Version constant
skills/grafana-log-analysis/       # AI agent skill files
  SKILL.md                         # Skill definition
  references/                      # Reference docs
```

## Design Principles

- **Zero external dependencies** — stdlib only (net/http, json, yaml, uri, cgi, logger)
- **Generic** — no project-specific hardcoding; everything is configurable
- **Token-efficient** — compact output format designed for AI agent consumption
- **Modular** — each class has a single responsibility

## Adding a New Analysis Mode

1. Add the mode name to `VALID_MODES` in `lib/grafana_log_analyzer/analyzer.rb`
2. Create a `search_for_*` method
3. Gate it with `run_phase?(:your_mode)` in the `analyze` method
4. Update `SKILL.md` with the new mode

## Adding Search Patterns

Default patterns are in `Analyzer::DEFAULT_SEARCH_PATTERNS`. Users can override them via the `config[:search_patterns]` option.

## Reporting Issues

Please include:
- Ruby version (`ruby -v`)
- The command you ran (redact credentials)
- The error output
- Your Grafana/Loki version if known
