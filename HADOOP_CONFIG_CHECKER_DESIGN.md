# Hadoop Configuration Checker: Design Document

**Project:** EC528 — Studying Cross-component Bugs in Cloud Systems  
**Implementation base:** `hadoop-config-project/`  
**Related course files:** `prior-sprints/`  
**Document purpose:** consolidate the design of the Hadoop configuration checker, connect it to the evaluation results, and clarify how the checker relates to the real-version bugbenches.

---

## 1. Executive Summary

This project implements a configuration observability and consistency checker for Hadoop-family deployments. The target environment contains multiple independently configured systems, including HDFS, YARN, MapReduce, Hive, Spark, Kafka, and ZooKeeper. These services often read related configuration values from different XML files, environment variables, JVM flags, and service-specific config sources. When the same logical value diverges across components, the runtime symptom may appear far from the actual root cause.

The checker addresses this by collecting configuration snapshots from multiple services, normalizing those snapshots into a common model, pushing them through Kafka, and running rule validation, drift detection, and root-cause tracing. The current implementation is centered on `hadoop-config-project`, while the real-version bugbenches in the course repository validate the broader configuration-propagation failure model against historical Spark bugs.

The design goal is not to detect every possible Hadoop bug. The current scope is narrower and more defensible: detect configuration drift, cross-source disagreement, invalid value relationships, and likely propagation failures before they produce confusing runtime failures.

---

## 2. Problem Statement

Cross-component bugs in Hadoop-family systems are difficult because:

1. Multiple systems participate in one runtime behavior.
2. Each system may load configuration from a different source.
3. A root cause in a low-level configuration file may surface as a Spark, Hive, or YARN runtime symptom.
4. Logs are distributed across containers and components.
5. Manual inspection is slow, non-repeatable, and error-prone.

A typical failure is not simply “a config key is missing.” More often, the same logical configuration value exists in multiple places but silently diverges. For example, `fs.defaultFS` may be correct in `hadoop.env` but wrong in `core-site.xml`, or Hive may still use an old HDFS NameNode while Spark and YARN publish a newer one.

The checker is designed to answer:

> Are the configuration values observed across services and sources mutually consistent, and if not, which downstream services are likely affected?

---

## 3. Design Goals and Non-Goals

### 3.1 Goals

The checker should:

- Collect Hadoop-style XML configuration from service containers.
- Collect environment-file and JVM `-Dkey=value` configuration where services expose settings outside XML.
- Normalize heterogeneous configuration sources into a shared snapshot model.
- Publish snapshots from agents to Kafka.
- Consume snapshots and detect temporal drift, cross-source drift, and rule violations.
- Validate cross-service invariants using a YAML rule file.
- Provide a causality graph that explains likely downstream effects.
- Support both local CLI checks and live-cluster evaluation.
- Produce human-readable and JSON outputs suitable for debugging, CI, and monitoring.

### 3.2 Non-Goals

The checker is not currently intended to:

- Prove the absence of all cross-component bugs.
- Detect arbitrary concurrency, scheduling, security-token, or data-plane semantic bugs.
- Replace a full production observability platform.
- Automatically infer every possible invariant without user-defined rules.
- Fully integrate the real-version Spark bugbenches into the Kafka-based checker pipeline. The bugbenches are currently an evaluation layer.

---

## 4. System Overview

The system is organized as a producer-consumer pipeline:

```text
Service configuration files / env / JVM flags
        ↓
config-agent sidecars
        ↓
ConfigSnapshot messages
        ↓
Kafka topic: hadoop-config-snapshots
        ↓
config-checker consumer
        ↓
Drift detection + YAML validation + causality graph
        ↓
Text / JSON status, drift reports, root-cause traces
```

Each monitored service has an agent sidecar. The agent reads configuration sources mounted from the corresponding service. The checker container consumes all published snapshots from Kafka and analyzes the global configuration state.

This decouples collection from analysis. Agents do not need to know the full rule set, and the checker does not directly poll Hadoop HTTP endpoints. The checker reasons over snapshots. This design enables users of this tool to easily connect to existing systems without messing with too much. Detailed more in our other docs. 

---

## 5. Core Components

### 5.1 Collectors

Collectors transform heterogeneous configuration formats into a common snapshot representation.

#### XML Collector

The XML collector parses Hadoop-style `*-site.xml` files such as:

- `core-site.xml`
- `hdfs-site.xml`
- `yarn-site.xml`
- `mapred-site.xml`
- `hive-site.xml`

It extracts key-value pairs and tags them with service, source, host, and file path metadata.

#### Environment / JVM Collector

The environment collector parses:

- `KEY=VALUE` files such as `hadoop.env`
- `export KEY=VALUE` forms
- JVM flags such as `-Dkey=value`

This is necessary because not all services expose configuration through XML. For example, Hive-related service options may appear in JVM flags rather than in mounted XML files.

### 5.2 ConfigSnapshot Model

All collected data is normalized into `ConfigSnapshot` objects. A snapshot represents the configuration state for one source and one service at one point in time.

Conceptually, a snapshot contains:

```text
agent_id
service
source type
source path
host
timestamp
properties: key-value map
```

This normalized representation allows the checker to compare values across services, files, and source types.

### 5.3 Kafka Agent

The agent runs as a sidecar. Its responsibilities are:

1. Watch local mounted configuration files.
2. Re-collect snapshots after a file change or heartbeat.
3. Publish snapshots to Kafka.
4. Remain stateless so it can be restarted without losing global state.

The agent supports both change-driven updates and periodic heartbeats. This makes the system responsive to edits while still robust to missed file events.

### 5.4 Checker Consumer

The checker consumer reads snapshots from Kafka and maintains the latest known configuration state for each agent. It then runs:

- temporal drift detection,
- cross-source drift detection,
- YAML rule validation,
- causality graph analysis.

The output can be inspected through the long-running checker logs or through the `hadoopconf status` CLI.

---

## 6. Detection Logic

### 6.1 Temporal Drift

Temporal drift compares a newly received snapshot with a previous snapshot from the same agent and source. If a key changes over time, the checker reports a drift event.

Example:

```text
yarn.scheduler.maximum-allocation-mb: 2048 → 9999
```

This catches local configuration changes after the cluster has already started.

### 6.2 Cross-Source Drift

Cross-source drift compares different sources for the same service. For example, the same key may appear in both XML and environment configuration.

Example:

```text
core-site.xml: fs.defaultFS = hdfs://wronghost:8020
hadoop.env:   fs.defaultFS = hdfs://namenode:8020
```

This reveals inconsistencies that would not be visible by inspecting only one file.

### 6.3 Cross-Service Propagation Rules

The rule engine validates invariants across services. For example, the `fs-defaultfs-propagation` rule checks whether `fs.defaultFS` agrees across NameNode, DataNode, ResourceManager, NodeManager, HiveServer2, Spark client, and Hive Metastore.

The reference rule set includes checks such as:

- HDFS replication must not exceed maximum replication.
- YARN scheduler maximum allocation must not exceed NodeManager memory capacity.
- `fs.defaultFS` must propagate consistently across services.
- Hive warehouse location must reference the configured NameNode.
- XML and environment values must agree when they define the same key.

### 6.4 Causality Graph

The causality graph turns a drift result into a root-cause trace. Instead of only reporting a mismatched key, it explains which downstream services may be affected.

For example, a wrong `fs.defaultFS` can be traced to downstream effects in:

- HiveServer2,
- Hive Metastore,
- Spark client.

This is a key difference from a simple linter: the checker does not only say “there is drift”; it also gives a likely propagation path.

---

## 7. CLI Interface

The main CLI is `hadoopconf`.

### 7.1 `collect`

Collects snapshots from local files and prints them.

Example:

```bash
hadoopconf collect conf/ --service namenode --env-file hadoop.env --detect-drift
```

This tests whether the collectors can parse local XML and environment configuration.

### 7.2 `validate`

Validates local configuration against a YAML rule file.

Example:

```bash
hadoopconf validate conf/ rules/hadoop-3.3.x.yaml --service namenode --env-file hadoop.env
```

This is useful as a local pre-deployment gate.

### 7.3 `status`

Reads the Kafka-backed global view of all agent snapshots and applies rules.

Host-side example:

```bash
hadoopconf status --bootstrap localhost:9094 --rules rules/hadoop-3.3.x.yaml --format json
```

Inside the checker container:

```bash
docker compose exec checker hadoopconf status --format text
```

`status` is the preferred command for live-cluster correctness because it sees every agent’s published view, including Kafka, ZooKeeper, Hive, and JVM-flag-derived snapshots. Local `validate` cannot see those distributed runtime views.

---

## 8. Docker and Deployment Design

### 8.1 Base Hadoop Stack

The Docker Compose stack includes service containers for the Hadoop-family test fixture, including:

- HDFS NameNode,
- HDFS DataNode,
- YARN ResourceManager,
- YARN NodeManager,
- Hive Metastore,
- HiveServer2,
- Spark master / worker / client,
- Kafka,
- ZooKeeper,
- Postgres for Hive Metastore.

### 8.2 Agent and Checker Sidecars

The updated `docker-compose.override.yml` adds checker-specific sidecars:

- `config-checker`: central consumer and analysis process,
- `config-agent-*`: per-service collectors for NameNode, DataNode, ResourceManager, NodeManager, Spark client, Hive, Kafka, and ZooKeeper.

The checker and agents communicate through Kafka.

### 8.3 Kafka Connectivity

Two Kafka endpoints are relevant:

- `kafka:9092` inside the Docker network,
- `localhost:9094` from the host machine.

This allows both internal containers and host-side CLI commands to inspect the same snapshot stream.

---

## 9. Evaluation Strategy

The evaluation uses three layers.

### 9.1 Unit and Integration Tests

The Python test suite validates individual checker components without requiring a live cluster. It covers collectors, snapshot models, drift detection, validation rules, causality graph behavior, CLI behavior, and false-positive checks.

The provided evaluation result shows that the full pytest suite passed with 279 tests.

### 9.2 Live Cluster Functionality Tests

The `tests/run-all.sh` script runs ten live tests. The first six verify the underlying cluster services:

1. HDFS round-trip,
2. YARN Pi job,
3. Hive table lifecycle,
4. Kafka produce / consume,
5. ZooKeeper znode operations,
6. SparkPi on YARN.

The last four validate checker-specific behavior:

7. single-agent drift detection,
8. multi-agent propagation,
9. cross-service YARN scheduler constraint,
10. causality tracing.

The provided results show `passed: 10` and `failed: 0`.

### 9.3 Scenario Evaluation Harness

`tests/evaluate.sh` is the automated correctness harness. For each buggy configuration scenario, it:

1. verifies the baseline is clean,
2. injects a mutated configuration into `conf/`,
3. waits for agents to republish snapshots,
4. polls `hadoopconf status` until the expected rule fires,
5. checks checker logs for the expected report,
6. restores the clean baseline,
7. writes a full result set to `tests/results/<timestamp>/` and `tests/results/latest`.

The output includes:

- `summary.txt`,
- `summary.json`,
- `before.json`,
- `detected.json`,
- `post-restore.json`,
- `checker-report.json`,
- `timing.json`,
- `inject.diff`,
- `scenario.txt`.

This demonstrates not only detection, but also restoration and repeatability.

---

## 10. Manual Drift Injection Example

The evaluation document includes a manual `fs.defaultFS` drift example.

### 10.1 Inject Bug

```bash
sed -i 's|hdfs://namenode:8020|hdfs://wronghost:8020|' conf/core-site.xml
docker compose restart agent-namenode
```

This mutates the HDFS NameNode address in `core-site.xml`.

### 10.2 Detection Result

The checker reports:

- 98 snapshots received,
- 33 agents,
- 9 services,
- 4 rules passed,
- 3 rules failed,
- 1 skipped.

The failed rules include:

- `fs-defaultfs-propagation` as critical,
- `hive-warehouse-namenode` as warning,
- `dual-source-consistency` as warning.

The checker also reports cross-source drift between `core-site.xml` and `hadoop.env`, and root-cause traces to Hive and Spark services.

### 10.3 Restore Clean State

```bash
sed -i 's|hdfs://wronghost:8020|hdfs://namenode:8020|' conf/core-site.xml
docker compose restart agent-namenode
```

After restoration, the checker reports:

```text
Rules: 7 passed, 0 failed, 1 skipped
CLEAN.
```

This confirms the checker can detect injected drift and verify recovery.

---

## 11. Real-Version Bugbench Layer

The checker framework evaluates generalized configuration consistency. The course repository additionally contains real-version Spark bugbenches that validate the broader configuration-propagation failure model.

### 11.1 SPARK-11972

SPARK-11972 compares Spark 1.6.0 and Spark 1.6.1. The workload passes:

```text
--hiveconf RESULT_TABLE=test_result01
```

and uses SQL containing:

```text
${hiveconf:RESULT_TABLE}
```

The reproduced result shows:

```text
buggy_exit_code = 1
fixed_exit_code = 0
buggy_hiveconf_failure_found = true
fixed_hiveconf_failure_found = false
reproduced = true
```

This confirms a real configuration propagation failure: Spark 1.6.0 does not substitute the HiveConf variable correctly, while Spark 1.6.1 does.

### 11.2 SPARK-15067

SPARK-15067 runs Spark 1.6.1 on Hadoop/YARN 2.7.1 with Java 8. It captures real NodeManager launch evidence for executor JVM options.

The result shows:

```text
user_flag_found = true
fixed_default_found = false
reproduced = false
```

The user-provided `-XX:MaxPermSize=1024M` appears in the real YARN launch command, but the historical duplicate `-XX:MaxPermSize=256m` does not appear under the Java 8 runtime. Therefore, the exact historical symptom is not reproduced, but the evidence-capture path works.

---

## 12. Relationship Between Checker and Bugbench

The checker and bugbench layers are related but not identical.

The checker is a general framework:

```text
Config sources → ConfigSnapshot → Kafka → Drift/rule/root-cause analysis
```

The bugbench is a real-version validation layer:

```text
Exact Spark versions → workload execution → logs/evidence → bug-specific oracle
```

The bugbench does not currently run through the checker’s Kafka pipeline. Instead, it validates that the configuration-propagation failure model corresponds to real historical bugs.

A future integration path would convert bugbench runtime evidence into snapshot-like `RuntimeEvidence` records and extend the validator with runtime-specific rules.

---

## 13. Repository Review and Recommendations

### 13.1 What Looks Good

- The repository has a coherent Python package structure under `checker/`.
- The CLI is clearly exposed through `hadoopconf`.
- Docker Compose now includes service containers plus checker/agent sidecars.
- The YAML rule file is a clean extension point.
- The test suite is strong: 279 pytest tests pass.
- Live integration tests cover both service health and checker-specific behavior.
- `evaluate.sh` provides a repeatable scenario-based evaluation harness.

### 13.2 Recommended Cleanup

- Do not commit runtime outputs such as Docker volumes, `out/`, `debug-runtime/`, or large logs.
- Add a short section to README.md that distinguishes `pytest`, `run-all.sh`, `evaluate.sh`, and manual `hadoopconf status`.
- Clarify that SPARK-11972 is a successful real-version reproduction, while SPARK-15067 is a launch-evidence capture case with `reproduced=false` under Java 8.

Check out `hadoop-config-project/docs/Troubleshooting.md`, and `hadoop-config-project/docs/operations.md` `hadoop-config-project/docs/README.md`for more specifics.

---

## 14. Limitations

- The checker focuses on configuration consistency, drift, and propagation failures; it is not a complete detector for all cloud-system bugs.
- Rules must be written explicitly; the system does not infer all invariants automatically.
- The checker currently reasons mainly over static and near-runtime configuration snapshots, not arbitrary application semantics.
- The `prior-sprints/bugbench` layer is currently not fully integrated into the checker’s Kafka-based pipeline.
- Each real bugbench still requires a custom workload and assertion oracle.
Check out `hadoop-config-project/docs/limitations.md` for more specifics.

---

## 15. Future Work

Possible extensions include:

1. Convert real bugbench logs into `RuntimeEvidence` snapshots.
2. Add validator rule types for runtime substitution and launch-command propagation.
3. Integrate SPARK-11972 into the checker as a runtime-substitution rule.
4. Add property-based tests that generate many configuration keys and verify propagation invariants.
5. Extend the causality graph with YAML-loadable custom edges.
6. Add CI jobs for `pytest`, `run-all.sh`, and a lightweight subset of `evaluate.sh`.
7. Add more historical bugs from Hive, ZooKeeper, and YARN once the current documentation is stable.

---

## 16. Conclusion

The project demonstrates a practical way to detect cross-component configuration bugs in Hadoop-family systems. The checker collects configuration snapshots across services, validates cross-service invariants, detects drift, and traces likely downstream impact. The evaluation artifacts show that the internal checker tests pass, the live cluster tests pass, and injected drift can be detected and restored.

The real-version bugbench layer complements this by showing that configuration propagation failures are not only synthetic examples: SPARK-11972 is successfully reproduced with buggy and fixed Spark versions, and SPARK-15067 demonstrates real Spark-on-YARN launch-evidence capture.

Together, these pieces support the project’s central claim:

> Cross-component configuration failures can be made visible, testable, and explainable through snapshot-based monitoring, rule validation, and real-version bugbench evaluation.

---

## Referenced Project Documents

- `hadoop-config-project/docs/` README and source files.
- EC528 course repository `prior-sprints/bugbench` results for SPARK-11972 and SPARK-15067.

### Demo 4 / Final Presentation
Presentation link: https://docs.google.com/presentation/d/1W6wULk-O3dGci1o7o2J6U7NHNvLoHD3I/edit?usp=sharing&ouid=109798651450595509755&rtpof=true&sd=true 

Video link: [https://drive.google.com/file/d/1p458j01n4CJSY2cS5iOQAqSCiNA0KwUs/view?usp=sharing ](https://drive.google.com/drive/folders/10KVrNnQoZXxPfEyXpjwFBrZP13LFwQX3?usp=drive_link)

Output from evaluation tests: `hadoop-config-project/tests/results/evaluation-outputs`

