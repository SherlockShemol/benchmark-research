#!/usr/bin/env bash
# 将常用 benchmark 上游仓浅克隆到 repos/（目录已在 .gitignore）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPOS="$ROOT/repos"
mkdir -p "$REPOS"
cd "$REPOS"

clone_shallow() {
  local url="$1" name="$2"
  if [[ -d "$name/.git" ]]; then
    echo "[skip] $name already exists"
    return 0
  fi
  echo "[clone] $url -> repos/$name"
  git clone --depth 1 "$url" "$name"
}

# MBPP / 多任务 LM 评测（笔记 mbpp.md 引用 lm_eval/tasks/mbpp）
clone_shallow "https://github.com/EleutherAI/lm-evaluation-harness.git" "lm-evaluation-harness"

# Aider Polyglot harness（笔记 aider-polyglot.md）
clone_shallow "https://github.com/Aider-AI/aider.git" "aider"

echo "Done. Existing repos (OSWorld, swe-bench, human-eval, …) 请按需自行维护。"
