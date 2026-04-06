#!/usr/bin/env python3
"""Capture and normalize spark-submit intent for ConfigPropGuard.

This script does not execute spark-submit. It parses a command line and emits a
manifest describing submission-time intent.
"""
from __future__ import annotations

import argparse
import json
import os
import shlex
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Dict, List, Optional


@dataclass
class IntentManifest:
    command: str
    argv: List[str]
    master: Optional[str]
    deploy_mode: Optional[str]
    app_resource: Optional[str]
    app_args: List[str]
    clazz: Optional[str]
    conf: Dict[str, str]
    files: List[str]
    jars: List[str]
    archives: List[str]
    driver_java_options: Optional[str]
    driver_memory: Optional[str]
    executor_memory: Optional[str]
    executor_cores: Optional[str]
    queue: Optional[str]
    env_snapshot: Dict[str, str]


def parse_command(command: str) -> IntentManifest:
    argv = shlex.split(command)
    if not argv:
        raise ValueError("empty command")

    master = None
    deploy_mode = None
    app_resource = None
    app_args: List[str] = []
    clazz = None
    conf: Dict[str, str] = {}
    files: List[str] = []
    jars: List[str] = []
    archives: List[str] = []
    driver_java_options = None
    driver_memory = None
    executor_memory = None
    executor_cores = None
    queue = None

    i = 0
    while i < len(argv):
        token = argv[i]
        nxt = argv[i + 1] if i + 1 < len(argv) else None

        if token in {"spark-submit", "./bin/spark-submit", "bin/spark-submit"}:
            i += 1
            continue
        if token == "--master" and nxt is not None:
            master = nxt
            i += 2
            continue
        if token == "--deploy-mode" and nxt is not None:
            deploy_mode = nxt
            i += 2
            continue
        if token == "--class" and nxt is not None:
            clazz = nxt
            i += 2
            continue
        if token == "--conf" and nxt is not None:
            if "=" not in nxt:
                raise ValueError(f"invalid --conf entry: {nxt}")
            k, v = nxt.split("=", 1)
            conf[k] = v
            i += 2
            continue
        if token == "--files" and nxt is not None:
            files.extend([x for x in nxt.split(",") if x])
            i += 2
            continue
        if token == "--jars" and nxt is not None:
            jars.extend([x for x in nxt.split(",") if x])
            i += 2
            continue
        if token == "--archives" and nxt is not None:
            archives.extend([x for x in nxt.split(",") if x])
            i += 2
            continue
        if token == "--driver-java-options" and nxt is not None:
            driver_java_options = nxt
            i += 2
            continue
        if token == "--driver-memory" and nxt is not None:
            driver_memory = nxt
            i += 2
            continue
        if token == "--executor-memory" and nxt is not None:
            executor_memory = nxt
            i += 2
            continue
        if token == "--executor-cores" and nxt is not None:
            executor_cores = nxt
            i += 2
            continue
        if token == "--queue" and nxt is not None:
            queue = nxt
            i += 2
            continue

        if token.startswith("--"):
            # best-effort skip option with value if present
            if nxt is not None and not nxt.startswith("--"):
                i += 2
            else:
                i += 1
            continue

        if app_resource is None:
            app_resource = token
        else:
            app_args.append(token)
        i += 1

    env_snapshot = {
        key: value
        for key, value in os.environ.items()
        if key in {
            "JAVA_HOME",
            "HADOOP_CONF_DIR",
            "YARN_CONF_DIR",
            "SPARK_CONF_DIR",
            "PYSPARK_PYTHON",
            "PYSPARK_DRIVER_PYTHON",
        }
    }

    return IntentManifest(
        command=command,
        argv=argv,
        master=master,
        deploy_mode=deploy_mode,
        app_resource=app_resource,
        app_args=app_args,
        clazz=clazz,
        conf=conf,
        files=files,
        jars=jars,
        archives=archives,
        driver_java_options=driver_java_options,
        driver_memory=driver_memory,
        executor_memory=executor_memory,
        executor_cores=executor_cores,
        queue=queue,
        env_snapshot=env_snapshot,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--command", help="spark-submit command string")
    group.add_argument("--command-file", help="path to file containing the full spark-submit command")
    parser.add_argument("--json-out", required=True)
    args = parser.parse_args()

    if args.command:
        command = args.command.strip()
    else:
        command = Path(args.command_file).read_text(encoding="utf-8").strip()

    manifest = parse_command(command)
    out_path = Path(args.json_out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(asdict(manifest), indent=2, sort_keys=True), encoding="utf-8")
    print(f"wrote {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
