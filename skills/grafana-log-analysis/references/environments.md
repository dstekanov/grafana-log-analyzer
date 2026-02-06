# Environment Setup & Credentials

## Grafana Connection

The analyzer needs three things to connect to your Grafana/Loki instance:

| Setting | CLI flag | Env var | Credentials file key |
|---|---|---|---|
| **Grafana URL** | `--grafana-url` | `GRAFANA_URL` | `grafana_url` |
| **Username** | via `--credentials` | `GRAFANA_USER` | `user` or `api_user` |
| **Password/Token** | via `--credentials` | `GRAFANA_PASSWORD` | `password` or `api_password` |

Priority: CLI flags > credentials file > environment variables.

## Credentials File

Create a YAML file (e.g., `grafana_api_token.yml`):

```yaml
grafana_url: "https://your-grafana.example.com"
user: "<your_user_id>"
password: "<your_api_token>"
```

Pass it with `--credentials`:

```bash
grafana-log-analyzer --credentials grafana_api_token.yml --subscription-uuid "UUID" --mode errors
```

The tool also auto-detects `grafana_api_token.yml` or `.grafana_credentials.yml` in the current directory.

## Multiple Environments

If you have separate Grafana instances (e.g., nonprod vs prod), use separate credential files:

```bash
# Nonprod
grafana-log-analyzer --credentials creds-nonprod.yml --env dev200 ...

# Prod
grafana-log-analyzer --credentials creds-prod.yml --env production ...
```

## Environment Labels

The `--env` and `--env-suffix` flags control the Loki label selector:

```bash
--env qa                     # produces: {env="qa"}
--env qa --env-suffix "-mse" # produces: {env="qa-mse"}
--env dev200                 # produces: {env="dev200"}
```

If `--env` is not set, the tool reads the `ENVIRONMENT` env var, defaulting to `production`.

## Environment Variables

```bash
export GRAFANA_URL="https://your-grafana.example.com"
export GRAFANA_USER="<user_id>"
export GRAFANA_PASSWORD="<api_token>"
export ENVIRONMENT="qa"

grafana-log-analyzer --subscription-uuid "UUID" --mode errors
```
