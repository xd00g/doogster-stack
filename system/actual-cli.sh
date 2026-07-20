#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="${DOOGSTER_STACK_DIR:-$HOME/stack}"
cd "$STACK_DIR"
exec docker compose --profile tools run --rm actual-cli "$@"