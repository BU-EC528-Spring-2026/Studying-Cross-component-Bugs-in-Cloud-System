#!/usr/bin/env bash
# demo.sh — screen-recording walkthrough for hadoop-config-checker.
# Every step has a hard time bound. No call can hang the script.
#
# Run from the repo root:  bash tests/demo.sh

set -uo pipefail

REPO_ROOT="$HOME/EC528/hadoop-config-project"
cd "$REPO_ROOT"

unset CHECKER_KAFKA_BOOTSTRAP 2>/dev/null || true

CHECKER="config-checker"
STATUS_TIMEOUT=10        # seconds hadoopconf status waits for kafka
REPUB_WAIT=70            # seconds to wait after a config mutation (>1 heartbeat)
DOCKER_EXEC_TIMEOUT=45   # hard cap on any single docker exec call
PREFLIGHT_BUDGET=180     # total seconds we'll spend waiting for the stack

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# Run a command with a wall-clock timeout. Always returns; never hangs.
# Usage: bounded SECONDS cmd args...
bounded() {
  local secs="$1"; shift
  timeout --kill-after=5 "${secs}" "$@"
  return $?
}

# Inode-preserving in-place edit (safe on Docker Desktop bind mounts).
inplace_sed() {
  local expr="$1" file="$2"
  local tmp
  tmp=$(mktemp)
  sed "$expr" "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

status_text() {
  bounded "$DOCKER_EXEC_TIMEOUT" docker exec "$CHECKER" \
    hadoopconf status \
      --rules /etc/checker/rules/hadoop-3.3.x.yaml \
      --timeout "$STATUS_TIMEOUT" \
      --format text
  local rc=$?
  if [ $rc -eq 124 ]; then
    echo "(status_text timed out after ${DOCKER_EXEC_TIMEOUT}s — continuing)"
  fi
  return 0
}

status_json() {
  bounded "$DOCKER_EXEC_TIMEOUT" docker exec "$CHECKER" \
    hadoopconf status \
      --rules /etc/checker/rules/hadoop-3.3.x.yaml \
      --timeout "$STATUS_TIMEOUT" \
      --format json
  local rc=$?
  if [ $rc -eq 124 ]; then
    echo "(status_json timed out after ${DOCKER_EXEC_TIMEOUT}s — continuing)"
  fi
  return 0
}

section() {
  echo ""
  echo "=== $* ==="
}

# ---------------------------------------------------------------------------
# preflight: stack must be stable AND checker must answer status
# ---------------------------------------------------------------------------

section "Preflight: waiting for containers to be stable"

deadline=$(( $(date +%s) + PREFLIGHT_BUDGET ))
while true; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "ERROR: stack not stable within ${PREFLIGHT_BUDGET}s."
    docker compose ps || true
    exit 1
  fi

  restarting=$(docker compose ps --format json 2>/dev/null \
    | python3 -c "
import sys, json
out=[]
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    try:
        o=json.loads(line)
        if o.get('State')=='restarting':
            out.append(o.get('Name',''))
    except Exception:
        pass
print(' '.join(out))
" 2>/dev/null)

  if [ -z "$restarting" ]; then
    break
  fi
  echo "  still restarting: $restarting"
  sleep 5
done
echo "  all containers stable."

section "Preflight: waiting for checker to answer status"

deadline=$(( $(date +%s) + PREFLIGHT_BUDGET ))
while true; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "ERROR: checker did not become ready within ${PREFLIGHT_BUDGET}s."
    docker logs --tail=30 "$CHECKER" || true
    exit 1
  fi
  echo "  polling checker..."
  if bounded 20 docker exec "$CHECKER" hadoopconf status \
       --rules /etc/checker/rules/hadoop-3.3.x.yaml \
       --timeout 5 --format text >/dev/null 2>&1; then
    break
  fi
  sleep 5
done
echo "  checker is ready."

# ---------------------------------------------------------------------------
# 1. running stack
# ---------------------------------------------------------------------------

section "1. Running containers"
docker compose ps

# ---------------------------------------------------------------------------
# 2. baseline (clean)
# ---------------------------------------------------------------------------

section "2. Baseline: cluster is clean (text)"
status_text

section "2b. Same baseline as JSON"
status_json

# ---------------------------------------------------------------------------
# 3. inject a bug
# ---------------------------------------------------------------------------

section "3. Injecting bug: fs.defaultFS -> hdfs://wronghost:8020"
inplace_sed 's|hdfs://namenode:8020|hdfs://wronghost:8020|' conf/core-site.xml
echo "Mutation applied. Waiting ${REPUB_WAIT}s for agents to republish..."
sleep "$REPUB_WAIT"

# ---------------------------------------------------------------------------
# 4. drift detected
# ---------------------------------------------------------------------------

section "4. Drift detected (text)"
status_text

section "4b. Drift detected (JSON, root_causes shows graph trace)"
status_json

# ---------------------------------------------------------------------------
# 5. restore
# ---------------------------------------------------------------------------

section "5. Restoring conf/core-site.xml"
inplace_sed 's|hdfs://wronghost:8020|hdfs://namenode:8020|' conf/core-site.xml
bounded 60 docker compose restart agent-namenode || \
  echo "(agent-namenode restart timed out — continuing)"
echo "Restored. Waiting ${REPUB_WAIT}s for agents to republish..."
sleep "$REPUB_WAIT"

section "5b. Confirm clean after restore"
status_text

# ---------------------------------------------------------------------------
# done
# ---------------------------------------------------------------------------

section "Done"