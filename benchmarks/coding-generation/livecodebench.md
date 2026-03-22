# LiveCodeBench

## 基本信息

| 项目 | 内容 |
|------|------|
| 名称 | LiveCodeBench |
| 来源 | ICLR 2025 |
| 论文 | [LiveCodeBench: Holistic and Contamination Free Evaluation of LLMs for Code](https://arxiv.org/abs/2403.07974) |
| GitHub | [github.com/LiveCodeBench/LiveCodeBench](https://github.com/LiveCodeBench/LiveCodeBench) |
| 项目站 / 榜单 | [livecodebench.github.io](https://livecodebench.github.io/) · [Leaderboard](https://livecodebench.github.io/leaderboard.html) |
| Kaggle | [Open Benchmarks · LiveCodeBench](https://www.kaggle.com/benchmarks/open-benchmarks/livecodebench)（社区镜像/入口之一，**以官方 GitHub + 项目站为准**） |
| 本地源码 | `repos/LiveCodeBench/` |

## 评估目标

在**持续更新**的竞赛题上，**多场景**评测代码能力，并用 **`contest_date` 时间过滤**缓解静态题库的**数据污染**；场景由 `Scenario` 枚举区分（与 `lcb_runner/runner` 路由一致）。

```4:8:repos/LiveCodeBench/lcb_runner/utils/scenarios.py
class Scenario(Enum):
    codegeneration = "codegeneration"
    selfrepair = "selfrepair"
    testoutputprediction = "testoutputprediction"
    codeexecution = "codeexecution"
```

## 任务构造

### 数据来源
- **LeetCode**、**AtCoder**、**CodeForces** 等，按比赛发布时间收录。
- 样本带 **`contest_date`**、**`platform`**、**`difficulty`**（easy/medium/hard）等元数据。

### 数据规模
- 随 **release** 递增（如 **release_v6** 量级可达 **1,055** 题、时间窗覆盖至 **2025** 年量级，以仓库/HF 发布说明为准）。

## 评估指标

### pass@k（与 HumanEval 同型无偏估计）

实现位于 **`pass_k_utils.py`**：对每题统计样本数 `n` 与「**该样本上所有用例均通过**」的计数 `c`，再对题求 `estimator(n,c,k)` 的均值；仅当 **所有题的 n ≥ k** 时才输出该 `k`。

```4:23:repos/LiveCodeBench/lcb_runner/evaluation/pass_k_utils.py
def estimate_pass_at_k(num_samples, num_correct, k):
    """Estimates pass@k of each problem and returns them in an array."""

    def estimator(n: int, c: int, k: int) -> float:
        """Calculates 1 - comb(n - c, k) / comb(n, k)."""
        if n - c < k:
            return 1.0
        return 1.0 - np.prod(1.0 - k / np.arange(n - c + 1, n + 1))
    ...
    return np.array(
        [estimator(int(n), int(c), k) for n, c in zip(num_samples_it, num_correct)]
    )
```

**Code Generation 聚合**：`compute_metrics_from_results` 将每条 generation 的逐测例结果 `gen` 转为「全通过」布尔：**`np.all(gen > 0)`**（即每个测例返回值须为 **>0** 的成功标记）。

```26:49:repos/LiveCodeBench/lcb_runner/evaluation/pass_k_utils.py
def compute_metrics_from_results(results, k_list=[1, 5]):
    ...
        for generation in res:
            gen = np.array(generation)
            all_correct.append(np.all(gen > 0))
        ...
    pass_at_k = {
        f"pass@{k}": estimate_pass_at_k(total, correct, k).mean()
        for k in ks
        if (total >= k).all()
    }
```

### 已有推理结果上的再分析：`compute_scores.py`

读取 **`eval_all` JSON**（每条含 `graded_list`、`contest_date`、`platform`、`pass@1` 等），先按日期/平台过滤，再用 **`totals`/`corrects`** 调 `estimate_pass_at_k` 打印 **Pass@1,5,…,200** 及 easy/medium/hard 拆分：

```79:92:repos/LiveCodeBench/lcb_runner/evaluation/compute_scores.py
    if args.start_date is not None:
        args.start_date = datetime.strptime(args.start_date, "%Y-%m-%d")
        results = [
            result for result in results if args.start_date <= result["contest_date"]
        ]

    if args.end_date is not None:
        args.end_date = datetime.strptime(args.end_date, "%Y-%m-%d")
        results = [
            result for result in results if result["contest_date"] <= args.end_date
        ]

    if args.platform is not None:
        results = [result for result in results if result["platform"] == args.platform]
```

```104:111:repos/LiveCodeBench/lcb_runner/evaluation/compute_scores.py
    for k in [1, 5, 10, 25, 50, 100, 150, 200]:
        print(
            f"Pass@{k} = ",
            estimate_pass_at_k(totals, corrects, k).mean(),
        )
```

（注意：`graded_list` 语义与 codegen 路径中的逐测例列表不同，用于**事后统计**；跑分应以实际使用的 pipeline 为准。）

## 四维评估（Multi-dimensional Evaluation）

| Scenario | 模块入口（概念） | 评估要点 |
|----------|------------------|----------|
| **Code Generation** | `compute_code_generation_metrics` + `run_test` | 多进程 `check_correctness` → `run_test` → `compute_metrics_from_results` |
| **Self-repair** | `prompts/self_repair` + 对应 metrics | 在失败生成上迭代修复后再测 |
| **Test Output Prediction** | `benchmarks/test_output_prediction.py` 等 | 对预测输出列表判分，常用 **pass@1 = 正确比例** |
| **Code Execution** | `compute_code_execution_metrics.py` | 对执行结果预测计算 **pass@1**（正确条数/总条数×100） |

### 代码执行核心：`run_test`

- 解析 `sample["input_output"]`：**`fn_name` 为空** → **stdin** 型；否则 **call-based**（调用 `Solution` 类方法）。
- 默认 **`timeout=6`**，`reliability_guard()` 限制危险能力；**SIGALRM** 做超时。

```428:478:repos/LiveCodeBench/lcb_runner/evaluation/testing_util.py
def run_test(sample, test=None, debug=False, timeout=6):
    ...
    signal.signal(signal.SIGALRM, timeout_handler)
    reliability_guard()
    ...
    in_outs = json.loads(sample["input_output"])
    ...
        if in_outs.get("fn_name") is None:
            which_type = CODE_TYPE.standard_input
            method_name = None
        else:
            which_type = CODE_TYPE.call_based
            method_name = in_outs["fn_name"]
    ...
        if which_type == CODE_TYPE.call_based:
            signal.alarm(timeout)
            try:
                results, metadata = grade_call_based(
                    code=test,
                    all_inputs=in_outs["inputs"],
                    all_outputs=in_outs["outputs"],
                    fn_name=method_name,
                    timeout=timeout,
                )
```

### Code Generation 进程隔离

`check_correctness` 用 **子进程** 跑 `_temp_run` → `run_test`，防止卡死；全局超时与测例数挂钩。

```29:44:repos/LiveCodeBench/lcb_runner/evaluation/compute_code_generation_metrics.py
def check_correctness(sample, generation, timeout, debug=True):
    ...
    p = multiprocessing.Process(
        target=_temp_run,
        args=(sample, generation, debug, result, metadata_list, timeout),
    )
    p.start()
    p.join(
        timeout=(timeout + 1) * len(json.loads(sample["input_output"])["inputs"]) + 5
    )
    if p.is_alive():
        p.kill()
```

## 评估流程（概览）

1. 按 `Scenario` 选择 **benchmark 与 prompt**（`lcb_runner/benchmarks/*`、`prompts/*`）。
2. **Runner**（`lcb_runner/runner/*`）拉取模型输出，必要时 **提取代码**（`extraction_utils`）。
3. **Codegen**：`codegen_metrics` → `evaluate_generations`（进程池）→ 每题多代 `check_correctness` → **`compute_metrics_from_results`**。
4. 汇总写 **`eval.json` / eval_all**；可用 **`python -m lcb_runner.evaluation.compute_scores`** 做 **日期/平台** 切片与 pass@k 再打印。

## 防污染机制

- **时间分割**：`compute_scores` 的 **`--start_date` / `--end_date`**（以及数据构建阶段同类过滤）用于只评某段 **contest_date** 之后的题，对比模型在「训练截断后」的表现。
- 论文/项目站讨论在固定题库上检测到的**疑似污染**现象；具体结论以论文与官方博客为准。

## 已知局限

1. **主要覆盖 Python** 竞赛风格，与生产工程代码有差距。
2. **维护成本**：平台规则与题面变化需跟进。
3. **指标路径多样**：`graded_list` 汇总与 `compute_metrics_from_results` 的「逐测例 >0」需结合你使用的脚本理解，避免混用口径。
4. **第三方榜单**（如聚合站）与官方 **Leaderboard** 的 **版本、时间窗、scenario** 可能不一致。

## 当前 SOTA

- **以 [livecodebench.github.io/leaderboard.html](https://livecodebench.github.io/leaderboard.html) 与论文更新为准**；第三方聚合站（如 Artificial Analysis 等）分数仅作参考，需核对 **模型版本与评测 split**。
- 公开报道中顶尖闭源/旗舰模型在 **Code Generation pass@1** 上常可达 **极高区间**（随版本快速变化，不在此写死数值）。

## 源码关键片段（索引）

| 文件 | 作用 |
|------|------|
| `lcb_runner/evaluation/pass_k_utils.py` | pass@k 估计与按题聚合 |
| `lcb_runner/evaluation/compute_code_generation_metrics.py` | 生成场景多进程评测入口 |
| `lcb_runner/evaluation/testing_util.py` | `run_test` / call-based vs stdin |
| `lcb_runner/evaluation/compute_scores.py` | 时间/平台过滤 + 多档 pass@k 打印 |
| `lcb_runner/utils/scenarios.py` | 四场景枚举 |
