#!/usr/bin/env bash
set -euo pipefail

# --- bootstrap env --------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../dev/docker-compose.env"
COMPOSE_FILE=run_obsidian_remote.yml

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

cd "$SCRIPT_DIR/.."

# --- parse args ----------------------------------------------------

FOLLOW=false
SERVICE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--tail)
      FOLLOW=true
      shift
      ;;
    -*)
      echo "Unknown flag: $1" >&2
      echo "Usage: $0 [ -t | --tail ] <service>" >&2
      exit 1
      ;;
    *)
      SERVICE="$1"
      shift
      ;;
  esac
done

if [[ -z "$SERVICE" ]]; then
  echo "Usage: $0 [ -t | --tail ] <service>" >&2
  exit 1
fi

# --- build echo message --------------------------------------------

if [[ "$FOLLOW" == true ]]; then
  TAIL_MSG=" (tailing)"
else
  TAIL_MSG=""
fi

echo "📋 Fetching logs for '$SERVICE'$TAIL_MSG…"

# --- fetch logs -----------------------------------------------------

if [[ "$FOLLOW" == true ]]; then
  docker compose -f "$COMPOSE_FILE" logs -f "$SERVICE"
else
  docker compose -f "$COMPOSE_FILE" logs "$SERVICE"
fi

