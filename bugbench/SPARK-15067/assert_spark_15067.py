#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

if len(sys.argv) != 3:
    print("usage: assert_spark_15067.py EVIDENCE_FILE RESULT_JSON", file=sys.stderr)
    sys.exit(2)

evidence_path = Path(sys.argv[1])
result_path = Path(sys.argv[2])
text = evidence_path.read_text(errors="replace")

# The original user intent is 1024M. The buggy Spark 1.6.x behavior appends
# a fixed default 256m later in the YARN executor launch command.
user_re = re.compile(r"-XX:MaxPermSize=1024[Mm]")
default_re = re.compile(r"-XX:MaxPermSize=256[mM]")
all_flags = re.findall(r"-XX:MaxPermSize=[^\s'\"]+", text)

result = {
    "bug": "SPARK-15067",
    "oracle": "both user-specified MaxPermSize and Spark's fixed 256m default appear in real launch evidence",
    "user_flag_found": bool(user_re.search(text)),
    "fixed_default_found": bool(default_re.search(text)),
    "max_perm_size_flags": all_flags,
    "reproduced": bool(user_re.search(text) and default_re.search(text)),
}
result_path.write_text(json.dumps(result, indent=2), encoding="utf-8")

if result["reproduced"]:
    print("PASS: SPARK-15067 reproduced in real Spark-on-YARN launch evidence.")
    print(json.dumps(result, indent=2))
    sys.exit(0)

print("FAIL: SPARK-15067 was not reproduced.")
print(json.dumps(result, indent=2))
sys.exit(1)
