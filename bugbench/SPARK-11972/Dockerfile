FROM eclipse-temurin:8-jdk

ARG SPARK_160_VERSION=1.6.0
ARG SPARK_161_VERSION=1.6.1

ENV SPARK_160_HOME=/opt/spark-1.6.0-bin-hadoop2.6 \
    SPARK_161_HOME=/opt/spark-1.6.1-bin-hadoop2.6 \
    SPARK_LOCAL_IP=127.0.0.1

RUN apt-get update && \
    apt-get install -y --no-install-recommends bash curl ca-certificates procps python3 tar gzip && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt

RUN curl -fL "https://archive.apache.org/dist/spark/spark-${SPARK_160_VERSION}/spark-${SPARK_160_VERSION}-bin-hadoop2.6.tgz" -o spark-1.6.0.tgz && \
    tar -xzf spark-1.6.0.tgz && \
    rm spark-1.6.0.tgz && \
    curl -fL "https://archive.apache.org/dist/spark/spark-${SPARK_161_VERSION}/spark-${SPARK_161_VERSION}-bin-hadoop2.6.tgz" -o spark-1.6.1.tgz && \
    tar -xzf spark-1.6.1.tgz && \
    rm spark-1.6.1.tgz

WORKDIR /bench

COPY testbench.sh /bench/testbench.sh
COPY assert_spark_11972.py /bench/assert_spark_11972.py
COPY query.sql /bench/query.sql

RUN chmod +x /bench/testbench.sh /bench/assert_spark_11972.py

CMD ["/bench/testbench.sh"]
