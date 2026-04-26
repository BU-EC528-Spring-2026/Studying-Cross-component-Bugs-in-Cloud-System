# SPARK-11972 Real-Version Bugbench

## Purpose

This bugbench tests SPARK-11972:

> `[Spark SQL] the value of 'hiveconf' parameter in CLI can't be got after enter spark-sql session`

The testbench compares Spark 1.6.0 (buggy lane) with Spark 1.6.1 (fixed lane). It exercises a real `spark-sql` process and checks whether a CLI-level `--hiveconf RESULT_TABLE=...` value is propagated into the Spark SQL / HiveConf session and used for SQL variable substitution.

## Bug oracle

The SQL query uses the same core pattern from the JIRA reproduction:

```sql
DROP TABLE IF EXISTS ${hiveconf:RESULT_TABLE};
```

Expected behavior:

- Spark 1.6.0: `${hiveconf:RESULT_TABLE}` is not substituted correctly, causing a parser error such as `cannot recognize input near '$' '{' 'hiveconf'` or `NoViableAltException`.
- Spark 1.6.1: the same command succeeds because the HiveConf value is propagated into the session.

## Build

```bash
docker build -t spark-11972-bench .
```

## Run

```bash
mkdir -p out
docker run --rm -v "$PWD/out:/bench/out" spark-11972-bench
```

## Expected result

The final result is written to:

```text
out/repro-result.json
```

The expected successful oracle is:

```json
"reproduced": true
```

This means the buggy Spark 1.6.0 lane shows the expected HiveConf propagation failure, while the fixed Spark 1.6.1 lane does not.

## Output files

```text
out/buggy-spark-1.6.0.log
out/buggy-spark-1.6.0.exitcode
out/fixed-spark-1.6.1.log
out/fixed-spark-1.6.1.exitcode
out/repro-result.json
```

## Notes

This testbench runs Spark SQL in `local[1]` mode by default. The bug is about Spark SQL CLI to HiveConf session propagation, so a full YARN cluster is not required for the oracle. If needed, the script can be extended to run with `--master yarn-client`, but local mode is more stable for a minimal real-version regression test.
