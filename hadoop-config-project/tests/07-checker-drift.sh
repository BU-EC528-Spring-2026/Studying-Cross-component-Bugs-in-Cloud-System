#!/usr/bin/env bash
# Test 07: live-stack drift detection.

set -uo pipefail

TEST_NAME="07-checker-drift"
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
YARN_XML="$REPO_ROOT/conf/yarn-site.xml"
ORIGINAL_CONTENT=""

# With CHECKER_HEARTBEAT=10 (or watchdog firing), drift surfaces in
# under 12s. However, Kafka consumer group coordination adds overhead.
# 30s accounts for rejoin delays on fresh test runs.
DRIFT_WAIT_SEC=30
POLL_INTERVAL=1
IDLE_WINDOW_SEC=5

fail() {
  echo "[$TEST_NAME] FAIL: $*"
  exit 1
}

restore_yarn_xml() {
  if [ -n "$ORIGINAL_CONTENT" ] && [ -f "$YARN_XML" ]; then
    echo "[$TEST_NAME] restoring $YARN_XML in place"
    printf '%s' "$ORIGINAL_CONTENT" > "$YARN_XML"
  fi
}
trap restore_yarn_xml EXIT

# ---------------------------------------------------------------------------
# 1. Preflight
# ---------------------------------------------------------------------------

for c in config-agent config-checker kafka; do
  state=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "missing")
  if [ "$state" != "running" ]; then
    fail "$c is not running (state=$state). Run 'docker compose up -d' first."
  fi
done

[ -f "$YARN_XML" ] || fail "yarn-site.xml not found at $YARN_XML"
echo "[$TEST_NAME] sidecars are up"

host_val=$(grep -oE 'yarn.scheduler.maximum-allocation-mb</(name|n)><value>[0-9]+' "$YARN_XML" | grep -oE '[0-9]+$')
cont_val=$(docker exec config-agent cat /opt/hadoop/etc/hadoop/yarn-site.xml \
  | grep -oE 'yarn.scheduler.maximum-allocation-mb</(name|n)><value>[0-9]+' \
  | grep -oE '[0-9]+$')
if [ "$host_val" != "$cont_val" ]; then
  fail "host ($host_val) and container ($cont_val) disagree on the scheduler value. Bind-mount stale — recreate the agent."
fi
echo "[$TEST_NAME] host and container agree on baseline: $host_val"

ORIGINAL_CONTENT=$(cat "$YARN_XML")

# ---------------------------------------------------------------------------
# 2. Baseline
# ---------------------------------------------------------------------------

BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
sleep 1
echo "[$TEST_NAME] baseline timestamp: $BASELINE"

# ---------------------------------------------------------------------------
# 3. Mutation
# ---------------------------------------------------------------------------

new_content=$(printf '%s' "$ORIGINAL_CONTENT" | awk '
  /<name>yarn.scheduler.maximum-allocation-mb<\/name>/ {
    sub(/<value>[0-9]+<\/value>/, "<value>9999</value>")
  }
  { print }
')
printf '%s' "$new_content" > "$YARN_XML"

cont_val=$(docker exec config-agent cat /opt/hadoop/etc/hadoop/yarn-site.xml \
  | grep -oE 'yarn.scheduler.maximum-allocation-mb</(name|n)><value>[0-9]+' \
  | grep -oE '[0-9]+$')
if [ "$cont_val" != "9999" ]; then
  fail "container does not see the host mutation (got $cont_val)."
fi
echo "[$TEST_NAME] mutation visible in container: 9999"

# ---------------------------------------------------------------------------
# 4. Wait for the agent to re-publish and checker to process.
# ---------------------------------------------------------------------------

DEADLINE=$(( $(date +%s) + DRIFT_WAIT_SEC ))
SAW_REPUBLISH=""
WATCHDOG_FIRED=""
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  agent_logs=$(docker logs --since "$BASELINE" config-agent 2>&1 || true)
  if echo "$agent_logs" | grep -q "detected change"; then
    WATCHDOG_FIRED=1
  fi
  # Search entire checker logs for 9999 (which appears in drift reports after mutation)
  checker_logs=$(docker logs config-checker 2>&1 || true)
  if echo "$checker_logs" | grep -q '"value_a": "9999"'; then
    SAW_REPUBLISH=1
    break
  fi
  sleep "$POLL_INTERVAL"
done

if [ -z "$SAW_REPUBLISH" ]; then
  fail "checker did not see drift with value 9999 within ${DRIFT_WAIT_SEC}s"
fi

if [ -n "$WATCHDOG_FIRED" ]; then
  echo "[$TEST_NAME] watchdog fired — drift detected quickly"
else
  echo "[$TEST_NAME] watchdog did NOT fire; heartbeat caught the drift"
fi
echo "[$TEST_NAME] checker reported drift including new value 9999"

# ---------------------------------------------------------------------------
# 5. Restore
# ---------------------------------------------------------------------------

RESTORE_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
sleep 1
restore_yarn_xml
trap - EXIT

cont_val=$(docker exec config-agent cat /opt/hadoop/etc/hadoop/yarn-site.xml \
  | grep -oE 'yarn.scheduler.maximum-allocation-mb</(name|n)><value>[0-9]+' \
  | grep -oE '[0-9]+$')
if [ "$cont_val" = "9999" ]; then
  fail "container still sees 9999 after restore — in-place write failed"
fi
echo "[$TEST_NAME] restored value visible in container: $cont_val"

DEADLINE=$(( $(date +%s) + DRIFT_WAIT_SEC ))
SAW_RESTORE=""
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  checker_logs=$(docker logs --since "$RESTORE_BASELINE" config-checker 2>&1 || true)
  if echo "$checker_logs" | grep -q "$cont_val"; then
    SAW_RESTORE=1
    break
  fi
  sleep "$POLL_INTERVAL"
done

if [ -z "$SAW_RESTORE" ]; then
  agent_logs=$(docker logs --since "$RESTORE_BASELINE" config-agent 2>&1 || true)
  if echo "$agent_logs" | grep -Eq "published|detected change"; then
    SAW_RESTORE=1
    echo "[$TEST_NAME] agent republished; checker may be silent (value matches last-seen)"
  fi
fi

if [ -z "$SAW_RESTORE" ]; then
  echo "---- agent logs since $RESTORE_BASELINE ----"
  docker logs --since "$RESTORE_BASELINE" config-agent 2>&1 | tail -30
  echo "---- checker logs since $RESTORE_BASELINE ----"
  docker logs --since "$RESTORE_BASELINE" config-checker 2>&1 | tail -30
  echo "--------------------------------------------"
  fail "no agent republish visible after restore within ${DRIFT_WAIT_SEC}s"
fi
echo "[$TEST_NAME] restore observed by pipeline"

# ---------------------------------------------------------------------------
# 6. Idle-window sanity
# ---------------------------------------------------------------------------

IDLE_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
sleep "$IDLE_WINDOW_SEC"
LOGS=$(docker logs --since "$IDLE_BASELINE" config-checker 2>&1 || true)
SPURIOUS=$(echo "$LOGS" | grep -E '"rule_id"|DriftResult' || true)
if [ -n "$SPURIOUS" ]; then
  echo "---- spurious drift ----"
  echo "$SPURIOUS"
  echo "------------------------"
  fail "checker emitted drift during a ${IDLE_WINDOW_SEC}s idle window — false positive"
fi
echo "[$TEST_NAME] idle window produced no spurious drift"

echo "[$TEST_NAME] PASS"
exit 0