#!/usr/bin/env bash
set -euo pipefail

sudo apt update
sudo apt install -y \
  openjdk-11-jdk \
  git \
  maven \
  docker.io \
  build-essential \
  netcat-openbsd

# Compose package name differs across Ubuntu variants
if ! docker compose version >/dev/null 2>&1; then
  sudo apt install -y docker-compose-v2 || sudo apt install -y docker-compose-plugin || true
fi

sudo systemctl enable --now docker || true

mkdir -p "$HOME/EC528"
mkdir -p "$HOME/EC528/src"
mkdir -p "$HOME/EC528/hive-lab"

# JDBC driver needed by Hive containers
mvn -q dependency:get -Dartifact=org.postgresql:postgresql:42.7.5

echo "[OK] Base environment ready."
java -version
mvn -version
docker --version
docker compose version
