#!/usr/bin/env bash
set -e

case "${1:-help}" in
  help)
    echo "EC528 ConfigProp Prototype"
    echo
    echo "Usage:"
    echo "  docker run --rm ec528-configprop:v1 case1"
    echo "  docker run --rm ec528-configprop:v1 case2"
    echo "  docker run --rm -it ec528-configprop:v1 bash"
    echo
    echo "Commands:"
    echo "  case1   Run modern_yarn_buggy demo"
    echo "  case2   Run spark4_dual_jdk_buggy demo"
    echo "  bash    Enter interactive shell"
    ;;
  case1)
    exec /app/run_case1.sh
    ;;
  case2)
    exec /app/run_case2.sh
    ;;
  bash)
    exec bash
    ;;
  *)
    echo "Unknown command: $1"
    echo "Run: docker run --rm ec528-configprop:v1 help"
    exit 1
    ;;
esac
