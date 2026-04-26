#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUT_DIR:-/bench/out}"
mkdir -p "$OUT_DIR"

RESULT_TABLE="${RESULT_TABLE:-test_result01}"
MASTER="${BENCH_MASTER:-local[1]}"

run_lane() {
  local label="$1"
  local spark_home="$2"
  local out_prefix="$3"
  local run_dir="/tmp/spark11972-${label}"

  rm -rf "$run_dir"
  mkdir -p "$run_dir/warehouse" "$run_dir/tmp"
  cp /bench/query.sql "$run_dir/query.sql"

  echo "=== Running ${label} ==="
  echo "Spark home: $spark_home"
  echo "Master: $MASTER"
  echo "Result table: $RESULT_TABLE"

  set +e
  (
    cd "$run_dir"
    export SPARK_LOCAL_IP=127.0.0.1
    export SPARK_LOCAL_DIRS="$run_dir/tmp"
    "$spark_home/bin/spark-sql" \
      --master "$MASTER" \
      --conf "spark.sql.warehouse.dir=$run_dir/warehouse" \
      --conf "javax.jdo.option.ConnectionURL=jdbc:derby:;databaseName=$run_dir/metastore_db;create=true" \
      --hiveconf "RESULT_TABLE=$RESULT_TABLE" \
      -f "$run_dir/query.sql"
  ) > "$OUT_DIR/${out_prefix}.log" 2>&1
  local rc=$?
  set -e

  echo "$rc" > "$OUT_DIR/${out_prefix}.exitcode"
  echo "${label} exit code: $rc"
}

run_lane "buggy-spark-1.6.0" "$SPARK_160_HOME" "buggy-spark-1.6.0"
run_lane "fixed-spark-1.6.1" "$SPARK_161_HOME" "fixed-spark-1.6.1"

python3 /bench/assert_spark_11972.py \
  "$OUT_DIR/buggy-spark-1.6.0.log" \
  "$OUT_DIR/buggy-spark-1.6.0.exitcode" \
  "$OUT_DIR/fixed-spark-1.6.1.log" \
  "$OUT_DIR/fixed-spark-1.6.1.exitcode" \
  "$OUT_DIR/repro-result.json"

cat "$OUT_DIR/repro-result.json"
