#!/usr/bin/env bash
# 用法：scripts/ci.sh core|ios   推送後等該 workflow 跑完，印出結果與失敗摘要。
PYTHONUTF8=1 PYTHONIOENCODING=utf-8 exec python "$(dirname "$0")/ci.py" "$@"
