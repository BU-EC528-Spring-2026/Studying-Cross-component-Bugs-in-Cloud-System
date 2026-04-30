#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

cd "$SPARK_DIR"
./build/mvn -pl sql/hive -am -Phive -Phive-thriftserver -DskipTests test-compile
