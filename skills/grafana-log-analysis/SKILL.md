---
name: grafana-log-analysis
description: Analyze Grafana/Loki logs to find root causes of test failures. Use when a test fails and you have identifiers (subscription_uuid, account_uuid, msisdn, iccid, imei).
---

# Grafana Log Analysis

## Quick start

```bash
ENVIRONMENT=production GRAFANA_URL=https://your-grafana.example.com \
  grafana-log-analyzer --subscription-uuid "UUID" --mode errors
```

Or with a credentials file:

```bash
grafana-log-analyzer --subscription-uuid "UUID" --mode errors \
  --env production --credentials grafana_api_token.yml
```

## Core workflow

1. Get test identifiers from the failed test (subscription_uuid, account_uuid, etc.)
2. Determine the environment (ask user if unknown)
3. Run with `--mode errors` first for a quick check
4. If more context needed, use `--mode timeline` or `--mode full`
5. Read the compact output, trace the failure, report findings

## Commands

### Analysis modes

```bash
# Quick error search (fastest, start here)
grafana-log-analyzer --subscription-uuid "UUID" --mode errors

# Workflow execution failures (Temporal, etc.)
grafana-log-analyzer --subscription-uuid "UUID" --mode workflows

# Network provider call failures
grafana-log-analyzer --subscription-uuid "UUID" --mode network

# Search by trace_id (distributed tracing)
grafana-log-analyzer --subscription-uuid "UUID" --mode trace

# Chronological workflow timeline
grafana-log-analyzer --subscription-uuid "UUID" --mode timeline

# Full analysis (all phases — slowest)
grafana-log-analyzer --subscription-uuid "UUID" --mode full
```

### Identifiers (use at least one)

```bash
--subscription-uuid "UUID"   # highest priority
--account-uuid "UUID"
--msisdn "MSISDN"
--iccid "ICCID"
--imei "IMEI"
```

### Options

```bash
--hours N            # time range (default: 3)
--format compact     # concise markdown output (default)
--format json        # full JSON output
--env ENV            # environment name
--env-suffix SUFFIX  # env label suffix (e.g. -mse)
--credentials FILE   # YAML credentials file
--grafana-url URL    # Grafana base URL
```

### Install skill files

```bash
# Install to Windsurf
grafana-log-analyzer --install-skills .windsurf/skills/grafana-log-analysis

# Install to Claude Code
grafana-log-analyzer --install-skills .claude/skills/grafana-log-analysis
```

## Example: Investigate a failed test

```bash
grafana-log-analyzer \
  --subscription-uuid "85d2d9b7-1cb3-4fba-bda9-bc7ea2e2010e" \
  --account-uuid "0285e04f-2f2d-4e53-a54c-cad2e7da8b42" \
  --mode errors --hours 6 --env dev200 --env-suffix "-mse"
```

## Output format

The script reports findings in this structure. Always include Grafana UI links.

```markdown
# Grafana Log Analysis Results

## Root Cause Identified
**Category:** [e.g., Device Validation Error, Network Error, Workflow Timeout]
**Summary:** [One-sentence description of what went wrong]

## Key Error
| Field | Value |
|-------|-------|
| Service | [service-name] |
| Timestamp | [YYYY-MM-DD HH:MM:SS UTC] |
| Trace ID | [trace_id] |

## Analysis
[Narrative: what started, what succeeded, where it failed, what the system is doing now.
Include timestamps, UUIDs, service names from logs.]

## Grafana UI Links
- **All Logs:** [View in Grafana](url)
- **Errors Only:** [View in Grafana](url)

## Recommendations
1. [Specific actionable step]
2. [Specific actionable step]
```

## Specific tasks

- **Environment setup & credentials** → [references/environments.md](references/environments.md)
- **LogQL query syntax** → [references/logql_query_guide.md](references/logql_query_guide.md)
- **Output format details** → [references/output-format.md](references/output-format.md)
- **Troubleshooting** → [references/troubleshooting.md](references/troubleshooting.md)
