#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
detect_docker

if [ -d "$HIVE_LAB_DIR" ]; then
  cd "$HIVE_LAB_DIR"
  run_compose down || true
fi

echo "[OK] Hive lab stopped."
