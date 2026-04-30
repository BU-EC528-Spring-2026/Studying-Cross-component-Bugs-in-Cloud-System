# SPARK-15067 Real-Version Testbench Work Log

## Goal

Build a real-version Spark-on-YARN testbench for SPARK-15067 and collect actual NodeManager launch evidence rather than using a prepared `yarn-launch.log`.

## Target bug

- Bug ID: SPARK-15067
- Category: Configuration propagation / JVM option shadowing
- Affected Spark versions: Spark 1.6.0 and Spark 1.6.1
- Fixed version: Spark 2.0.0
- Expected historical symptom: the YARN executor launch command contains both the user-specified `-XX:MaxPermSize=1024M` and Spark's fixed default `-XX:MaxPermSize=256m`.

## Environment used

The testbench Docker image installed and ran:

- Spark: 1.6.1
- Hadoop/YARN: 2.7.1
- Java: OpenJDK 8 (`1.8.0_482`)

## What was executed

The testbench started a real HDFS/YARN stack inside the container:

- NameNode
- DataNode
- ResourceManager
- NodeManager

Then it submitted a real SparkPi job to YARN with the following relevant executor option:

```bash
--conf "spark.executor.extraJavaOptions=-XX:MaxPermSize=1024M -Dbugbench=SPARK-15067"
```

## Evidence collection method

The container-side automatic YARN evidence capture was brittle and stopped after the `=== Capturing real YARN launch evidence ===` phase. To avoid relying on that failing in-container capture step, the final stable workflow was:

1. Run the real Spark/YARN container without `--rm`.
2. Keep the stopped container.
3. Copy real runtime artifacts from the stopped container using `docker cp`.
4. Extract executor launch command evidence from NodeManager artifacts on the host side.

Runtime artifact sources copied from the container:

```text
/tmp/hadoop-yarn
/opt/hadoop-2.7.1/logs
/bench/out
```

Important real artifacts observed:

```text
debug-runtime/hadoop-yarn/local/.../launch_container.sh
debug-runtime/hadoop-yarn/logs/.../stderr
```

## Result

The final assertion result was:

```json
{
  "bug": "SPARK-15067",
  "oracle": "both user-specified MaxPermSize and Spark's fixed 256m default appear in real launch evidence",
  "user_flag_found": true,
  "fixed_default_found": false,
  "max_perm_size_flags": [
    "-XX:MaxPermSize=1024M",
    "-XX:MaxPermSize=1024M",
    "-XX:MaxPermSize=1024M",
    "-XX:MaxPermSize=1024M",
    "-XX:MaxPermSize=1024M"
  ],
  "reproduced": false
}
```

Real executor launch evidence included the user-specified flag:

```text
$JAVA_HOME/bin/java ... '-XX:MaxPermSize=1024M' '-Dbugbench=SPARK-15067' ... org.apache.spark.executor.CoarseGrainedExecutorBackend ...
```

However, the expected historical fixed default did not appear:

```text
-XX:MaxPermSize=256m
```

## Interpretation

The real-version testbench infrastructure is successful:

- Real Spark 1.6.1 was run.
- Real Hadoop/YARN 2.7.1 was run.
- A real SparkPi job was submitted to YARN.
- Real NodeManager launch artifacts were captured.
- The user-provided executor JVM option reached the YARN executor launch command.

The exact SPARK-15067 duplicate-flag symptom was not reproduced under the current Java 8 runtime because the Spark fixed default `-XX:MaxPermSize=256m` was not observed.

## Recommended next step

Do not spend more time on this testbench unless the project specifically needs exact SPARK-15067 reproduction. The most likely next lane would be a Java 7 runtime, because `MaxPermSize` is a pre-Java-8 PermGen option.

For the final project, keep this as a real-environment infrastructure result and add another configuration propagation bug that can be fully reproduced under a stable runtime.
