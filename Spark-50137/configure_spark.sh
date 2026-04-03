#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

cd "$SPARK_DIR"
mkdir -p conf

cat > conf/hive-site.xml <<'EOF'
<configuration>
  <property>
    <name>hive.metastore.uris</name>
    <value>thrift://127.0.0.1:9083</value>
  </property>
</configuration>
EOF

cat > conf/spark-defaults.conf <<'EOF'
spark.sql.catalogImplementation hive
spark.sql.hive.metastore.version 3.1.3
spark.sql.hive.metastore.jars maven
EOF

echo "[OK] Spark configured for local Hive metastore."
