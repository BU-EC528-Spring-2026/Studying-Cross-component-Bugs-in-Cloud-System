#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] Looking for reproduction evidence in /tmp/hiveexternalcatalogsuite.log"

grep -n "repro SPARK-50137" /tmp/hiveexternalcatalogsuite.log || true
grep -n "repro_50137" /tmp/hiveexternalcatalogsuite.log || true
grep -n "Hive compatible way" /tmp/hiveexternalcatalogsuite.log || true
grep -n "Could not persist \`default\`.\`repro_50137\`" /tmp/hiveexternalcatalogsuite.log || true
tail -n 80 /tmp/hiveexternalcatalogsuite.log
