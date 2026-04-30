# EC528 environment profile for ConfigPropGuard v0.2

## Final recommendation

### A. Primary development baseline
Use this lane to build the prototype and run the first experiments.

- **OS**: Ubuntu 22.04 LTS
- **Java**: OpenJDK 11
- **Python**: 3.10+
- **Spark**: 3.5.7
- **Hadoop / YARN**: 3.5.0
- **Hive runtime**: omitted in v0.2

### Why A is the main lane
This lane keeps the stack modern while avoiding a preventable bring-up problem: Spark 4 on YARN introduces a *second JDK propagation problem* by design. That is valuable later, but it is noise while the first prototype is still stabilizing.

Use lane A to validate the core detector on:
- raw downstream config injection,
- missing AM propagation,
- JVM option collisions,
- missing YARN/Hadoop client configuration,
- deployment-policy gates.

## B. Optional modern evaluation lane
Use this lane after the v0.2 detector is stable.

- **OS**: Ubuntu 22.04 LTS
- **Spark**: 4.1.1
- **Hadoop / YARN**: 3.5.0
- **Hadoop daemon JDK**: 11
- **Spark application JDK**: 17

### Why B is not the initial lane
Spark 4 on YARN is an *excellent* stress case for configuration propagation, but a *poor* first bring-up target:
- Spark 4 requires Java 17/21.
- Spark’s YARN documentation explicitly warns that Hadoop does not support Java 17 as of Hadoop 3.4.1, so Spark applications need a different JDK configured via propagation.
- That means missing `spark.yarn.appMasterEnv.JAVA_HOME` / `spark.executorEnv.JAVA_HOME` can break launches before other rules are even exercised.

So B is a very good **evaluation lane**, not the first **development lane**.

## C. Historical regression lane
Use this lane only when you want a representative historical bug replay.

- **Spark**: 1.6.1
- **Hadoop / YARN**: 2.7.3
- **Java**: 8
- **Representative case**: SPARK-15067

## Language choice
- **Prototype implementation**: Python 3.10+
- **Later instrumentation / deeper hooks**: Java or Scala

## Minimal runtime assumptions for v0.2
- Spark client has access to `spark-submit`.
- YARN-side launch evidence is available as either:
  - NodeManager launch script,
  - aggregated launch log,
  - or a manually captured Java command line.
- One of the following is present for Hadoop/YARN client configuration:
  - `HADOOP_CONF_DIR`,
  - `YARN_CONF_DIR`,
  - or explicit `core-site.xml` / `yarn-site.xml` in the detector inputs.

## Version matrix rationale
The matrix is designed around **prototype development cost**, not just “newest version wins”:
- **Spark 3.5.7** is current enough to be relevant and still accepts Java 11.
- **Hadoop 3.5.0** is the current stable Hadoop line.
- **Spark 4.1.1** remains valuable for later evaluation because it creates a real, document-backed propagation obligation around `JAVA_HOME`.
