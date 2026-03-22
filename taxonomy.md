# Benchmark 分类体系总览

## 1. 代码生成 (Code Generation)

| Benchmark | 语言 | 规模 | 核心评估方式 | 状态 |
|-----------|------|------|-------------|------|
| HumanEval | Python | 164 题 | 官方 **`evaluate_functional_correctness`**（Fire CLI）→ 子进程 exec + **`reliability_guard`**；**Chen 无偏 pass@k**；逐题须 **n≥k** 才报该 k | 已饱和 |
| MBPP | Python | 974 题 | 文献/社区常用 pass@k；**lm-eval 默认 `mbpp`** 为 **test + few-shot + `code_eval` pass@1 均值**（见 `lm_eval/tasks/mbpp`） | 已饱和 |
| LiveCodeBench | Python | 持续更新（如 v6 千题级） | `pass_k_utils` pass@k + 四 Scenario；`compute_scores` 按 contest_date 过滤 | 活跃 |
| Aider Polyglot | 6 语言 | 225 题 | Exercism 语料 + Aider `benchmark/benchmark.py`（Typer）；容器内需 `AIDER_DOCKER`；`pass_rate_*` 汇总 `.aider.results.json` | 活跃 |
| BigCodeBench | Python | 1,140 题 | pass@k + 工具调用 | 活跃 |

## 2. 软件工程 (Software Engineering)

| Benchmark | 语言 | 规模 | 核心评估方式 | 状态 |
|-----------|------|------|-------------|------|
| SWE-bench | Python（ICLR 主集）；harness 兼服务 Multimodal/Live 等 | 2,294 题（Full）；Lite 300 | **`run_evaluation`**：`gold` 自检；**`-d` 默认 Lite**；**`make_run_report`**→**`{model}.{run_id}.json`**；`grading`：**仅 FULL→resolved**；**XFAIL 计通过**；**`FAIL_ONLY_REPOS`**；标记间解析 + 全日志回退 | 基础版；榜见 [swebench.com](https://www.swebench.com/) |
| SWE-bench Verified | Python | 500 题 | 与 SWE-bench 共用 `run_evaluation` + Docker；换 HF `dataset_name` 即可 | 仍常用作固定子集；主榜趋势转向 Pro/Live |
| SWE-bench Pro | 多语言 | 全量 1,865 题；[公开榜](https://scale.com/leaderboard/swe_bench_pro_public) 子集 **731** | Docker harness；评分 **`(f2p∪p2p)⊆PASSED`**；copyleft/私有子集防污染 | 最新 |
| SWE-bench Live | Python 为主 + 多语言/Windows 扩展 | HF `SWE-bench-Live/SWE-bench-Live`：`lite`/`verified`/`full`/`test` 等 split | 同 SWE-bench harness；`--dataset_name` + `--split` | 活跃 |
| SWE-PolyBench | 4 语言 | 2,110 题（PB500/PBv 子集） | Docker + 每 repo log parser；resolved + file/node（Tree-Sitter）检索 F1 | 活跃 |

## 3. 函数调用与工具使用 (Function Calling & Tool Use)

| Benchmark | 规模 | 核心评估方式 | 状态 |
|-----------|------|-------------|------|
| BFCL | 多类别（V4：Non-Live/Live/Irrelevance/Multi-Turn/Agentic 等） | Typer：`generate`→`evaluate`→`data_*.csv`；多轮 **`state_checker`+无序 `response_checker`**；Agentic **`agentic_checker`（标准化+词界正则）**；Overall 以 **`calculate_percentage_weighted_accuracy(...,[10,10,10,30,40])`** 为准（与官网「未加权」文案勿混） | 活跃 |
| Tau-Bench | 对话式 | retail/airline：`calculate_reward` 比 DB 哈希 + 可选 `outputs` 子串；`run.py` 聚 Pass^k | 活跃 |
| ToolBench | 16,000+ API | ToolEval：`eval_pass_rate` 默认 **`evaluate_times=4`** 累加 passed/failed；Finish 门闩 + 注册评测器 LLM 判；**TSV 平局随机 vs 控制台 pass_rate（平局计通过）** | 活跃 |
| ComplexFuncBench | 复杂调用 | 多步/长上下文调用 | 活跃 |
| LiveMCPBench | MCP 工具 | 真实 MCP 服务器交互 | 新兴 |

## 4. Agent 推理 (General Assistant & Reasoning)

| Benchmark | 规模 | 核心评估方式 | 状态 |
|-----------|------|-------------|------|
| GAIA | 450+ / 466（三 Level） | HF Leaderboard：`question_scorer` 数值/列表/字符串归一化 | 活跃 |
| AgentBench | **FC：`main` 上 5 任务容器栈**；**经典：8 环境（v0.2）** | HTTP **`/start_sample`→`/interact`→`/calculate_overall`**；**`overall.json`**=`validation`（状态占比）+**`custom`**（worker 指标）；**`analysis.py`** 抽 per-task 主指标 | 活跃 |
| AssistantBench | 214 题 | Web 导航任务完成 | 活跃 |
| LiveBench | 持续更新 | 防污染 + 多维度 | 活跃 |
| HLE | 2,500 题 | 专家级学术问答 | 活跃 |

## 5. 计算机交互 (Computer Interaction / GUI)

| Benchmark | 平台 | 规模 | 核心评估方式 | 状态 |
|-----------|------|------|-------------|------|
| WebArena | Web | 812 题 | **`EvaluatorComb`**（`eval_types` 连乘）+ **String/URL/HTML** 内部连乘；**`early_stop`**（max_steps / 解析失败 / 重复动作）；**LLM fuzzy/ua** | 活跃 |
| OSWorld | Win/Mac/Linux | ~369 题（+ Verified 维护版） | VM 内任务 + `result.txt` 分数聚合为 Success Rate | 活跃 |
| AndroidWorld | Android | 116 模板 + 参数化多实例 | **`episode_runner.run_episode`**：`max_n_steps=int(10*complexity)`；MiniWoB 用 **`termination_fn`**；成功需 **`is_successful` ∧ agent `done`**；**`process_episodes`** 按模板聚 **`mean_success_rate`** | 活跃 |
| Mind2Web | Web | 2,000+ 题 | 真实网站导航 | 活跃 |
| BrowseComp | Web | 1,266 题 | 深度网页搜索 | 活跃 |
