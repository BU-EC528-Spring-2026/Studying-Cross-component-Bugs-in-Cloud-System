#!/usr/bin/env bash
# demo.sh — screen recording walkthrough for hadoop-config-checker
# Run from the repo root: bash demo.sh

set -uo pipefail
cd "$HOME/EC528/hadoop-config-project"
unset CHECKER_KAFKA_BOOTSTRAP 2>/dev/null || true

# ---------------------------------------------------------------------------
# 1. Show the running stack
# ---------------------------------------------------------------------------

echo "=== 1. Running containers ==="
docker compose ps

# ---------------------------------------------------------------------------
# 2. Full live integration test suite
# ---------------------------------------------------------------------------

echo ""
echo "=== 2. Full live integration test suite ==="
bash tests/run-all.sh

# ---------------------------------------------------------------------------
# 3. Unit tests (no live cluster needed)
# ---------------------------------------------------------------------------

echo ""
echo "=== 3. Unit and integration tests ==="
python -m pytest tests/checker/ -v --tb=short

# ---------------------------------------------------------------------------
# 4. Baseline: cluster is clean
# ---------------------------------------------------------------------------

echo ""
echo "=== 4. Baseline: cluster is clean ==="
docker exec config-checker hadoopconf status --format text

echo ""
echo "=== 4b. Same baseline as JSON ==="
docker exec config-checker hadoopconf status --format json

# ---------------------------------------------------------------------------
# 5. Inject a bug: wrong fs.defaultFS in core-site.xml
# ---------------------------------------------------------------------------

echo ""
echo "=== 5. Injecting bug: fs.defaultFS -> hdfs://wronghost:8020 ==="
sed -i 's|hdfs://namenode:8020|hdfs://wronghost:8020|' conf/core-site.xml
echo "Mutation applied. Waiting for agents to republish (~60s heartbeat)..."
sleep 65

# ---------------------------------------------------------------------------
# 6. Drift detected: rule failures + causality graph trace
# ---------------------------------------------------------------------------

echo ""
echo "=== 6. Drift detected (text) ==="
docker exec config-checker hadoopconf status --format text

echo ""
echo "=== 6b. Drift detected (JSON) ==="
docker exec config-checker hadoopconf status --format json

# ---------------------------------------------------------------------------
# 7. Restore
# ---------------------------------------------------------------------------

echo ""
echo "=== 7. Restoring conf/core-site.xml ==="
sed -i 's|hdfs://wronghost:8020|hdfs://namenode:8020|' conf/core-site.xml
docker compose restart agent-namenode
echo "Restored. Waiting for agents to republish..."
sleep 65

echo ""
echo "=== 7b. Confirm clean after restore ==="
docker exec config-checker hadoopconf status --format text

# ---------------------------------------------------------------------------
# 8. Host-side status via external Kafka listener
# ---------------------------------------------------------------------------

echo ""
echo "=== 8. Host-side status via localhost:9094 ==="
hadoopconf status --bootstrap localhost:9094 --rules rules/hadoop-3.3.x.yaml --format text

# ---------------------------------------------------------------------------
# 9. Buggy-config evaluation harness
# ---------------------------------------------------------------------------

echo ""
echo "=== 9. Buggy-config evaluation harness ==="
bash tests/evaluate.sh

echo ""
echo "=== 9b. Evaluation summary ==="
cat tests/results/latest/summary.txt

echo ""
echo "=== Done ==="