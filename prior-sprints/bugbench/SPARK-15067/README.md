# SPARK-15067 Real-Version Testbench

This is a real shell testbench for SPARK-15067.

It installs and runs:

- Apache Spark 1.6.1, the affected Spark version listed in the ASF JIRA issue
- Apache Hadoop/YARN 2.7.1 in a pseudo-distributed single-container setup
- Java 8

The testbench starts real HDFS and YARN daemons, submits SparkPi to YARN with:

```bash
--conf "spark.executor.extraJavaOptions=-XX:MaxPermSize=1024M -Dbugbench=SPARK-15067"
```

Then it captures real NodeManager launch evidence from `yarn.nodemanager.local-dirs` and checks whether the executor launch command contains both:

- user intent: `-XX:MaxPermSize=1024M`
- buggy Spark default appended later: `-XX:MaxPermSize=256m`

If both are present, the testbench exits 0 and reports that the historical bug was reproduced.

## Run

```bash
docker build -t spark-15067-bench .
mkdir -p out
docker run --rm -v "$PWD/out:/bench/out" spark-15067-bench
```

## Outputs

All outputs are written to `out/`:

- `spark-submit.log`
- `yarn-applications.txt`
- `nodemanager-local-files.txt`
- `nodemanager-log-files.txt`
- `yarn-launch-evidence.txt`
- `repro-result.json`
- `testbench.log`

## Important semantic note

A PASS means the testbench successfully reproduced the historical bug. It does not mean the old Spark version is correct.
