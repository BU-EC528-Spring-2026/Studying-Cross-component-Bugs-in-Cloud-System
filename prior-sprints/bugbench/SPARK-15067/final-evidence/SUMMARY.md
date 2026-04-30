# SPARK-15067 Real-Version Testbench Result

## Environment

- Spark: 1.6.1
- Hadoop/YARN: 2.7.1
- Java: 1.8.0_482 in the current Docker image

## What was executed

The testbench started a real HDFS/YARN environment in Docker and submitted SparkPi using Spark 1.6.1 on YARN.

## Evidence captured

The testbench copied real NodeManager runtime artifacts from the stopped container and extracted executor launch commands from launch scripts and YARN container logs.

Important evidence files:

- spark-submit.log
- testbench.log
- yarn-launch-evidence.txt
- repro-result.json

## Oracle

SPARK-15067 is considered reproduced if both of the following appear in real YARN launch evidence:

- user-specified flag: `-XX:MaxPermSize=1024M`
- Spark fixed default: `-XX:MaxPermSize=256m`

## Result

- user_flag_found: true
- fixed_default_found: false
- reproduced: false

The current run confirms that the user-specified executor JVM option reached the real YARN executor launch command. However, the historical fixed default `-XX:MaxPermSize=256m` was not observed in the current Java 8 runtime.

## Interpretation

The real-version testbench infrastructure works: it runs Spark 1.6.1 with Hadoop/YARN 2.7.1 and captures real NodeManager launch evidence. The exact SPARK-15067 duplicate-flag symptom was not reproduced under this Java 8 runtime configuration. A Java 7 lane or another configuration-propagation bug may be needed for a full historical reproduction.
