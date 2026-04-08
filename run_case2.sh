#!/usr/bin/env bash
set -e

python3 /app/bin/capture_submit_intent.py \
  --command-file /app/examples/spark4_dual_jdk_buggy/submit.cmd \
  --json-out /tmp/spark4_buggy-intent.json

python3 /app/bin/configprop_guard.py \
  --intent /tmp/spark4_buggy-intent.json \
  --spark-defaults /app/examples/spark4_dual_jdk_buggy/spark-defaults.conf \
  --spark-env /app/examples/spark4_dual_jdk_buggy/spark-env.sh \
  --yarn-launch-log /app/examples/spark4_dual_jdk_buggy/yarn-launch.log \
  --policy /app/policies/spark4_dual_jdk_policy.json \
  --spark-version 4.1.1 \
  --hadoop-version 3.5.0 \
  --cluster-manager yarn \
  --deploy-mode cluster \
  --json-out /tmp/case2.json \
  --human-out /tmp/case2.txt

cat /tmp/case2.txt
