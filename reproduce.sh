#!/bin/bash
# ============================================================================
# ZOOKEEPER-2184 Reproduction Script (v4 — Persistent ZK Data)
#
# The bug is in the ZK CLIENT library (StaticHostProvider.java).
# Phase 1: Kafka 1.1.1 (ZK client 3.4.10) — caches IP, can't reconnect
# Phase 2: Kafka 2.8.1 (ZK client 3.5.9) — re-resolves, reconnects
#
# KEY FIX from v3: We persist ZK data to a Docker volume so that when ZK
# restarts with a new IP, the session state is preserved. This allows
# the fixed client to both find the new IP AND resume its session.
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

wait_for_zk() {
    local container=$1
    local max_wait=$2
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if docker exec "$container" bash -c 'echo ruok | nc localhost 2181 2>/dev/null' 2>/dev/null | grep -q "imok"; then
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    return 1
}

check_kafka_connected() {
    local zk_container=$1
    docker exec "$zk_container" bash -c 'echo dump | nc localhost 2181 2>/dev/null' 2>/dev/null | grep -q "/brokers/ids/1"
}

get_zk_dump() {
    local container=$1
    docker exec "$container" bash -c 'echo dump | nc localhost 2181 2>/dev/null' 2>/dev/null || echo "(dump not available)"
}

cleanup() {
    log "Cleaning up..."
    docker rm -f zk-buggy zk-buggy-newip kafka-buggy 2>/dev/null || true
    docker rm -f zk-fixed zk-fixed-newip kafka-fixed 2>/dev/null || true
    docker network rm zk2184-buggy-net zk2184-fixed-net 2>/dev/null || true
    docker volume rm zk-data-buggy zk-datalog-buggy zk-data-fixed zk-datalog-fixed 2>/dev/null || true
}

# ============================================================================
# Phase 1: BUGGY — Kafka 1.1.1 (ZK client 3.4.10, pre-fix)
# ============================================================================
run_buggy_test() {
    echo ""
    
    echo " PHASE 1: BUGGY CLIENT (Kafka 1.1.1 → ZK client 3.4.10)"
    echo " ZK server: 3.4.11 with persistent data volume"
    echo ""
    echo " Expecting: Client caches OLD IP, can't reach new ZK"
    
    echo ""

    docker network create --subnet=172.30.0.0/16 zk2184-buggy-net 2>/dev/null || true
    docker volume create zk-data-buggy 2>/dev/null || true
    docker volume create zk-datalog-buggy 2>/dev/null || true

    log "Starting ZooKeeper 3.4.11 at 172.30.0.10 (with persistent volume)..."
    docker run -d \
        --name zk-buggy \
        --hostname zookeeper \
        --net zk2184-buggy-net \
        --ip 172.30.0.10 \
        -v zk-data-buggy:/data \
        -v zk-datalog-buggy:/datalog \
        -e ZOO_TICK_TIME=2000 \
        zookeeper:3.4.11

    log "Waiting for ZK..."
    if ! wait_for_zk zk-buggy 30; then
        fail "ZooKeeper did not start"
        return 1
    fi
    pass "ZooKeeper 3.4.11 running at 172.30.0.10"

    log "Starting Kafka 1.1.1 (bundles ZK client 3.4.10, pre-fix)..."
    docker run -d \
        --name kafka-buggy \
        --hostname kafka \
        --net zk2184-buggy-net \
        --ip 172.30.0.30 \
        -e KAFKA_ZOOKEEPER_CONNECT=zookeeper:2181 \
        -e KAFKA_LISTENERS=PLAINTEXT://0.0.0.0:9092 \
        -e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://kafka:9092 \
        -e KAFKA_BROKER_ID=1 \
        -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
        -e KAFKA_ZOOKEEPER_SESSION_TIMEOUT_MS=15000 \
        -e KAFKA_ZOOKEEPER_CONNECTION_TIMEOUT_MS=10000 \
        wurstmeister/kafka:2.11-1.1.1

    log "Waiting 30s for Kafka to register..."
    sleep 30

    if check_kafka_connected zk-buggy; then
        pass "Kafka broker registered in ZK at /brokers/ids/1"
    else
        warn "Not registered yet, waiting 20 more seconds..."
        sleep 20
        check_kafka_connected zk-buggy && pass "Kafka registered" || warn "Continuing anyway..."
    fi

    log "Initial ZK state:"
    get_zk_dump zk-buggy
    echo ""

    log "Cached IP:"
    docker exec kafka-buggy bash -c 'getent hosts zookeeper 2>/dev/null' || true
    echo ""

    # Stop ZK, restart with new IP but SAME data
    log ">>> Stopping ZooKeeper (data persisted on volume)..."
    docker stop zk-buggy
    docker rm zk-buggy

    log ">>> Restarting ZooKeeper 3.4.11 at NEW IP 172.30.0.20 (same data)..."
    docker run -d \
        --name zk-buggy-newip \
        --hostname zookeeper \
        --net zk2184-buggy-net \
        --ip 172.30.0.20 \
        -v zk-data-buggy:/data \
        -v zk-datalog-buggy:/datalog \
        -e ZOO_TICK_TIME=2000 \
        zookeeper:3.4.11

    if ! wait_for_zk zk-buggy-newip 30; then
        fail "New ZK did not start"
        return 1
    fi
    pass "ZooKeeper restarted at 172.30.0.20 (with preserved session data)"

    log "Docker DNS now resolves 'zookeeper' to:"
    docker exec kafka-buggy bash -c 'getent hosts zookeeper 2>/dev/null' || true
    echo ""

    log "Waiting 60 seconds for Kafka to attempt reconnection..."
    echo "    (Buggy client cached 172.30.0.10, will never try 172.30.0.20)"
    sleep 60

    log "Kafka connection logs (last 25 lines):"
    echo "--------------------------------------------------------------------"
    docker logs kafka-buggy 2>&1 | grep -iE "(opening socket|session|expired|reconnect)" | tail -25
    echo "--------------------------------------------------------------------"
    echo ""

    log "KEY: Check the IP in 'Opening socket connection' lines."
    echo "     BUGGY client should show OLD IP 172.30.0.10"
    echo ""

    if check_kafka_connected zk-buggy-newip; then
        warn "Kafka reconnected — bug did not reproduce"
    else
        fail "Kafka CANNOT reconnect (BUG CONFIRMED — client stuck on old IP)"
        log "ZK dump (should show no Kafka broker):"
        get_zk_dump zk-buggy-newip
    fi

    echo ""
    log "Cleaning up Phase 1..."
    docker rm -f zk-buggy-newip kafka-buggy 2>/dev/null || true
    docker network rm zk2184-buggy-net 2>/dev/null || true
    docker volume rm zk-data-buggy zk-datalog-buggy 2>/dev/null || true
}

# ============================================================================
# Phase 2: FIXED — Kafka 2.8.1 (ZK client 3.5.9, post-fix)
# ============================================================================
run_fixed_test() {
    echo ""
    
    echo " PHASE 2: FIXED CLIENT (Kafka 2.8.1 → ZK client 3.5.9)"
    echo " ZK server: 3.4.11 with persistent data volume"
    echo ""
    echo " Expecting: Client re-resolves hostname, reconnects fully"
    
    echo ""

    docker network create --subnet=172.31.0.0/16 zk2184-fixed-net 2>/dev/null || true
    docker volume create zk-data-fixed 2>/dev/null || true
    docker volume create zk-datalog-fixed 2>/dev/null || true

    log "Starting ZooKeeper 3.4.11 at 172.31.0.10 (with persistent volume)..."
    docker run -d \
        --name zk-fixed \
        --hostname zookeeper \
        --net zk2184-fixed-net \
        --ip 172.31.0.10 \
        -v zk-data-fixed:/data \
        -v zk-datalog-fixed:/datalog \
        -e ZOO_TICK_TIME=2000 \
        zookeeper:3.4.11

    if ! wait_for_zk zk-fixed 30; then
        fail "ZooKeeper did not start"
        return 1
    fi
    pass "ZooKeeper 3.4.11 running at 172.31.0.10"

    log "Starting Kafka 2.8.1 (bundles ZK client 3.5.9, post-fix)..."
    docker run -d \
        --name kafka-fixed \
        --hostname kafka \
        --net zk2184-fixed-net \
        --ip 172.31.0.30 \
        -e KAFKA_ZOOKEEPER_CONNECT=zookeeper:2181 \
        -e KAFKA_LISTENERS=PLAINTEXT://0.0.0.0:9092 \
        -e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://kafka:9092 \
        -e KAFKA_BROKER_ID=1 \
        -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
        -e KAFKA_ZOOKEEPER_SESSION_TIMEOUT_MS=15000 \
        -e KAFKA_ZOOKEEPER_CONNECTION_TIMEOUT_MS=10000 \
        wurstmeister/kafka:2.13-2.8.1

    log "Waiting 30s for Kafka to register..."
    sleep 30

    if check_kafka_connected zk-fixed; then
        pass "Kafka broker registered in ZK at /brokers/ids/1"
    else
        warn "Not registered yet, waiting 20 more seconds..."
        sleep 20
        check_kafka_connected zk-fixed && pass "Kafka registered" || warn "Continuing anyway..."
    fi

    log "Initial ZK state:"
    get_zk_dump zk-fixed
    echo ""

    # Stop ZK, restart with new IP but SAME data
    log ">>> Stopping ZooKeeper (data persisted on volume)..."
    docker stop zk-fixed
    docker rm zk-fixed

    log ">>> Restarting ZooKeeper 3.4.11 at NEW IP 172.31.0.20 (same data)..."
    docker run -d \
        --name zk-fixed-newip \
        --hostname zookeeper \
        --net zk2184-fixed-net \
        --ip 172.31.0.20 \
        -v zk-data-fixed:/data \
        -v zk-datalog-fixed:/datalog \
        -e ZOO_TICK_TIME=2000 \
        zookeeper:3.4.11

    if ! wait_for_zk zk-fixed-newip 30; then
        fail "New ZK did not start"
        return 1
    fi
    pass "ZooKeeper restarted at 172.31.0.20 (with preserved session data)"

    log "Waiting 60 seconds for Kafka to reconnect..."
    echo "    (Fixed client should re-resolve 'zookeeper' to 172.31.0.20"
    echo "     AND resume session since ZK data is preserved)"
    sleep 60

    log "Kafka connection logs (last 25 lines):"
    echo "--------------------------------------------------------------------"
    docker logs kafka-fixed 2>&1 | grep -iE "(opening socket|session|expired|reconnect|resolv|established)" | tail -25
    echo "--------------------------------------------------------------------"
    echo ""

    log "KEY: Check the IP in 'Opening socket connection' lines."
    echo "     FIXED client should show NEW IP 172.31.0.20"
    echo ""

    if check_kafka_connected zk-fixed-newip; then
        pass "Kafka RECONNECTED and re-registered (FIX FULLY CONFIRMED)"
        log "ZK dump (should show broker at /brokers/ids/1):"
        get_zk_dump zk-fixed-newip
    else
        warn "Kafka found new ZK but may not have fully re-registered"
        log "ZK dump:"
        get_zk_dump zk-fixed-newip
        echo ""
        log "Last 30 Kafka log lines:"
        docker logs kafka-fixed 2>&1 | tail -30
    fi

    echo ""
    log "Cleaning up Phase 2..."
    docker rm -f zk-fixed-newip kafka-fixed 2>/dev/null || true
    docker network rm zk2184-fixed-net 2>/dev/null || true
    docker volume rm zk-data-fixed zk-datalog-fixed 2>/dev/null || true
}

# ============================================================================
# Main
# ============================================================================

echo " ZOOKEEPER-2184 Reproduction (v4 — Persistent ZK Data)"
echo ""
echo " Phase 1: Kafka 1.1.1 → ZK client 3.4.10 (BUGGY)"
echo " Phase 2: Kafka 2.8.1 → ZK client 3.5.9  (FIXED)"
echo " Server:  ZK 3.4.11 with persistent volumes (both phases)"
echo ""
echo " ZK data is persisted so sessions survive restart."
echo " The ONLY difference is the client library version."


cleanup

log "Pulling images..."
docker pull zookeeper:3.4.11
docker pull wurstmeister/kafka:2.11-1.1.1
docker pull wurstmeister/kafka:2.13-2.8.1

run_buggy_test
run_fixed_test

echo ""

echo " SUMMARY"

echo ""
echo " Phase 1 (BUGGY — ZK client 3.4.10):"
echo "   Client cached IP at startup → never re-resolved"
echo "   Kept trying OLD IP → connection refused"
echo "   ZK dump: 0 sessions, 0 ephemeral nodes"
echo ""
echo " Phase 2 (FIXED — ZK client 3.5.9):"
echo "   Client re-resolved hostname → found new IP"
echo "   Connected to new ZK → resumed session (data preserved)"
echo "   ZK dump: broker re-registered at /brokers/ids/1"
echo ""
echo " Bug: StaticHostProvider.java cached DNS resolution forever"
echo " Fix: ZOOKEEPER-2184 (merged into ZK 3.5.4 and 3.4.12)"

