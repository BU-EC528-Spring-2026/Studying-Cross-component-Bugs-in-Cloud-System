# ConfigPropGuard v0.2

Prototype detector for the **Configuration Propagation / Feature Gating** layer of cross-system bugs.

## Recommended environment

### Primary development baseline (recommended for v0.2)
- OS: Ubuntu 22.04 LTS
- Java: OpenJDK 11
- Python: 3.10+
- Spark: 3.5.7
- Hadoop / YARN: 3.5.0
- Hive: not required for v0.2 runtime

### Optional evaluation lane (modern Spark 4 rule validation)
- OS: Ubuntu 22.04 LTS
- Hadoop / YARN: 3.5.0
- Spark: 4.1.1
- JDK for Hadoop daemons: 11
- JDK for Spark app: 17

### Historical regression lane
- Spark: 1.6.1
- Hadoop / YARN: 2.7.3
- Java: 8
- Representative historical issue: SPARK-15067

## Why this environment split?
The primary development baseline is intentionally **modern but low-friction**. Spark 3.5.7 still supports Java 8/11/17, so using Java 11 avoids the extra operational complexity introduced by Spark 4 on YARN, where Spark requires a newer JDK than the Hadoop daemons typically use. That makes Spark 3.5.7 + Hadoop 3.5.0 a better v0.2 development lane for a first configuration-propagation detector.

The Spark 4.1.1 lane is still useful, but as an **evaluation lane**: it creates a real configuration-propagation obligation around `JAVA_HOME`, which the detector can validate.

## What the prototype does
ConfigPropGuard v0.2 models the pipeline:

**submission intent -> normalized effective conf -> container launch evidence -> findings**

It includes:
- `bin/capture_submit_intent.py`: parses a `spark-submit` command into a normalized JSON manifest.
- `bin/configprop_guard.py`: analyzes config propagation and deployment gates.

## Rules implemented
- **CFG001**: raw downstream keys in submission properties
  - detects `yarn.*`, `dfs.*`, `fs.*`, `hive.*`, etc. injected directly instead of via `spark.hadoop.*` or `spark.hive.*`
- **CFG002**: cluster-mode `spark-env.sh` variables not propagated to the YARN Application Master
- **CFG003**: executor JVM-option collisions / shadowing
  - checks `spark.executor.defaultJavaOptions` vs `spark.executor.extraJavaOptions`
  - optionally checks the final YARN launch command if provided
- **CFG004**: missing YARN/Hadoop client configuration channel
  - checks for `HADOOP_CONF_DIR` / `YARN_CONF_DIR` or explicit site XML evidence
- **CFG005**: Spark 4 on YARN without explicit JDK propagation
  - checks `spark.yarn.appMasterEnv.JAVA_HOME` and `spark.executorEnv.JAVA_HOME`
- **CFG006**: policy-driven deployment gate checks
  - prototype policy engine for required keys and equal-value constraints

##  quick start
### Case1:
### 1) Build a submission manifest
```bash
python3 bin/capture_submit_intent.py \
  --command-file examples/modern_yarn_buggy/submit.cmd \
  --json-out reports/modern_yarn_buggy-intent.json
```

### 2) Run the detector
```bash
python3 bin/configprop_guard.py \
  --intent reports/modern_yarn_buggy-intent.json \
  --spark-defaults examples/modern_yarn_buggy/spark-defaults.conf \
  --spark-env examples/modern_yarn_buggy/spark-env.sh \
  --yarn-launch-log examples/modern_yarn_buggy/yarn-launch.log \
  --policy policies/modern_yarn_python_policy.json \
  --spark-version 3.5.7 \
  --hadoop-version 3.5.0 \
  --cluster-manager yarn \
  --deploy-mode cluster \
  --json-out reports/manual-modern-buggy-report.json \
  --human-out reports/manual-modern-buggy-report.txt
```
### 3) See buggy results
```bash
sed -n '1,200p' reports/manual-modern-buggy-report.txt
```
### 4) Regenerate fixed intents
```bash
python3 bin/capture_submit_intent.py \
  --command-file examples/my_case_01/submit.cmd \
  --json-out reports/my_case_01-intent.json
```
### 5) Run fixed
```bash
python3 bin/configprop_guard.py \
  --intent reports/my_case_01-intent.json \
  --spark-defaults examples/my_case_01/spark-defaults.conf \
  --spark-env examples/my_case_01/spark-env.sh \
  --yarn-launch-log examples/my_case_01/yarn-launch.log \
  --policy policies/modern_yarn_python_policy.json \
  --spark-version 3.5.7 \
  --hadoop-version 3.5.0 \
  --cluster-manager yarn \
  --deploy-mode cluster \
  --json-out reports/my_case_01-report.json \
  --human-out reports/my_case_01-report.txt
```
### 6) See fixed results
```bash
sed -n '1,200p' reports/my_case_01-report.txt
```

## Included demo datasets
- `examples/modern_yarn_buggy`
- `examples/modern_yarn_fixed`
- `examples/spark4_dual_jdk_buggy`
- `examples/spark4_dual_jdk_fixed`

## Expected demo outcome
- `modern_yarn_buggy`: FAIL (multiple findings)
- `modern_yarn_fixed`: PASS
- `spark4_dual_jdk_buggy`: FAIL (missing explicit JDK propagation)
- `spark4_dual_jdk_fixed`: PASS

### Case2:
### 1):
```bash
python3 bin/capture_submit_intent.py \
  --command-file examples/spark4_dual_jdk_buggy/submit.cmd \
  --json-out reports/spark4_dual_jdk_buggy-intent.json
```

### 2)
```bash
python3 bin/configprop_guard.py \
  --intent reports/spark4_dual_jdk_buggy-intent.json \
  --spark-defaults examples/spark4_dual_jdk_buggy/spark-defaults.conf \
  --spark-env examples/spark4_dual_jdk_buggy/spark-env.sh \
  --yarn-launch-log examples/spark4_dual_jdk_buggy/yarn-launch.log \
  --policy policies/spark4_dual_jdk_policy.json \
  --spark-version 4.1.1 \
  --hadoop-version 3.5.0 \
  --cluster-manager yarn \
  --deploy-mode cluster \
  --json-out reports/spark4_dual_jdk_buggy-report-v2.json \
  --human-out reports/spark4_dual_jdk_buggy-report-v2.txt
```

### 3)
```bash
sed -n '1,200p' reports/spark4_dual_jdk_buggy-report-v2.txt
```

### 4)
```bash
python3 bin/capture_submit_intent.py \
  --command-file examples/spark4_dual_jdk_fixed/submit.cmd \
  --json-out reports/spark4_dual_jdk_fixed-intent.json
```

### 5)
```bash
python3 bin/configprop_guard.py \
  --intent reports/spark4_dual_jdk_fixed-intent.json \
  --spark-defaults examples/spark4_dual_jdk_fixed/spark-defaults.conf \
  --spark-env examples/spark4_dual_jdk_fixed/spark-env.sh \
  --yarn-launch-log examples/spark4_dual_jdk_fixed/yarn-launch.log \
  --policy policies/spark4_dual_jdk_policy.json \
  --spark-version 4.1.1 \
  --hadoop-version 3.5.0 \
  --cluster-manager yarn \
  --deploy-mode cluster \
  --json-out reports/spark4_dual_jdk_fixed-report-v2.json \
  --human-out reports/spark4_dual_jdk_fixed-report-v2.txt
```

### 6)
```bash
sed -n '1,200p' reports/spark4_dual_jdk_fixed-report-v2.txt
```
