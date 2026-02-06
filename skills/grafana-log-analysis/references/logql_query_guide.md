# LogQL Query Guide

## Basic Query Structure

```
{label_selector} |= `filter` |= `another_filter`
```

## Environment Labels

The tool builds labels from `--env` and `--env-suffix`:

```
{env="<environment><suffix>"} |= `<identifier>` |= `<pattern>`
```

Examples:

| --env | --env-suffix | Label |
|---|---|---|
| `qa` | (none) | `{env="qa"}` |
| `qa` | `-mse` | `{env="qa-mse"}` |
| `dev200` | `-app` | `{env="dev200-app"}` |
| `production` | (none) | `{env="production"}` |

## Filter Operators

| Operator | Description | Example |
|---|---|---|
| `\|=` | Contains (case-sensitive) | `\|= \`ERROR\`` |
| `\|~` | Regex match | `\|~ \`error\|warning\`` |
| `!=` | Does not contain | `!= \`DEBUG\`` |
| `!~` | Does not match regex | `!~ \`health.*check\`` |

## Common Query Patterns

### By identifier

```
{env="qa"} |= `subscription_uuid_value`
```

### Errors only

```
{env="qa"} |= `subscription_uuid` |= `ERROR`
```

### Workflow execution

```
{env="qa"} |= `Workflow::Activation` |= `subscription_uuid`
```

### Network calls

```
{env="qa"} |= `API client` |= `subscription_uuid`
```

### Exclude noise

```
{env="qa"} |= `identifier` != `health` != `ping`
```

## Time Range Considerations

- Default: 1 hour (3600 seconds)
- Extended: 2 hours (7200 seconds) for slow workflows
- Maximum recommended: 6 hours (21600 seconds)

## Query Optimization Tips

1. **Be specific** — use the most unique identifier first
2. **Limit time range** — smaller ranges are faster
3. **Chain filters** — add more filters to narrow results
4. **Use regex sparingly** — literal matches (`|=`) are faster than regex (`|~`)
