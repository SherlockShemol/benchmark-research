# 评估方法横向对比分析表

## 一、核心维度对比

| Benchmark | 类别 | 评估目标 | 数据规模 | 评估方式 | 核心指标 | 防污染 | 自动化 | 人类基线 | SOTA |
|-----------|------|---------|---------|---------|---------|--------|--------|---------|------|
| HumanEval | 代码生成 | 功能正确性 | 164 题 | **`evaluate_functional_correctness`**（Fire CLI）→ 子进程 exec + 默认 3s + **`reliability_guard`**；须 **解除 execution.py 注释**；**每题至少一条样本** | pass@k（Chen 无偏；全题 n≥k 才报该 k） | 无 | 全自动 | ~100% | [Papers w/ Code](https://paperswithcode.com/sota/code-generation-on-humaneval) 聚合；原箱 >90% 饱和 |
| MBPP | 代码生成 | 基础编程 | 974 题（常报 test 500） | 提取代码 + 执行 `test_list`；**lm-eval 默认** `mbpp.yaml`→`code_eval` pass@1 | 文献常用 pass@k；框架默认常是 **pass@1 均值** | 无 | 全自动 | ~100% | 聚合榜常见 **~88%～91%+** pass@1（视 split/harness） |
| LiveCodeBench | 代码生成 | 多维代码能力 | 持续 release（如 v6≈1055） | `run_test`+`pass_k_utils`；四 Scenario | pass@k 等 | contest_date 过滤 | 全自动 | N/A | [官方 Leaderboard](https://livecodebench.github.io/leaderboard.html) |
| Aider Polyglot | 代码编辑 | 多语言编辑 | 225 题 | `benchmark/benchmark.py` + `run_unit_tests`；需 `AIDER_DOCKER` | `pass_rate_1` 首轮 / `pass_rate_2` 两轮内累积 | 无 | 容器内全自动 | N/A | 榜前列含 gpt-5（high）等；见 [Aider 榜](https://aider.chat/docs/leaderboards/) |
| SWE-bench | 软件工程 | Issue 修复 | Full 2,294；Lite 300 | **`run_evaluation`**（默认 **Lite** HF 名）；`gold` 自检；**`make_run_report`**；Docker：`GIT_APPLY_CMDS`→`/eval.sh`→`get_eval_report`；**仅 FULL**；XFAIL；FAIL_ONLY | resolve rate | 无 | 全自动 | ~90%+ | [swebench.com](https://www.swebench.com/) 实时 Full/Lite；勿与 Multimodal/sb-cli 混行 |
| SWE-bench Verified | 软件工程 | Issue 修复 | 500 题 | 同 SWE-bench harness；`--dataset_name SWE-bench/SWE-bench_Verified`；可选 **`--modal`** | resolve rate | 人工验证（不防泄漏） | 全自动 | N/A | [swebench.com/verified](https://www.swebench.com/verified)；高分伴泄漏争议，建议对照 Pro/Live |
| SWE-bench Pro | 软件工程 | 长时间跨度任务 | 全量 1,865；公开榜 **731** | Modal/本地 Docker；`entryscript`→`parser.py`→**并集 f2p∪p2p ⊆ PASSED 测试名** | resolve rate | copyleft 公开子集 + 私有子集 | 全自动 | N/A | [Scale 榜](https://scale.com/leaderboard/swe_bench_pro_public) 前列约 **~46%**（Claude Opus 4.5，250-turn 无上限口径） |
| SWE-bench Live | 软件工程 | 防污染评估 | HF 多 split（lite/verified/full/test） | `run_evaluation` + `test_cmds`/`log_parser` | resolve rate | 冻结子集+full 增量 | 全自动 | N/A | [官方榜单](https://swe-bench-live.github.io/) |
| SWE-PolyBench | 软件工程 | 多语言仓库级 | 2,110（PB500/PBv） | `evaluate_instance`：patch→`docker_run`→parser→`scoring`；`metric_scoring` | resolved + file/node F1 | PBv 人工验证 | 全自动 | N/A | [官网榜](https://amazon-science.github.io/SWE-PolyBench/) Verified 前列常 30–50% resolve 量级 |
| BFCL | 函数调用 | 工具使用准确性 | V4 多类别 | `ast_checker`；多轮 **状态+返回**；Agentic **标准化文本匹配**；Typer **`bfcl_eval evaluate`** | 五桶 **`[10,10,10,30,40]`** 归一化加权（与榜页 Overall 文案勿混） | Live API 子集 | 全自动 | N/A | [BFCL V4](https://gorilla.cs.berkeley.edu/leaderboard.html)（固定 commit / `bfcl-eval` 复现） |
| ToolBench | 函数调用 | 万级真实 API 工具链 | 16K+ API | `eval_pass_rate`：默认 **4×** 评测器采样/题；无 Finish 即败；**TSV 平局随机 vs 控制台 pass_rate（平局计通过）** | pass rate + win rate | 弱 | 半自动(评测LLM) | N/A | [OpenBMB](https://openbmb.github.io/ToolBench/) / [HF Space](https://huggingface.co/spaces/qiantong-xu/toolbench-leaderboard) |
| Tau-Bench | 函数调用 | 对话+工具+模拟用户 | retail / airline | `sha256` 数据结构哈希 + GT 重放；`RESPOND` 子串对 `outputs` | avg reward + Pass^k（`comb(c,k)/comb(n,k)`） | 无 | 半自动(LLM 用户) | N/A | [HAL 分域榜](https://hal.cs.princeton.edu/taubench_retail) 等；勿信「telecom」域 |
| GAIA | Agent 推理 | 多步推理+工具 | 公开常写 466；**榜侧 test=301**（`app.py` `ref_scores_len`） | 提交 JSONL → `question_scorer` 对私有 GT | accuracy（Overall/Level） | Gated+test 答案闭源 | 全自动（榜单侧） | ~92% 人类 | 见 [HF Leaderboard](https://huggingface.co/spaces/gaia-benchmark/leaderboard) |
| AgentBench | Agent 推理 | **FC 5 任务** / **经典 8 环境（v0.2）** | 多子集 | HTTP **`start_sample`/`interact`/`calculate_overall`**；Compose 或 **`start_task`** | **`validation`+`custom`**；`analysis` 抽主指标 | 无统一防污染 | 全自动+重环境 | 因任务而异 | [FC 表格榜](https://docs.google.com/spreadsheets/d/e/2PACX-1vRR3Wl7wsCgHpwUw1_eUXW_fptAPLL3FkhnW_rua0O1Ji_GIVrpTjY5LaKAhwO-WeARjnY_KNw0SYNJ/pubhtml) · [论文 PDF](https://openreview.net/pdf?id=zAdUB0aCTQ) |
| WebArena | GUI 交互 | Web 任务完成 | 812 题 | **`EvaluatorComb`** 连乘；URL **base×query**；**`early_stop`**；LLM **fuzzy/ua** | 成功率（均值） | 自托管环境 | 半自动(LLM 子判) | ~78% | 见论文/Verified；二手榜常报 70%+ |
| OSWorld | GUI 交互 | 真实桌面多应用任务 | 369（**8 道 Drive 可排除→361**） | **`run_single_example`**：录制+**`traj.jsonl`/截图**→**`evaluate()`**→**`result.txt`**；`run.py` 默认 **max_steps=15**；`show_result.py` 聚合 | Success Rate（%） | OSWorld-Verified 流程 | 半自动+重环境 | ~72%（论文） | [官网 Verified 榜](https://os-world.github.io/)（勿与旧论文最佳 ~12% 混比） |
| AndroidWorld | GUI 交互 | Android 端多 App 任务 | 116 模板 × 参数组合 | 步数 **`int(10×complexity)`**；MiniWoB **`termination_fn`**；**`is_successful` ∧ `done`** | 按模板 **`mean_success_rate`**（`process_episodes`） | 动态实例 | 重环境+API | 见论文/官网 | [官网](https://google-research.github.io/android_world/) · [表格榜](https://docs.google.com/spreadsheets/d/1cchzP9dlTZ3WXQTfYNhh3avxoLipqHN75v1Tb86uhHo/edit?gid=0#gid=0) |

## 二、评估流程复杂度分级

| 等级 | 描述 | 代表 Benchmark | 环境需求 | 单次评估耗时 |
|------|------|---------------|---------|-------------|
| **L1** | 简单 I/O 匹配 | GAIA | 无 | 秒级 |
| **L2** | 代码执行+测试用例 | HumanEval, MBPP, LiveCodeBench | Python 环境 | 分钟级 |
| **L3** | Docker 隔离+测试套件 | SWE-bench 家族, SWE-PolyBench | Docker + 120GB | 30-50 分钟 |
| **L4** | 多轮交互+状态验证 | BFCL (multi-turn), Tau-Bench | Python + LLM API | 分钟级/题 |
| **L4+** | 多环境 Docker Worker + 统一调度 | AgentBench | Controller + 多任务镜像 | 小时～天级（视子集） |
| **L5** | 自托管 Web 环境 | WebArena | Docker×7 + 浏览器 | 小时级 |
| **L6** | 桌面 VM / 云并行 | OSWorld | VMware/Docker(KVM)/AWS + GUI | 小时～天级 |
| **L6′** | Android 模拟器 + ADB | AndroidWorld | AVD + grpc + 首次 app setup | 小时级～ |

## 三、评估指标分类

### 3.1 二值指标（通过/不通过）

| 指标 | 代表 | 判定规则 |
|------|------|----------|
| **pass@k** | HumanEval, MBPP, LiveCodeBench | k 个样本中至少 1 个全部测试通过 |
| **resolve rate** | SWE-bench 家族 | **原版 harness**：**FULL**（F2P 与 P2P 成功率均为 1）才计 **resolved**，PARTIAL 不计；**Pro 官方脚本**：测试名集合 **`(f2p∪p2p)⊆{name: status==PASSED}`** |
| **success rate** | WebArena | **`EvaluatorComb`** 各子评估器得分连乘为 1；子评估器内部多条件常再连乘 |
| **reward** | Tau-Bench | `sha256` 结构化 data 哈希 vs GT 重放；`RESPOND` 文本子串对 `outputs` |

### 3.2 精确匹配指标

| 指标 | 代表 | 判定规则 |
|------|------|----------|
| **exact match** | GAIA | 官方 `normalize_str` / 数值归一 / 列表元素对齐 |
| **AST match** | BFCL | `ast_checker` 路由 + `simple_function_checker` 等；多轮另含 **实例状态对齐 + 返回无序覆盖** |

### 3.3 连续值/细粒度指标

| 指标 | 代表 | 说明 |
|------|------|------|
| **file recall/precision/F1** | SWE-PolyBench | 修改文件集合的匹配度 |
| **node recall/precision/F1** | SWE-PolyBench | AST 节点路径的匹配度 |
| **加权准确率** | BFCL | 5 大桶按 [10,10,10,30,40] 归一化加权（`data_overall.csv`）；子桶内另有 unweighted/weighted 组合 |
| **Pass^k** | Tau-Bench | `run.py`：`Σ_t comb(c_t,k)/comb(n,k) / |tasks|`（论文一致） |

## 四、防污染策略对比

| 策略 | 原理 | 效果 | 代表 |
|------|------|------|------|
| **无** | 不做防污染 | 差 | HumanEval, MBPP |
| **人工验证** | 人工审核数据质量 | 中 | SWE-bench Verified |
| **时间分割** | 仅使用训练截止后数据 | 好 | LiveCodeBench, SWE-bench Live |
| **私有 / copyleft 设计** | 专有子集不公开；公开子集强 copyleft 降训练污染 | 好 | SWE-bench Pro |
| **自托管环境** | 评估环境不在公网 | 好 | WebArena |
| **答案不公开** | 测试集答案仅在排行榜评估 | 中 | GAIA |
| **Live 数据** | 使用实时 API 数据 | 好 | BFCL (Live 分类) |
| **模拟 API 环境** | 固定响应重放降低漂移 | 中～好 | StableToolBench（ToolBench 生态） |

## 五、评估模式演进

```
简单匹配 (pass@k)
    │
    ▼
执行验证 (Docker + test suite)
    │
    ▼
多维度评估 (generation + repair + execution)
    │
    ▼
交互式评估 (对话 + 工具调用 + 状态验证)
    │
    ▼
真实环境评估 (自托管 Web + 浏览器自动化)
```

### 关键趋势

1. **从静态到动态**：固定数据集 → 持续更新 → 实时环境
2. **从单维到多维**：pass@k → resolve rate + retrieval + repair
3. **从简单到真实**：算法题 → GitHub Issue → Web 任务
4. **从 Python 到多语言**：Python only → 4-6 种语言
5. **从模型到 Agent**：纯生成 → 工具使用 → 多步推理 → 环境交互

## 六、选用建议

| 评估需求 | 推荐 Benchmark |
|----------|---------------|
| 快速验证代码生成能力 | LiveCodeBench (防污染) |
| 评估真实软件工程能力 | SWE-bench Pro (最新最严) |
| 评估多语言能力 | SWE-PolyBench / Aider Polyglot |
| 评估函数调用/工具使用 | BFCL (结构化 AST) / ToolBench (开放域 API+ToolEval) / Tau-Bench (对话式) |
| 评估多环境 Agent 基础能力 | AgentBench（对齐 **FC vs v0.2** 协议与任务集） |
| 评估综合 Agent 能力 | GAIA (通用) / WebArena (Web 专项) / OSWorld (桌面 GUI) / AndroidWorld (移动端) |
| 需要人类对比基线 | GAIA (92%) / WebArena (~78%) |
