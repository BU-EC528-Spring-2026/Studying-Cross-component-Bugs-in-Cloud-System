#!/usr/bin/env bash
set -euo pipefail

mkdir -p reports

# Case 1 buggy (expect FAIL)
python3 bin/capture_submit_intent.py \
  --command-file examples/modern_yarn_buggy/submit.cmd \
  --json-out reports/modern_yarn_buggy-intent.json
python3 bin/configprop_guard.py \
  --intent reports/modern_yarn_buggy-intent.json \
  --spark-defaults examples/modern_yarn_buggy/spark-defaults.conf \
  --spark-env examples/modern_yarn_buggy/spark-env.sh \
  --yarn-launch-log examples/modern_yarn_buggy/yarn-launch.log \
  --policy policies/modern_yarn_python_policy.json \
  --spark-version 3.5.7 --hadoop-version 3.5.0 \
  --cluster-manager yarn --deploy-mode cluster \
  --json-out reports/modern_yarn_buggy-report.json \
  --human-out reports/modern_yarn_buggy-report.txt

# Case 1 fixed (expect PASS)
python3 bin/capture_submit_intent.py \
  --command-file examples/modern_yarn_fixed/submit.cmd \
  --json-out reports/modern_yarn_fixed-intent.json
python3 bin/configprop_guard.py \
  --intent reports/modern_yarn_fixed-intent.json \
  --spark-defaults examples/modern_yarn_fixed/spark-defaults.conf \
  --spark-env examples/modern_yarn_fixed/spark-env.sh \
  --yarn-launch-log examples/modern_yarn_fixed/yarn-launch.log \
  --policy policies/modern_yarn_python_policy.json \
  --spark-version 3.5.7 --hadoop-version 3.5.0 \
  --cluster-manager yarn --deploy-mode cluster \
  --json-out reports/modern_yarn_fixed-report.json \
  --human-out reports/modern_yarn_fixed-report.txt

# Case 2 buggy (expect WARN)
python3 bin/capture_submit_intent.py \
  --command-file examples/spark4_dual_jdk_buggy/submit.cmd \
  --json-out reports/spark4_dual_jdk_buggy-intent.json
python3 bin/configprop_guard.py \
  --intent reports/spark4_dual_jdk_buggy-intent.json \
  --spark-defaults examples/spark4_dual_jdk_buggy/spark-defaults.conf \
  --spark-env examples/spark4_dual_jdk_buggy/spark-env.sh \
  --yarn-launch-log examples/spark4_dual_jdk_buggy/yarn-launch.log \
  --policy policies/spark4_dual_jdk_policy.json \
  --spark-version 4.1.1 --hadoop-version 3.5.0 \
  --cluster-manager yarn --deploy-mode cluster \
  --json-out reports/spark4_dual_jdk_buggy-report.json \
  --human-out reports/spark4_dual_jdk_buggy-report.txt

# Case 2 fixed (expect PASS)
python3 bin/capture_submit_intent.py \
  --command-file examples/spark4_dual_jdk_fixed/submit.cmd \
  --json-out reports/spark4_dual_jdk_fixed-intent.json
python3 bin/configprop_guard.py \
  --intent reports/spark4_dual_jdk_fixed-intent.json \
  --spark-defaults examples/spark4_dual_jdk_fixed/spark-defaults.conf \
  --spark-env examples/spark4_dual_jdk_fixed/spark-env.sh \
  --yarn-launch-log examples/spark4_dual_jdk_fixed/yarn-launch.log \
  --policy policies/spark4_dual_jdk_policy.json \
  --spark-version 4.1.1 --hadoop-version 3.5.0 \
  --cluster-manager yarn --deploy-mode cluster \
  --json-out reports/spark4_dual_jdk_fixed-report.json \
  --human-out reports/spark4_dual_jdk_fixed-report.txt

# Full reports
for f in modern_yarn_buggy modern_yarn_fixed spark4_dual_jdk_buggy spark4_dual_jdk_fixed; do
  echo ""
  echo "================================================================"
  echo "  $f"
  echo "================================================================"
  cat "reports/${f}-report.txt"
done

# Summary
echo ""
echo "=== SUMMARY ==="
for f in modern_yarn_buggy modern_yarn_fixed spark4_dual_jdk_buggy spark4_dual_jdk_fixed; do
  printf "%-30s %s\n" "$f" "$(head -1 reports/${f}-report.txt)"
done
