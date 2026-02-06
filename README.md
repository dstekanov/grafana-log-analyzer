# grafana-log-analyzer

A Ruby CLI tool and AI agent skill for analyzing Grafana/Loki logs to find root causes of test failures. Zero external dependencies — uses only Ruby stdlib.

Designed to be used by **AI coding agents** (Windsurf Cascade, Claude Code, GitHub Copilot) as a skill, or by humans directly from the command line.

## Features

- **Granular analysis modes** — `errors`, `workflows`, `network`, `trace`, `timeline`, `full`
- **Token-efficient output** — compact markdown format designed for AI agents
- **AI agent skill** — includes `SKILL.md` and reference docs for Windsurf, Claude Code, etc.
- **Configurable** — env labels, search patterns, Grafana URLs, credentials
- **Zero dependencies** — stdlib only (`net/http`, `json`, `yaml`)
- **`--install-skills`** — one command to install skill files into your project

## Quick Start

### 1. Clone

```bash
git clone https://github.com/dstekanov/grafana-log-analyzer.git
cd grafana-log-analyzer
```

### 2. Configure credentials

```bash
cp grafana_api_token.example.yml grafana_api_token.yml
# Edit grafana_api_token.yml with your Grafana URL, user, and token
```

Or use environment variables:

```bash
export GRAFANA_URL="https://your-grafana.example.com"
export GRAFANA_USER="your_user_id"
export GRAFANA_PASSWORD="your_api_token"
```

### 3. Run

```bash
# Quick error search
ruby bin/grafana-log-analyzer \
  --subscription-uuid "your-uuid" \
  --mode errors --env production

# Full analysis with JSON output
ruby bin/grafana-log-analyzer \
  --subscription-uuid "your-uuid" \
  --mode full --hours 6 --format json
```

## Usage

```
grafana-log-analyzer v1.0.0
Analyze Grafana/Loki logs to find root causes of failures.

Usage: grafana-log-analyzer [options]

Modes: full, errors, workflows, network, trace, timeline

Identifiers (at least one required):
    --subscription-uuid UUID     Subscription UUID
    --account-uuid UUID          Account UUID
    --msisdn MSISDN              Phone number (MSISDN)
    --iccid ICCID                SIM card identifier (ICCID)
    --imei IMEI                  Device identifier (IMEI)

Options:
    --hours N                    Time range in hours (default: 3)
    --mode MODE                  Analysis mode (default: full)
    --format FORMAT              Output format: compact (default), json

Configuration:
    --grafana-url URL            Grafana base URL
    --env ENV                    Environment name (e.g. qa, production)
    --env-suffix SUFFIX          Env label suffix (e.g. -mse → {env="qa-mse"})
    --credentials FILE           YAML credentials file path
    --install-skills [DIR]       Install AI agent skill files
    --version                    Show version
    -h, --help                   Show help
```

## Analysis Modes

| Mode | What it does | Speed |
|---|---|---|
| `errors` | Searches for ERROR, Exception, failed, timeout, rejected | Fast |
| `workflows` | Searches for Temporal/Workflow failures | Fast |
| `network` | Searches for network/API call failures | Fast |
| `trace` | Searches by trace_id (requires errors mode first) | Medium |
| `timeline` | Builds chronological event timeline | Medium |
| `full` | Runs all phases | Slowest |

**Recommended workflow:** Start with `--mode errors`, then expand to `--mode timeline` or `--mode full` if needed.

## Output Formats

### Compact (default)

Token-efficient markdown — ideal for AI agents:

```
# Log Analysis: errors mode (3h)

## Root Cause
**errors_found**: Found 2 log entries with errors/issues
`[ERROR] DeviceValidationActivity failed: TAC_NOT_FOUND`

## Log Entries (2)
[2026-01-27 17:23:35] **ERROR** No TAC record found for device [353549531105541]
[2026-01-27 17:23:30] **ERROR** DeviceValidationActivity failed: TAC_NOT_FOUND

## Trace IDs
- `8183b664f749857ec07cb96dc85091fe`

## Grafana Links
- **all_logs**: https://grafana.example.com/explore?...
- **errors_only**: https://grafana.example.com/explore?...
```

### JSON

Full structured output for programmatic use — add `--format json`.

## AI Agent Skill

This tool includes skill files for AI coding agents. Install them into your project:

```bash
# Windsurf Cascade
ruby bin/grafana-log-analyzer --install-skills .windsurf/skills/grafana-log-analysis

# Claude Code
ruby bin/grafana-log-analyzer --install-skills .claude/skills/grafana-log-analysis

# Or copy manually
cp -r skills/grafana-log-analysis/ YOUR_PROJECT/.windsurf/skills/grafana-log-analysis/
```

The skill includes:
- **`SKILL.md`** — concise command reference for the agent
- **`references/`** — detailed docs the agent can consult on demand

## Using as a Library

```ruby
require_relative 'lib/grafana_log_analyzer'

analyzer = GrafanaLogAnalyzer::Analyzer.new(
  { subscription_uuid: 'your-uuid' },
  hours: 6,
  mode: 'errors',
  config: {
    grafana_url: 'https://your-grafana.example.com',
    grafana_user: 'user',
    grafana_password: 'token',
    env: 'production',
    env_suffix: '',
    search_patterns: {
      errors: %w[ERROR Exception failed timeout],
      workflows: ['Workflow::', 'Temporal'],
      network: ['MyProvider client']
    }
  }
)

analyzer.analyze
puts analyzer.to_compact  # or analyzer.to_json
```

## Environment Labels

The `--env` and `--env-suffix` flags control the Loki `{env="..."}` label:

```bash
--env qa                        # → {env="qa"}
--env qa --env-suffix "-mse"    # → {env="qa-mse"}
--env production                # → {env="production"}
```

## Requirements

- **Ruby 3.0+** (uses `Hash#except`)
- **Grafana with Loki** datasource
- Basic auth credentials for Grafana API

## Project Structure

```
bin/grafana-log-analyzer           # CLI entry point
lib/grafana_log_analyzer.rb        # Main module
lib/grafana_log_analyzer/
  client.rb                        # HTTP client (basic auth)
  loki.rb                          # Loki query_range wrapper
  log_parser.rb                    # Log parsing utilities
  analyzer.rb                      # Main analysis engine
  version.rb                       # Version constant
skills/grafana-log-analysis/       # AI agent skill files
  SKILL.md                         # Skill definition
  references/                      # Reference docs for agents
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
