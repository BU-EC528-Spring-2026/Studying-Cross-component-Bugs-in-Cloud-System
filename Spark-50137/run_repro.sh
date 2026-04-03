#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

cd "$SPARK_DIR/sql/hive"
../../build/mvn \
  -Phive -Phive-thriftserver \
  -DwildcardSuites=org.apache.spark.sql.hive.HiveExternalCatalogSuite \
  test | tee /tmp/hiveexternalcatalogsuite.log
