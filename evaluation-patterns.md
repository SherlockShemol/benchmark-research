# 跨 Benchmark 评估模式总结

## 评估模式分类

### 模式 1：Pass@k（代码生成类）
- **代表**：HumanEval, MBPP, LiveCodeBench
- **原理**：生成 k 个候选方案，至少 1 个通过所有测试即算通过
- **公式**：`pass@k = 1 - C(n-c, k) / C(n, k)`（n 个样本、c 个通过）；**HumanEval** 实现用等价乘积形式 **`1 - ∏_{i=1}^{k}(1 - k/(n-c+i))`**（`human_eval/evaluation.py`），且仅当 **每题 `n ≥ k`** 才输出该 k 的 `pass@k`；逐条结果落盘 **`{sample_file}_results.jsonl`**（函数 docstring 仍写 `.gz`，以代码为准）
- **HumanEval 入口**：`pip install -e` 后 **`evaluate_functional_correctness`**（**Fire**：`sample_file` 位置参数，**`--k=1,10,100`**）；运行前通常需在 **`execution.py`** 按 README **解除 exec 注释**并接受非安全沙箱声明
- **LiveCodeBench 实现要点**：`compute_metrics_from_results` 将每条生成在所有测例上的返回值转为布尔 **`np.all(gen > 0)`** 再聚合成每题的 (n,c)；另可用 **`compute_scores.py`** 对已保存的 **`graded_list`** 做 **contest_date / platform** 切片后调用同一 `estimate_pass_at_k`
- **优点**：简单直接，无偏估计
- **缺点**：容易饱和，不考虑代码质量，仅反映功能正确性

- **变体：Aider Polyglot（非 pass@k）**：`benchmark/benchmark.py` 驱动 Aider **编辑已有解答文件**并执行语言原生测试；每题最多 `--tries` 轮，失败则将测试输出反馈给下一轮。汇总时 **`pass_rate_1`** 近似「首轮即全过」占比，**`pass_rate_2`**（默认 tries=2）为「两轮内曾全过」的累积占比（见 `summarize_results` 对 `tests_outcomes` 的计数）。正式跑分需在设 **`AIDER_DOCKER`** 的容器中进行，否则脚本直接退出。

- **易混：MBPP（lm-eval 默认任务）**：`lm_eval/tasks/mbpp/mbpp.yaml` 使用 **`utils.pass_at_1`** + HuggingFace **`code_eval`**、**`do_sample: false`**，报告的是 **pass@1 类均值**；与 Chen et al. **多采样无偏 pass@k** 需改配置并保证 n≥k，不可与 HumanEval 笔记中的 pass@k 公式混为一谈。

### 模式 2：Fail-to-Pass 测试转换（软件工程类）
- **代表**：SWE-bench 家族, SWE-PolyBench
- **原理**：模型生成 patch，必须使失败测试通过（F2P）且不引入回归（P2P）
- **核心判定**：`resolved = (F2P 全通过) AND (P2P 全保持)`
- **SWE-bench 官方 harness**（`repos/swe-bench/swebench/harness/grading.py`）：先 **`get_eval_tests_report`** 得到 F2P/P2P 的 success 列表，再 **`compute_fail_to_pass` / `compute_pass_to_pass`**（分母为列表长度，空列表得 **1**）；**`get_resolution_status` 为 FULL** 时 **`resolved=True`**（PARTIAL 不算）；**`test_passed` 把 `XFAIL` 视作通过**；**`FAIL_ONLY_REPOS`** 走 **`EvalType.FAIL_ONLY`**。日志 **`get_logs_eval`**：标记间解析失败时**回退解析整份日志**。
- **SWE-bench Pro 脚本口径**：`swe_bench_pro_eval.py` 从 **`parser.py`→`output.json`** 取 **`PASSED` 测试名集合**，与元数据 **`fail_to_pass` / `pass_to_pass`** 做 **`(f2p | p2p) <= passed_tests`**；对外主榜常用 **731** 题公开子集（全量 **1,865**）
- **实现**：Docker 三层镜像架构 + eval.sh 执行测试 + 日志解析；**`run_evaluation`** 默认 **`--dataset_name SWE-bench/SWE-bench_Lite`**，报 **Full 2,294** 时需显式 **`princeton-nlp/SWE-bench`**（或当前 HF 等价名）+ **`--split test`**；收尾 **`make_run_report`** 写 **`{model}.{run_id}.json`**；**Multimodal** 等另走 **sb-cli**，与经典 Full 不同榜
- **Verified 子集**：与全量集 **同一 harness**（`repos/swe-bench/swebench/harness/run_evaluation.py`）；仅 **`--dataset_name`**（如 `SWE-bench/SWE-bench_Verified`）与实例元数据不同，**不要**假设存在另一套评分逻辑
- **优点**：贴近真实软件工程，端到端验证
- **缺点**：依赖测试覆盖率，构造成本高，可能高估能力（ABC 发现）

### 模式 3：时间分割防污染（持续更新类）
- **代表**：LiveCodeBench, SWE-bench Live, LiveBench
- **原理**：持续从新发布的数据源采集题目，按 `contest_date` / `issue_date` 过滤
- **用法**：`--start_date 2024-01-01` 仅评估该日期后的题目；**SWE-bench Live** 另以「近年 issue + 月度增量数据集」实现类似效果，**评分逻辑与 SWE-bench 共用**；HF 上 **`SWE-bench-Live/SWE-bench-Live`** 提供 **`lite` / `verified` / `full` / `test`** 等 split（`run_evaluation.py` 的 **`--split`** 与 **`--dataset_name`** 对齐所选榜单口径；`full` 随月度更新，`lite`/`verified` 常冻结）
- **优点**：有效防止数据污染，可检测模型的污染程度
- **缺点**：维护成本高，题目难度可能不稳定

### 模式 4：交互式环境评估（Web/GUI Agent 类）
- **代表**：WebArena, OSWorld, AndroidWorld
- **原理**：在浏览器或桌面 VM 中多步交互，依据**任务定制**的判定逻辑给出成功/分数
- **WebArena**：**`evaluator_router`→`EvaluatorComb`** 对 **`string_match` / `url_match` / `program_html`** 子评估器**顺序连乘**；URL 子项为 **base_score × 各 query 键因子**；HTML 对 **targets** 内 **exact/must_include** 继续连乘；主循环每步先 **`early_stop`** 再 **`agent.next_action`**；**fuzzy_match / ua_match** 走 LLM
- **OSWorld**：**`run_single_example`**：**reset + 录制 + predict/step 循环** 写 **PNG/traj.jsonl**，再 **`evaluate()`→`result.txt`/`recording.mp4`**；**`DesktopEnv.evaluate()`** 按 JSON 的 **`metric` + `result_getter`（± expected）** 与 **`metric_conj`** 聚合；**`run.py` 默认 `max_steps=15`**（与 WebArena 默认 30 不同）
- **AndroidWorld**：**Android 模拟器 + AndroidEnv/ADB**；**`suite_utils.run`** 内 **`max_n_steps = int(10 * task.complexity)`**；**MiniWoB** 任务名前缀触发 **`termination_fn`** 可提前结束；每任务 **`initialize_task` → run_episode → `is_successful(env)`**；仅当 **`interaction_results.done`** 为真时才采纳成功信号，否则记 **0**；**`process_episodes`** 按 **`task_template` groupby** 得 **`mean_success_rate`**
- **优点**：贴近真实人机交互与长程操作
- **缺点**：环境搭建与复现成本极高；WebArena 等仍可能依赖 LLM fuzzy match；OSWorld 依赖 VM/账号/网络配置；AndroidWorld 依赖 AVD/首次 setup 与 step budget 对齐

### 模式 5：数据库状态哈希验证（对话式 Agent）
- **代表**：Tau-Bench
- **原理**：Agent 通过对话+工具调用修改内存中的结构化 **`data`**；评测时用 **`to_hashable` + `sha256(str(...))`** 得到 **`data_hash`**，再在**干净库**上按 **`task.actions` 重放** ground truth 得到 **`gt_data_hash`**，二者须一致
- **判定**：**`data_hash == gt_data_hash`**；若 **`task.outputs` 非空**，还需某次 **`RESPOND`** 的 **`content`**（去逗号、小写）**包含**各 `output.lower()` 子串（见 `repos/tau-bench/tau_bench/envs/base.py` **`calculate_reward`**）
- **Pass^k**：`run.py` **`display_metrics`** 用 **`comb(c,k)/comb(n,k)`** 对每题聚合（**`n=num_trials`**），与论文 § 指标一致
- **优点**：端到端验证业务库终态，不依赖逐步对齐 GT 工具链
- **缺点**：二值 reward；**仅 retail/airline**；策略仅间接验证；输出匹配规则偏启发式

### 模式 6：AST 结构匹配（函数调用类）
- **代表**：BFCL
- **原理**：将模型输出解码为结构化函数调用；`ast_checker` 按 `test_category` 路由到 **parallel（无序）/ multiple（顺序）/ simple（单调用且 `len(model_output)==1`）**，再走 `simple_function_checker` 等做类型与 `possible_answer` 校验
- **检查项**：`convert_func_name`（含部分模型 `_`↔`.`）、必选参数、禁止多余参数、语言相关类型转换与值集合
- **变体**：simple / parallel / multiple；另含 **multi-turn**、**agentic**（非本模式纯 AST，见仓库 `multi_turn_checker` / `agentic_checker`）
- **优点**：可自动化评估，结果客观
- **缺点**：不考虑调用时机和上下文理解

### 模式 7：精确匹配 + 标准化（问答类）
- **代表**：GAIA, SimpleQA
- **原理**：对最终答案字符串做**确定性**归一化再判等；**GAIA** 官方 `question_scorer` 分三支：**纯数值**（去 `$% ,` 后转 float）、**列表**（按 `,`/`;` 切分、长度对齐、元素级数值或 `normalize_str(remove_punct=False)`）、**普通字符串**（去空白 + 可选去标点 + 小写）
- **Test 集**：GAIA **答案不公开**，全量 test 仅能通过 **Hugging Face Leaderboard** 服务端计分；自评只对 dev 等公开答案子集有效
- **优点**：可完全自动、可复现（同一 `scorer.py`）
- **缺点**：归一化规则无法覆盖所有等价表述；Gated 数据与闭卷 test 增加参与门槛

### 模式 8：LLM 评判工具轨迹（大规模 API 类）
- **代表**：ToolBench (ToolEval)
- **原理**：将模型完整调用轨迹（含中间步与 `Finish`）交给配置好的评测模型，通过 `check_is_solved` / `check_task_solvable` / `is_passed` 等函数调用链判定是否解决；pass rate 可对同题多次采样再多数决，平局随机
- **变体**：成对轨迹偏好比较得到 **win rate**，用于模型间相对排序
- **优点**：可评估开放域 API 任务，不依赖单一可执行黄金用例
- **缺点**：强依赖评测 LLM 主观性与稳定性；真实 API 漂移影响复现（可用 StableToolBench 等模拟环境缓解）

### 模式 9：多层级指标组合（综合类）
- **代表**：SWE-PolyBench, BFCL
- **原理**：组合多个不同粒度的指标
- **SWE-PolyBench**：**`scoring.instance_level_scoring`** 产出 **F2P/P2P 语义 resolved**；**`metrics.metric_scoring.instance_level_metric_scoring`** 产出 **file_retrieval_metrics** 与可选 **node_retrieval_metrics**（sklearn F1）；全流程由 **`run_evaluation.evaluate_instance`** 串 Docker 应用 patch、**`docker_run` + 按 repo 的 log parser**、写 **`_result.json` / `_metrics.json`**
- **BFCL**：**`python -m bfcl_eval`** 流水线生成结果再 **`evaluate`**；五桶 overall 用 **`calculate_percentage_weighted_accuracy(..., [10,10,10,30,40])`**（`eval_runner_helper.py`）。**多轮**侧每 turn 比对 **模拟对象状态** + **执行返回无序子序列**（`multi_turn_checker`）。**Agentic** 对末条回复做 **`standardize_string` + `\b...\b` 匹配**（`agentic_checker.py`）。**官网 Leaderboard 对 Overall 的文字描述**可能与脚本加权和不一致，复现以 **同 commit / `bfcl-eval` 版本** 的 **`data_overall.csv`** 为准。
- **优点**：更全面的能力画像
- **缺点**：复杂度高，单一数字难以概括

### 模式 10：HTTP Controller + 容器 Worker（AgentBench）
- **代表**：AgentBench（**FC** 与 **v0.2 八环境** 两套口径）
- **协议**：客户端 **`TaskClient`**：**`POST /start_sample`** 得 **`session_id`**；**`RUNNING`** 时 **`agent.inference(history)`** 再 **`POST /interact`**；异常 **`/cancel`**；全量样本后 **`calculate_overall`**：本地聚 **`SampleStatus` 比例 + history 长度**，再 **`POST /calculate_overall`** 合并 worker 的 **`custom`**
- **汇总**：**`python -m src.analysis`** 扫 **`overall.json`**，**`TaskHandler`** 按任务名前缀取 **`custom`** 内主指标；**`VALIDATION_MAP_FUNC`** 将 Completed / Context Limit 等标签映射到 **`validation` 字段**
- **部署**：经典 **`python -m src.start_task`** + **`src.assigner`**；FC 推荐 **`extra/docker-compose.yml`**（含 AgentRL Controller、Redis、Freebase 等）
- **注意**：**勿混报** FC 子集与 8 环境 test；**WebShop 内存**、**ALFWorld 泄漏**、**KG 数据路径** 影响复现

## 关键设计维度对比

| 维度 | 选项 | 说明 |
|------|------|------|
| **评估粒度** | 二值 / 连续 / 多层级 | 通过/不通过 vs F1 score vs 加权组合 |
| **自动化程度** | 全自动 / 半自动 / 人工 | GPT-4 判断算半自动 |
| **环境隔离** | 无 / Docker / 自托管 / 云端 | 复杂度和成本递增 |
| **防污染** | 无 / 时间分割 / 私有 / 加密 | 效果递增 |
| **任务复杂度** | 单步 / 多步 / 对话 / 开放 | 评估的能力层次递增 |
| **语言覆盖** | 单语言 / 多语言 | Python only → 4-6 种语言 |

## 评估方式演进趋势

1. **简单 → 真实**：算法题 → GitHub Issue → Web 任务
2. **静态 → 动态**：固定数据集 → 持续更新 → 实时环境
3. **单维 → 多维**：pass@k → resolve + retrieval + repair
4. **模型 → Agent**：纯生成 → 工具使用 → 多步推理 → 环境交互
5. **信任 → 验证**：无防污染 → 时间分割 → 元分析框架（BetterBench, ABC）
