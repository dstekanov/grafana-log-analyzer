# Output Format

## Compact (default)

Token-efficient markdown output. Best for AI agent consumption.

```bash
--format compact   # default, no need to specify
```

Example output:

```
# Log Analysis: errors mode (3h)

## Root Cause
**errors_found**: Found 2 log entries with errors/issues
`[ERROR] No TAC record found for device [353549531105541]`

## Log Entries (2)
[2026-01-27 17:23:35] **ERROR** No TAC record found for device [353549531105541]
[2026-01-27 17:23:30] **ERROR** DeviceValidationActivity failed: TAC_NOT_FOUND

## Trace IDs
- `8183b664f749857ec07cb96dc85091fe`

## Grafana Links
- **all_logs**: https://grafana.example.com/explore?...
- **errors_only**: https://grafana.example.com/explore?...

## Recommendations
- Review the error messages above for specific failure details
- Check workflow status in your workflow engine UI
```

### Compact format rules

- Log entries capped at 15 (shows count if more)
- Timeline events capped at 20
- Trace IDs capped at 5
- Messages truncated at 200 chars
- Event types tagged: `ERR`, `WF`, `ACT`, `GRPC`, `KAFKA`, `NET`, `INFO`

## JSON

Full structured JSON output. Use when you need to process data programmatically.

```bash
--format json
```

Returns the complete results hash with all fields:

- `identifiers` — input identifiers
- `hours_analyzed` — time range
- `mode` — analysis mode used
- `queries_executed` — all LogQL queries run
- `log_entries` — all matched log entries
- `trace_ids_found` — extracted trace IDs
- `workflow_timeline` — chronological events
- `root_cause` — category + summary + details
- `recommendations` — actionable steps
- `grafana_urls` — clickable Explore URLs
