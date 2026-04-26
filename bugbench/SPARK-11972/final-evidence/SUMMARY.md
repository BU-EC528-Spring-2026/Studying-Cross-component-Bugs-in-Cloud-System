# SPARK-11972 Real-Version Bugbench Result

## Bug

SPARK-11972: `spark-sql --hiveconf` parameters are not correctly visible after entering the Spark SQL CLI session.

## Versions

- Buggy version: Spark 1.6.0
- Fixed version: Spark 1.6.1

## Test design

The testbench runs the same SQL workload under Spark 1.6.0 and Spark 1.6.1.
The workload passes `--hiveconf RESULT_TABLE=test_result01` to `spark-sql` and then uses `${hiveconf:RESULT_TABLE}` inside SQL statements.

## Oracle

The bug is considered reproduced if:

1. Spark 1.6.0 fails with an unexpanded `${hiveconf:RESULT_TABLE}` / Hive parser failure.
2. Spark 1.6.1 runs the same SQL without the hiveconf parser failure.

## Result

The bugbench reproduced SPARK-11972:

- Spark 1.6.0 exited with code 1.
- Spark 1.6.0 log contains the unexpanded `${hiveconf:RESULT_TABLE}` and parser failure patterns.
- Spark 1.6.1 exited with code 0.
- Spark 1.6.1 did not contain the same hiveconf parser failure.

This confirms a real configuration-propagation failure from CLI-level `--hiveconf` into the Spark SQL / HiveConf session in Spark 1.6.0, and confirms that the same workload is fixed in Spark 1.6.1.
