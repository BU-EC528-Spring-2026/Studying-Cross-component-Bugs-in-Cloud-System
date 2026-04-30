# Full Reproduction Process

## Step 1: Prepare the base environment

Install Java 11, Maven, Docker, Docker Compose, and the PostgreSQL JDBC driver:

```bash
bash scripts/setup_base.sh
```

## Step 2: Start the local Hive lab

Start PostgreSQL + Hive Metastore + HiveServer2:

```bash
bash scripts/start_hive_lab.sh
```

## Step 3: Clone Spark 3.5.3

```bash
bash scripts/clone_spark.sh
```

## Step 4: Configure Spark to know the local metastore

```bash
bash scripts/configure_spark.sh
```

## Step 5: Patch the regression-style test

```bash
bash scripts/patch_test.sh
```

This inserts a new test into `HiveExternalCatalogSuite.scala`.

## Step 6: Compile test code

```bash
bash scripts/build_test_compile.sh
```

## Step 7: Run the suite

```bash
bash scripts/run_repro.sh
```

## Step 8: Collect evidence

```bash
bash scripts/collect_evidence.sh
```

