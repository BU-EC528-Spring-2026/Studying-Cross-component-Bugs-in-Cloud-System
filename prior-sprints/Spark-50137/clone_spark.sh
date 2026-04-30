#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

mkdir -p "$EC528_ROOT/src"
cd "$EC528_ROOT/src"

if [ ! -d spark-3.5.3 ]; then
  git clone --branch v3.5.3 --depth 1 https://github.com/apache/spark.git spark-3.5.3
fi

cd "$SPARK_DIR"
git describe --tags --always
echo "[OK] Spark source ready at $SPARK_DIR"
