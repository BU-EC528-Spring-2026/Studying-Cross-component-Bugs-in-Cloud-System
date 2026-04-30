FROM eclipse-temurin:8-jdk-jammy

ENV HADOOP_VERSION=2.7.1 \
    SPARK_VERSION=1.6.1 \
    HADOOP_HOME=/opt/hadoop-2.7.1 \
    SPARK_HOME=/opt/spark-1.6.1-bin-hadoop2.6 \
    HADOOP_CONF_DIR=/opt/hadoop-2.7.1/etc/hadoop \
    YARN_CONF_DIR=/opt/hadoop-2.7.1/etc/hadoop \
    JAVA_HOME=/opt/java/openjdk
ENV PATH=$SPARK_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash curl wget python3 procps netcat-openbsd grep sed findutils coreutils ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN cd /opt \
    && wget -q https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz \
    && tar -xzf hadoop-${HADOOP_VERSION}.tar.gz \
    && rm hadoop-${HADOOP_VERSION}.tar.gz \
    && wget -q https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop2.6.tgz \
    && tar -xzf spark-${SPARK_VERSION}-bin-hadoop2.6.tgz \
    && rm spark-${SPARK_VERSION}-bin-hadoop2.6.tgz

COPY conf/core-site.xml $HADOOP_CONF_DIR/core-site.xml
COPY conf/hdfs-site.xml $HADOOP_CONF_DIR/hdfs-site.xml
COPY conf/yarn-site.xml $HADOOP_CONF_DIR/yarn-site.xml
COPY conf/mapred-site.xml $HADOOP_CONF_DIR/mapred-site.xml
COPY testbench.sh /bench/testbench.sh
COPY assert_spark_15067.py /bench/assert_spark_15067.py
COPY README.md /bench/README.md

RUN echo "export JAVA_HOME=$JAVA_HOME" >> $HADOOP_CONF_DIR/hadoop-env.sh \
    && chmod +x /bench/testbench.sh

WORKDIR /bench
ENTRYPOINT ["/bench/testbench.sh"]
