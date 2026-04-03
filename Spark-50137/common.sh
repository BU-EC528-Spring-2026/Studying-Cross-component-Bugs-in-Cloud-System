#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EC528_ROOT="${EC528_ROOT:-$HOME/EC528}"
SPARK_DIR="${SPARK_DIR:-$EC528_ROOT/src/spark-3.5.3}"
HIVE_LAB_DIR="${HIVE_LAB_DIR:-$EC528_ROOT/hive-lab}"

detect_docker() {
  if docker ps >/dev/null 2>&1; then
    DOCKER_CMD=(docker)
  elif sudo docker ps >/dev/null 2>&1; then
    DOCKER_CMD=(sudo docker)
  else
    echo "[ERROR] Docker is not installed or not available."
    exit 1
  fi

  COMPOSE_CMD=("${DOCKER_CMD[@]}" compose)
  if ! "${COMPOSE_CMD[@]}" version >/dev/null 2>&1; then
    echo "[ERROR] Docker Compose plugin is not available."
    exit 1
  fi
}

run_docker() {
  "${DOCKER_CMD[@]}" "$@"
}

run_compose() {
  "${COMPOSE_CMD[@]}" "$@"
}
