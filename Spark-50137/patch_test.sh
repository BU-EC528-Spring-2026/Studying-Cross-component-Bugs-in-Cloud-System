#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

TARGET_FILE="$SPARK_DIR/sql/hive/src/test/scala/org/apache/spark/sql/hive/HiveExternalCatalogSuite.scala"
SNIPPET_FILE="$REPO_ROOT/patches/repro_test_snippet.scala"

if [ ! -f "$TARGET_FILE" ]; then
  echo "[ERROR] Target file not found: $TARGET_FILE"
  exit 1
fi

if grep -q "repro SPARK-50137 on 3.5.3" "$TARGET_FILE"; then
  echo "[INFO] Reproduction test already present."
  exit 0
fi

python3 - "$TARGET_FILE" "$SNIPPET_FILE" <<'PY'
from pathlib import Path
import sys

target = Path(sys.argv[1])
snippet_path = Path(sys.argv[2])

text = target.read_text()
snippet = snippet_path.read_text().rstrip() + "\n"

import_line = "import org.apache.logging.log4j.Level\n"
anchor_import = "import scala.util.control.NonFatal\n"

if "import org.apache.logging.log4j.Level" not in text:
    if anchor_import in text:
        text = text.replace(anchor_import, anchor_import + import_line, 1)
    else:
        raise RuntimeError("Could not find import anchor for Level import.")

last_brace = text.rfind("}")
if last_brace == -1:
    raise RuntimeError("Could not locate the end of HiveExternalCatalogSuite.scala")

text = text[:last_brace] + snippet + "\n}\n"
target.write_text(text)
print("[OK] Applied reproduction test patch.")
PY

grep -n "repro SPARK-50137" "$TARGET_FILE"
