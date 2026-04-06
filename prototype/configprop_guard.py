#!/usr/bin/env python3
"""ConfigPropGuard v0.2

Prototype detector for Configuration Propagation / Feature Gating bugs,
primarily targeting Spark-on-YARN.
"""
from __future__ import annotations

import argparse
import json
import re
import shlex
import sys
import textwrap
import xml.etree.ElementTree as ET
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Dict, List, Optional, Tuple

CONF_PAIR_RE = re.compile(r"^([^\s=#]+)\s*[:=\s]\s*(.*?)\s*$")
ENV_RE = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$")

DOWNSTREAM_PREFIXES = (
    "yarn.",
    "hadoop.",
    "mapred.",
    "mapreduce.",
    "dfs.",
    "fs.",
    "hive.",
)

STANDARD_SPARK_ENV_KEYS = {
    "JAVA_HOME",
    "SPARK_HOME",
    "SPARK_CONF_DIR",
    "HADOOP_CONF_DIR",
    "YARN_CONF_DIR",
}


@dataclass
class Finding:
    rule_id: str
    severity: str
    title: str
    message: str
    evidence: List[str]
    recommendation: str


@dataclass
class Summary:
    status: str
    errors: int
    warnings: int
    advisories: int
    findings: int


@dataclass
class JvmOpt:
    raw: str
    key: str
    value: Optional[str]
    index: int


class Guard:
    def __init__(
        self,
        intent: Dict[str, object],
        spark_defaults: Dict[str, str],
        spark_env: Dict[str, str],
        core_site: Dict[str, str],
        yarn_site: Dict[str, str],
        hive_site: Dict[str, str],
        yarn_launch_text: str,
        policy: Dict[str, object],
        spark_version: str,
        hadoop_version: str,
        cluster_manager: str,
        deploy_mode: str,
    ) -> None:
        self.intent = intent
        self.spark_defaults = spark_defaults
        self.spark_env = spark_env
        self.core_site = core_site
        self.yarn_site = yarn_site
        self.hive_site = hive_site
        self.yarn_launch_text = yarn_launch_text
        self.policy = policy
        self.spark_version = spark_version
        self.hadoop_version = hadoop_version
        self.cluster_manager = cluster_manager
        self.deploy_mode = deploy_mode
        self.findings: List[Finding] = []

        self.effective_conf = dict(spark_defaults)
        self.effective_conf.update(intent.get("conf", {}))
        self.intent_env = intent.get("env_snapshot", {}) if isinstance(intent.get("env_snapshot"), dict) else {}

    def add(self, rule_id: str, severity: str, title: str, message: str, evidence: List[str], recommendation: str) -> None:
        self.findings.append(Finding(rule_id, severity, title, message, evidence, recommendation))

    def run(self) -> Dict[str, object]:
        self.rule_raw_downstream_keys()
        self.rule_missing_am_env_propagation()
        self.rule_jvm_option_shadowing()
        self.rule_missing_yarn_conf_channel()
        self.rule_spark4_dual_jdk_gate()
        self.rule_policy_checks()

        errors = sum(1 for f in self.findings if f.severity == "error")
        warnings = sum(1 for f in self.findings if f.severity == "warning")
        advisories = sum(1 for f in self.findings if f.severity == "advisory")
        status = "FAIL" if errors else ("WARN" if warnings else "PASS")

        return {
            "summary": asdict(Summary(status, errors, warnings, advisories, len(self.findings))),
            "environment": {
                "spark_version": self.spark_version,
                "hadoop_version": self.hadoop_version,
                "cluster_manager": self.cluster_manager,
                "deploy_mode": self.deploy_mode,
            },
            "effective_conf": self.effective_conf,
            "spark_env": self.spark_env,
            "inputs_present": {
                "intent": bool(self.intent),
                "spark_defaults": bool(self.spark_defaults),
                "spark_env": bool(self.spark_env),
                "core_site": bool(self.core_site),
                "yarn_site": bool(self.yarn_site),
                "hive_site": bool(self.hive_site),
                "yarn_launch_text": bool(self.yarn_launch_text.strip()),
                "policy": bool(self.policy),
            },
            "findings": [asdict(f) for f in self.findings],
        }

    def rule_raw_downstream_keys(self) -> None:
        offenders = []
        for source_name, conf in [("spark-defaults", self.spark_defaults), ("submission intent", self.intent.get("conf", {}))]:
            if not isinstance(conf, dict):
                continue
            for key, value in conf.items():
                if key.startswith(DOWNSTREAM_PREFIXES) and not key.startswith("spark."):
                    offenders.append((source_name, key, value))
        if offenders:
            self.add(
                "CFG001",
                "warning",
                "Raw downstream keys injected directly into Spark submission properties",
                "Per-application downstream settings are being injected as raw Hadoop/YARN/Hive keys. This makes the propagation path ambiguous and brittle.",
                [f"{src}: {k}={v}" for src, k, v in offenders],
                "Prefer spark.hadoop.* or spark.hive.* so the propagation channel is explicit and auditable.",
            )

    def rule_missing_am_env_propagation(self) -> None:
        if self.cluster_manager != "yarn" or self.deploy_mode != "cluster":
            return
        missing = []
        for env_key, env_val in self.spark_env.items():
            if env_key in STANDARD_SPARK_ENV_KEYS:
                continue
            am_key = f"spark.yarn.appMasterEnv.{env_key}"
            if am_key not in self.effective_conf:
                missing.append((env_key, env_val))
        if missing:
            self.add(
                "CFG002",
                "warning",
                "spark-env.sh variables are not propagated to the YARN Application Master",
                "In YARN cluster mode, variables from spark-env.sh do not automatically appear in the Application Master / driver process.",
                [f"missing {f'spark.yarn.appMasterEnv.{k}'} for spark-env value {k}={v}" for k, v in missing],
                "Add spark.yarn.appMasterEnv.<VAR>=<value> for every cluster-mode variable the AM/driver depends on.",
            )

    def rule_jvm_option_shadowing(self) -> None:
        default_opts = self.effective_conf.get("spark.executor.defaultJavaOptions", "").strip()
        extra_opts = self.effective_conf.get("spark.executor.extraJavaOptions", "").strip()
        if not default_opts and not extra_opts and not self.yarn_launch_text.strip():
            return

        default_parsed = parse_java_opts(default_opts)
        extra_parsed = parse_java_opts(extra_opts)
        default_map = {opt.key: opt for opt in default_parsed}
        extra_map = {opt.key: opt for opt in extra_parsed}

        collisions = []
        for key, dopt in default_map.items():
            if key in extra_map and extra_map[key].value != dopt.value:
                collisions.append((key, dopt, extra_map[key]))
        if collisions:
            self.add(
                "CFG003A",
                "error",
                "Administrator JVM defaults are shadowed by user JVM options",
                "The same executor JVM option appears in both spark.executor.defaultJavaOptions and spark.executor.extraJavaOptions with different values. That makes final effective behavior order-dependent.",
                [f"{key}: default={d.raw} ; extra={e.raw}" for key, d, e in collisions],
                "Remove conflicting duplicates or define a single authoritative owner for each JVM flag.",
            )

        if self.yarn_launch_text.strip():
            java_cmd = extract_java_command(self.yarn_launch_text)
            if java_cmd:
                effective = parse_java_opts(java_cmd)
                effective_map: Dict[str, List[JvmOpt]] = {}
                for opt in effective:
                    effective_map.setdefault(opt.key, []).append(opt)

                declared_expectations: Dict[str, JvmOpt] = {}
                declared_expectations.update(default_map)
                declared_expectations.update(extra_map)

                launch_mismatches = []
                for key, expected in declared_expectations.items():
                    occs = effective_map.get(key, [])
                    if not occs:
                        launch_mismatches.append((key, expected.raw, "ABSENT"))
                        continue
                    final = occs[-1]
                    if final.value != expected.value:
                        launch_mismatches.append((key, expected.raw, final.raw))
                if launch_mismatches:
                    self.add(
                        "CFG003B",
                        "error",
                        "Declared executor JVM options do not match the effective YARN launch command",
                        "At least one executor JVM option changed or disappeared between submission-time intent and the final launch command.",
                        [f"{key}: expected {exp} ; effective {eff}" for key, exp, eff in launch_mismatches],
                        "Inspect Spark-side command assembly and YARN launch construction to find where the option is overwritten or dropped.",
                    )
            else:
                self.add(
                    "CFG003C",
                    "advisory",
                    "No Java command found in YARN launch evidence",
                    "The detector could not parse a Java command from the provided YARN launch evidence, so effective JVM comparison was skipped.",
                    ["launch evidence present but no java command detected"],
                    "Provide a NodeManager launch script or a log fragment containing the full java invocation.",
                )

    def rule_missing_yarn_conf_channel(self) -> None:
        if self.cluster_manager != "yarn":
            return
        has_conf_dir = any(k in self.spark_env for k in ("HADOOP_CONF_DIR", "YARN_CONF_DIR")) or any(
            k in self.intent_env for k in ("HADOOP_CONF_DIR", "YARN_CONF_DIR")
        )
        has_site_xml = bool(self.core_site or self.yarn_site)
        if not has_conf_dir and not has_site_xml:
            self.add(
                "CFG004",
                "error",
                "No explicit Hadoop/YARN client configuration channel detected",
                "Spark-on-YARN needs either HADOOP_CONF_DIR / YARN_CONF_DIR or explicit site XML files to resolve the ResourceManager and HDFS configuration.",
                ["missing HADOOP_CONF_DIR", "missing YARN_CONF_DIR", "no core-site.xml / yarn-site.xml provided to detector"],
                "Provide HADOOP_CONF_DIR or YARN_CONF_DIR, or include core-site.xml and yarn-site.xml in the analyzed deployment inputs.",
            )

    def rule_spark4_dual_jdk_gate(self) -> None:
        if self.cluster_manager != "yarn":
            return
        try:
            major = int(self.spark_version.split(".")[0])
        except Exception:
            return
        if major < 4:
            return

        missing = []
        if "spark.yarn.appMasterEnv.JAVA_HOME" not in self.effective_conf:
            missing.append("spark.yarn.appMasterEnv.JAVA_HOME")
        if "spark.executorEnv.JAVA_HOME" not in self.effective_conf:
            missing.append("spark.executorEnv.JAVA_HOME")
        if missing:
            self.add(
                "CFG005",
                "warning",
                "Spark 4 on YARN without explicit JAVA_HOME propagation",
                "Spark 4 on YARN needs an explicit JDK propagation plan when Hadoop daemons do not run the same JDK as the Spark application.",
                [f"missing {key}" for key in missing],
                "Set both spark.yarn.appMasterEnv.JAVA_HOME and spark.executorEnv.JAVA_HOME (or equivalent launch-time propagation) before using Spark 4 on YARN.",
            )

    def rule_policy_checks(self) -> None:
        if not self.policy:
            return
        required = self.policy.get("required", [])
        if isinstance(required, list):
            for entry in required:
                if not isinstance(entry, dict):
                    continue
                key = entry.get("key")
                expected = entry.get("equals")
                severity = entry.get("severity", "warning")
                scope = entry.get("scope", "effective_conf")
                title = entry.get("title", f"Required key missing: {key}")
                if not isinstance(key, str):
                    continue
                source = self._resolve_scope(scope)
                actual = source.get(key)
                if actual is None:
                    self.add(
                        "CFG006A",
                        severity,
                        title,
                        f"Policy requires {key}, but it was not found in {scope}.",
                        [f"scope={scope}", f"missing key={key}"],
                        f"Add {key}{'=' + expected if isinstance(expected, str) else ''} to satisfy the deployment policy.",
                    )
                elif expected is not None and str(actual) != str(expected):
                    self.add(
                        "CFG006B",
                        severity,
                        title,
                        f"Policy requires {key}={expected}, but actual value is {actual} in {scope}.",
                        [f"scope={scope}", f"actual {key}={actual}", f"expected {key}={expected}"],
                        f"Change {key} to {expected} for this deployment profile.",
                    )
        equal_sets = self.policy.get("equal_keys", [])
        if isinstance(equal_sets, list):
            for group in equal_sets:
                if not isinstance(group, dict):
                    continue
                keys = group.get("keys", [])
                severity = group.get("severity", "warning")
                title = group.get("title", "Keys expected to be equal are inconsistent")
                if not isinstance(keys, list) or len(keys) < 2:
                    continue
                values = {k: self.effective_conf.get(k) for k in keys}
                non_none = {k: v for k, v in values.items() if v is not None}
                if len(set(non_none.values())) > 1 or len(non_none) != len(keys):
                    self.add(
                        "CFG006C",
                        severity,
                        title,
                        "Deployment policy expects a set of propagated keys to agree, but they do not.",
                        [f"{k}={v}" for k, v in values.items()],
                        "Set these keys to the same effective value or revise the deployment profile if they are intentionally different.",
                    )

    def _resolve_scope(self, scope: str) -> Dict[str, str]:
        mapping = {
            "effective_conf": self.effective_conf,
            "spark_defaults": self.spark_defaults,
            "spark_env": self.spark_env,
            "core_site": self.core_site,
            "yarn_site": self.yarn_site,
            "hive_site": self.hive_site,
            "intent_env": self.intent_env,
        }
        return mapping.get(scope, self.effective_conf)


def parse_conf_file(path: Optional[str]) -> Dict[str, str]:
    if not path:
        return {}
    result: Dict[str, str] = {}
    for raw_line in Path(path).read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        m = CONF_PAIR_RE.match(line)
        if m:
            result[m.group(1)] = m.group(2)
    return result


def parse_env_file(path: Optional[str]) -> Dict[str, str]:
    if not path:
        return {}
    result: Dict[str, str] = {}
    for raw_line in Path(path).read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        m = ENV_RE.match(line)
        if not m:
            continue
        key, value = m.groups()
        value = value.strip().strip('"').strip("'")
        result[key] = value
    return result


def parse_xml_props(path: Optional[str]) -> Dict[str, str]:
    if not path:
        return {}
    text = Path(path).read_text(encoding="utf-8")
    if not text.strip():
        return {}
    root = ET.fromstring(text)
    props: Dict[str, str] = {}
    for prop in root.findall(".//property"):
        name = prop.findtext("name")
        value = prop.findtext("value")
        if name is not None and value is not None:
            props[name.strip()] = value.strip()
    return props


def parse_json(path: Optional[str]) -> Dict[str, object]:
    if not path:
        return {}
    return json.loads(Path(path).read_text(encoding="utf-8"))


def extract_java_command(text: str) -> Optional[str]:
    for line in text.splitlines():
        candidate = line.strip()
        if not candidate:
            continue
        if "java" in candidate and ("org.apache.spark" in candidate or "-cp" in candidate or "-classpath" in candidate):
            return candidate
    return None


def parse_java_opts(option_string: str) -> List[JvmOpt]:
    if not option_string:
        return []
    try:
        tokens = shlex.split(option_string)
    except Exception:
        tokens = option_string.split()
    parsed: List[JvmOpt] = []
    for idx, tok in enumerate(tokens):
        if not tok.startswith("-"):
            continue
        key, value = normalize_jvm_flag(tok)
        parsed.append(JvmOpt(tok, key, value, idx))
    return parsed


def normalize_jvm_flag(token: str) -> Tuple[str, Optional[str]]:
    if token.startswith("-D"):
        body = token[2:]
        if "=" in body:
            k, v = body.split("=", 1)
            return f"-D{k}", v
        return token, None
    if token.startswith("-XX:"):
        if "=" in token:
            k, v = token.split("=", 1)
            return k, v
        return token, None
    if token.startswith("--") and "=" in token:
        k, v = token.split("=", 1)
        return k, v
    if token.startswith("-X") and len(token) > 3:
        return token[:3], token[3:]
    return token, None


def write_human(report: Dict[str, object], out_path: str) -> None:
    summary = report["summary"]
    lines = [
        f"Status: {summary['status']}",
        f"Errors: {summary['errors']}  Warnings: {summary['warnings']}  Advisories: {summary['advisories']}",
        "",
        "Environment:",
        f"  Spark={report['environment']['spark_version']}  Hadoop={report['environment']['hadoop_version']}  Manager={report['environment']['cluster_manager']}  DeployMode={report['environment']['deploy_mode']}",
        "",
        "Findings:",
    ]
    findings = report.get("findings", [])
    if not findings:
        lines.append("  (none)")
    else:
        for idx, finding in enumerate(findings, start=1):
            lines.append(f"{idx}. [{finding['severity'].upper()}] {finding['rule_id']} - {finding['title']}")
            lines.append(textwrap.indent(finding["message"], "   "))
            if finding.get("evidence"):
                lines.append("   Evidence:")
                for item in finding["evidence"]:
                    lines.append(f"   - {item}")
            lines.append(f"   Recommendation: {finding['recommendation']}")
            lines.append("")
    Path(out_path).write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--intent")
    parser.add_argument("--spark-defaults")
    parser.add_argument("--spark-env")
    parser.add_argument("--core-site")
    parser.add_argument("--yarn-site")
    parser.add_argument("--hive-site")
    parser.add_argument("--yarn-launch-log")
    parser.add_argument("--policy")
    parser.add_argument("--spark-version", required=True)
    parser.add_argument("--hadoop-version", required=True)
    parser.add_argument("--cluster-manager", default="yarn")
    parser.add_argument("--deploy-mode", default="cluster")
    parser.add_argument("--json-out", required=True)
    parser.add_argument("--human-out", required=True)
    args = parser.parse_args()

    guard = Guard(
        intent=parse_json(args.intent),
        spark_defaults=parse_conf_file(args.spark_defaults),
        spark_env=parse_env_file(args.spark_env),
        core_site=parse_xml_props(args.core_site),
        yarn_site=parse_xml_props(args.yarn_site),
        hive_site=parse_xml_props(args.hive_site),
        yarn_launch_text=Path(args.yarn_launch_log).read_text(encoding="utf-8") if args.yarn_launch_log else "",
        policy=parse_json(args.policy),
        spark_version=args.spark_version,
        hadoop_version=args.hadoop_version,
        cluster_manager=args.cluster_manager,
        deploy_mode=args.deploy_mode,
    )
    report = guard.run()

    out_json = Path(args.json_out)
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    write_human(report, args.human_out)
    print(f"wrote {out_json}")
    print(f"wrote {args.human_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
