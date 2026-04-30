#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
detect_docker

mkdir -p "$HIVE_LAB_DIR"
mkdir -p "$HIVE_LAB_DIR/pgdata"

# Ensure JDBC driver exists
mvn -q dependency:get -Dartifact=org.postgresql:postgresql:42.7.5

sed "s|__USER_HOME__|$HOME|g" "$REPO_ROOT/docker/docker-compose.template.yml" > "$HIVE_LAB_DIR/docker-compose.yml"

cd "$HIVE_LAB_DIR"
run_compose up -d

echo "[INFO] Waiting for Hive metastore port 9083..."
for i in $(seq 1 30); do
  if nc -z 127.0.0.1 9083 >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

run_compose ps
nc -zv 127.0.0.1 9083

# HiveServer2 is optional for SPARK-50137, so do not fail the script if 10000 is not ready
nc -zv 127.0.0.1 10000 || true

echo "[OK] Hive lab started."
