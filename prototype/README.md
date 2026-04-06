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

## Example quick start
### 1) Build a submission manifest
```bash
python3 bin/capture_submit_intent.py \
  --command-file examples/modern_yarn_buggy/submit.cmd \
  --json-out reports/modern-buggy-intent.json
```

### 2) Run the detector
```bash
python3 bin/configprop_guard.py \
  --intent reports/modern-buggy-intent.json \
  --spark-defaults examples/modern_yarn_buggy/spark-defaults.conf \
  --spark-env examples/modern_yarn_buggy/spark-env.sh \
  --yarn-launch-log examples/modern_yarn_buggy/yarn-launch.log \
  --policy policies/modern_yarn_python_policy.json \
  --spark-version 3.5.7 \
  --hadoop-version 3.5.0 \
  --cluster-manager yarn \
  --deploy-mode cluster \
  --json-out reports/modern-buggy-report.json \
  --human-out reports/modern-buggy-report.txt
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
