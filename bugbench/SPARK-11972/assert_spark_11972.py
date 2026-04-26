#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

BUGGY_LOG = Path(sys.argv[1])
BUGGY_RC = Path(sys.argv[2])
FIXED_LOG = Path(sys.argv[3])
FIXED_RC = Path(sys.argv[4])
OUT_JSON = Path(sys.argv[5])

buggy_text = BUGGY_LOG.read_text(errors="replace") if BUGGY_LOG.exists() else ""
fixed_text = FIXED_LOG.read_text(errors="replace") if FIXED_LOG.exists() else ""

def read_rc(path: Path):
    try:
        return int(path.read_text().strip())
    except Exception:
        return None

buggy_rc = read_rc(BUGGY_RC)
fixed_rc = read_rc(FIXED_RC)

patterns = [
    r"cannot recognize input near '\$' '\{' 'hiveconf'",
    r"NoViableAltException",
    r"\$\{hiveconf:RESULT_TABLE\}",
    r"Error in query:.*hiveconf",
]

buggy_signals = [p for p in patterns if re.search(p, buggy_text, flags=re.IGNORECASE | re.DOTALL)]
fixed_signals = [p for p in patterns[:2] + [r"Error in query:.*hiveconf"] if re.search(p, fixed_text, flags=re.IGNORECASE | re.DOTALL)]

result = {
    "bug": "SPARK-11972",
    "oracle": "Spark 1.6.0 should show hiveconf variable substitution failure; Spark 1.6.1 should run the same SQL without the hiveconf parser failure",
    "buggy_version": "1.6.0",
    "fixed_version": "1.6.1",
    "buggy_exit_code": buggy_rc,
    "fixed_exit_code": fixed_rc,
    "buggy_hiveconf_failure_found": bool(buggy_signals),
    "buggy_failure_patterns": buggy_signals,
    "fixed_hiveconf_failure_found": bool(fixed_signals),
    "fixed_failure_patterns": fixed_signals,
    "fixed_exit_success": fixed_rc == 0,
    "reproduced": bool(buggy_signals) and not bool(fixed_signals) and fixed_rc == 0,
}

OUT_JSON.write_text(json.dumps(result, indent=2) + "\n")

if result["reproduced"]:
    print("PASS: SPARK-11972 reproduced: Spark 1.6.0 fails while Spark 1.6.1 passes.")
    sys.exit(0)

print("WARN: SPARK-11972 oracle not fully satisfied. See repro-result.json and logs.")
sys.exit(2)
