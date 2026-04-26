#!/usr/bin/env bash
set -u

IMAGE="${1:-spark-15067-bench:no-yarn-cli}"
CONTAINER_NAME="spark15067-debug"
ROOT_DIR="$(pwd)"
OUT_DIR="$ROOT_DIR/out"
DEBUG_DIR="$ROOT_DIR/debug-runtime"

echo "=== Running SPARK-15067 container without --rm ==="
echo "Image: $IMAGE"

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
rm -rf "$OUT_DIR" "$DEBUG_DIR"
mkdir -p "$OUT_DIR" "$DEBUG_DIR"

set +e
docker run --name "$CONTAINER_NAME" -v "$OUT_DIR:/bench/out" "$IMAGE"
RUN_RC=$?
set -e

echo "=== Container exited with code $RUN_RC ==="
echo "=== Copying runtime artifacts from stopped container ==="

docker cp "$CONTAINER_NAME:/bench/out" "$DEBUG_DIR/bench-out" >/dev/null 2>&1 || true
docker cp "$CONTAINER_NAME:/tmp/hadoop-yarn" "$DEBUG_DIR/hadoop-yarn" >/dev/null 2>&1 || true
docker cp "$CONTAINER_NAME:/opt/hadoop-2.7.1/logs" "$DEBUG_DIR/hadoop-logs" >/dev/null 2>&1 || true

echo "=== Building host-side launch evidence ==="
{
  echo "### Runtime artifact file list"
  find "$DEBUG_DIR" -type f 2>/dev/null | sort | sed "s#^$ROOT_DIR/##" | head -500 || true
  echo

  echo "### MaxPermSize lines across copied runtime artifacts"
  grep -R -n -- "-XX:MaxPermSize" "$DEBUG_DIR" 2>/dev/null || true
  echo

  echo "### launch_container.sh / default_container_executor.sh snippets"
  find "$DEBUG_DIR" -type f \( -name 'launch_container.sh' -o -name 'default_container_executor.sh' -o -name 'default_container_executor_session.sh' \) 2>/dev/null | sort | while read -r f; do
    echo "--- FILE: ${f#$ROOT_DIR/}"
    grep -n "MaxPermSize\|java\|SPARK-15067\|CoarseGrainedExecutorBackend" "$f" 2>/dev/null || true
    echo
  done
} > "$OUT_DIR/yarn-launch-evidence.txt"

if [ -f "assert_spark_15067.py" ]; then
  echo "=== Running assertion ==="
  set +e
  python3 assert_spark_15067.py "$OUT_DIR/yarn-launch-evidence.txt" "$OUT_DIR/repro-result.json"
  ASSERT_RC=$?
  set -e
else
  echo "assert_spark_15067.py not found; writing fallback JSON"
  python3 - <<'PY'
from pathlib import Path
import json
text = Path('out/yarn-launch-evidence.txt').read_text(errors='ignore')
result = {
  'reproduced': ('-XX:MaxPermSize=1024M' in text and '-XX:MaxPermSize=256m' in text),
  'has_user_value_1024M': '-XX:MaxPermSize=1024M' in text,
  'has_fixed_value_256m': '-XX:MaxPermSize=256m' in text,
  'evidence_file': 'out/yarn-launch-evidence.txt'
}
Path('out/repro-result.json').write_text(json.dumps(result, indent=2))
PY
  ASSERT_RC=0
fi

echo "=== Result files ==="
ls -lh "$OUT_DIR" || true

echo "=== repro-result.json ==="
cat "$OUT_DIR/repro-result.json" 2>/dev/null || true

echo
echo "=== MaxPermSize grep ==="
grep -R -- "-XX:MaxPermSize" "$OUT_DIR" 2>/dev/null || true

echo
echo "Done. Evidence: out/yarn-launch-evidence.txt"
echo "Assertion exit code: ${ASSERT_RC:-0}"
exit 0
