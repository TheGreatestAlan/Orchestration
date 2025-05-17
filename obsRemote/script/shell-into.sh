#!/usr/bin/env bash
set -euo pipefail

# --- bootstrap env --------------------------------------------------

# Get directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# .env lives in ../dev relative to script
ENV_FILE="$SCRIPT_DIR/../dev/docker-compose.env"
COMPOSE_FILE=run_obsidian_remote.yml

# Load and export everything from your .env
if [[ -f "$ENV_FILE" ]]; then
  echo "Sourcing $ENV_FILE…"
  set -o allexport
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +o allexport
else
  echo "⛔ Env file not found at $ENV_FILE" >&2
  exit 1
fi

# --- move into compose dir -----------------------------------------

# assume docker-compose.yml is one level up from script
cd "$SCRIPT_DIR/.."

# --- parse args ----------------------------------------------------

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <service-name> [shell]" >&2
  echo "Example: $0 web bash" >&2
  exit 1
fi

SERVICE="$1"
SHELL_CMD="${2:-bash}"  # default to bash, or sh if you prefer

# --- ensure it’s running, then shell in ----------------------------

# bring up just that service if needed
docker compose -f "$COMPOSE_FILE" up -d "$SERVICE"

# now exec into it
echo "🛠  Attaching to '$SERVICE' (running '$SHELL_CMD')"
docker compose -f "$COMPOSE_FILE" exec -it "$SERVICE" "$SHELL_CMD"

