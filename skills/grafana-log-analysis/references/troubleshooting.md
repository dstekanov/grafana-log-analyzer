# Troubleshooting

## No logs found

**Symptom:** Script reports "No errors found in logs" or all queries return empty.

**Causes & fixes:**
- **Time range too short** — Increase with `--hours 6` or `--hours 24`. Logs may be from an older run.
- **Wrong environment** — Verify `--env` matches where the test ran.
- **Logs expired** — Loki retains logs for a limited time (typically 7-30 days).
- **Wrong identifier** — Try a different identifier (e.g., `--account-uuid` instead of `--subscription-uuid`).
- **Wrong env-suffix** — Check your Loki label format. Use `--env-suffix` if needed.

## Credential errors

**Symptom:** `Configuration error: GRAFANA_USER environment variable is not set`

**Fix:** Provide credentials via one of:
1. `--credentials grafana_api_token.yml`
2. Environment variables: `GRAFANA_URL`, `GRAFANA_USER`, `GRAFANA_PASSWORD`
3. Auto-detected file: `grafana_api_token.yml` or `.grafana_credentials.yml` in current dir

See [environments.md](environments.md) for details.

## Rate limiting

**Symptom:** Queries timeout or return 429 errors.

**Fix:**
- Use `--mode errors` instead of `--mode full` to reduce queries
- Reduce `--hours` to narrow the time range
- Wait a few minutes and retry

## Mode-specific tips

| Mode | When to use | Common issues |
|---|---|---|
| `errors` | First pass — quick error check | May miss workflow-level failures not tagged ERROR |
| `workflows` | Temporal/workflow failures | Only finds entries with "failed"/"error" in workflow logs |
| `network` | Network/API call issues | Requires `--subscription-uuid` or `--iccid` |
| `trace` | Distributed tracing | Needs errors mode to run first (to discover trace_ids) |
| `timeline` | Full chronological view | Can be verbose; uses 500-line limit |
| `full` | Complete analysis | Slowest; runs all phases sequentially |

## Custom search patterns

The default search patterns can be overridden by using the library programmatically:

```ruby
require 'grafana_log_analyzer'

analyzer = GrafanaLogAnalyzer::Analyzer.new(
  { subscription_uuid: 'UUID' },
  config: {
    search_patterns: {
      errors: %w[ERROR Exception failed],
      workflows: ['MyWorkflow::', 'Temporal'],
      network: ['MyProvider client', 'ExternalAPI']
    }
  }
)
```
