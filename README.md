# AI Benchmark 评估方法调研

系统性调研 AI 编码/Agent Benchmark 的评估方法论，建立结构化的知识库和对比分析框架。

## 项目结构

```
benchmarks/
  coding-generation/       代码生成类（HumanEval, MBPP, LiveCodeBench, Aider Polyglot）
  software-engineering/    软件工程类（SWE-bench 家族, SWE-PolyBench）
  function-calling/        函数调用类（BFCL, Tau-Bench, ToolBench）
  agent-reasoning/         Agent 推理类（GAIA, AgentBench, WebArena）
  computer-interaction/    GUI 交互类（OSWorld, AndroidWorld）
meta/                      元分析框架（BetterBench, BENCHMARK², ABC）
comparisons/               跨 benchmark 对比分析
repos/                     Clone 的 benchmark 源码仓库（.gitignore 排除）
scripts/                   辅助脚本（如 `clone-benchmark-repos.sh` 浅克隆常用上游仓）
```

## 每个 Benchmark 笔记覆盖的维度

| 维度 | 说明 |
|------|------|
| 基本信息 | 名称、来源机构、论文/GitHub/数据集链接 |
| 评估目标 | 测试的核心能力 |
| 任务构造 | 数据来源、筛选/清洗方式 |
| 评估指标 | pass@k、resolve rate、accuracy 等 |
| 评估流程 | 人工评估 vs 自动评估，Docker harness 等 |
| 防污染机制 | 时间分割、私有测试集等 |
| 已知局限 | 饱和问题、数据泄漏、单语言偏差等 |
| 当前 SOTA | 最佳模型表现及人类基线 |

## 调研进度

- [x] SWE-bench 家族（原版 / Verified / Pro / Live / PolyBench）
- [x] 代码生成类（HumanEval / MBPP / LiveCodeBench / Aider Polyglot）
- [x] Agent/工具使用类（GAIA / Tau-Bench / BFCL / WebArena / AgentBench）
- [x] 元分析框架（BetterBench / BENCHMARK² / ABC）
- [x] 横向对比分析表
- [ ] GUI 交互类深入（OSWorld / AndroidWorld）
- [ ] 更多 benchmark 持续发现中...

## 已 Clone 的仓库 (repos/)

| 仓库 | 目录 | 类别 |
|------|------|------|
| SWE-bench | repos/swe-bench | 软件工程 |
| SWE-bench Pro | repos/swe-bench-pro | 软件工程 |
| SWE-PolyBench | repos/swe-polybench | 软件工程 |
| LiveCodeBench | repos/LiveCodeBench | 代码生成 |
| Aider Polyglot | repos/aider-polyglot | 代码编辑 |
| Gorilla (BFCL) | repos/gorilla | 函数调用 |
| Tau-Bench | repos/tau-bench | 函数调用 |
| WebArena | repos/webarena | GUI 交互 |
| AgentBench | repos/AgentBench | Agent 推理 |
| Benchmark Compendium | repos/benchmark-compendium | 元分析 |
