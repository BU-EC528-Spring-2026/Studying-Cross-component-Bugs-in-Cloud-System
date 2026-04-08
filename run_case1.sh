#!/usr/bin/env bash
set -e

python3 /app/bin/capture_submit_intent.py \
  --command-file /app/examples/modern_yarn_buggy/submit.cmd \
  --json-out /tmp/modern_yarn_buggy-intent.json

python3 /app/bin/configprop_guard.py \
  --intent /tmp/modern_yarn_buggy-intent.json \
  --spark-defaults /app/examples/modern_yarn_buggy/spark-defaults.conf \
  --spark-env /app/examples/modern_yarn_buggy/spark-env.sh \
  --yarn-launch-log /app/examples/modern_yarn_buggy/yarn-launch.log \
  --policy /app/policies/modern_yarn_python_policy.json \
  --spark-version 3.5.7 \
  --hadoop-version 3.5.0 \
  --cluster-manager yarn \
  --deploy-mode cluster \
  --json-out /tmp/case1.json \
  --human-out /tmp/case1.txt

cat /tmp/case1.txt
