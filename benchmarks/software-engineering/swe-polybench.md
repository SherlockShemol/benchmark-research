# SWE-PolyBench

## 基本信息

| 项目 | 内容 |
|------|------|
| 名称 | SWE-PolyBench |
| 来源 | Amazon Science |
| 论文 | [arxiv.org/html/2504.08703v3](https://arxiv.org/html/2504.08703v3) |
| GitHub | [github.com/amazon-science/SWE-PolyBench](https://github.com/amazon-science/SWE-PolyBench) |
| 排行榜 | [amazon-science.github.io/SWE-PolyBench](https://amazon-science.github.io/SWE-PolyBench/)（Full / PB500 / Verified 多表） |
| 数据集（HF） | [AmazonScience SWE-PolyBench Collections](https://huggingface.co/collections/AmazonScience/swe-polybench-67f41a0585f1ecaed5fa3aea) |
| 本地源码 | `repos/swe-polybench/`（包路径 `poly_bench_evaluation/`） |

## 评估目标

评估 AI 编码 Agent 在**多语言**仓库级任务上的能力。弥补 SWE-bench 仅覆盖 Python 的不足。

## 任务构造

### 数据来源
- 21 个仓库，覆盖 4 种语言：Java、JavaScript、TypeScript、Python
- 涵盖 bug 修复、功能添加、代码重构

### 数据规模
- **完整集 (PB)**：2,110 题
- **采样集 (PB500)**：500 题（每语言 125 题，任务分类约 40-40-20）
- **Verified 集 (PBv)**：382 题，带人工验证标注

## 评估指标

### 1. Resolve Rate（与 SWE-bench 语义一致）

`instance_level_scoring` 在能解析出 **`passed_tests` / `failed_tests`** 时：

```47:65:repos/swe-polybench/src/poly_bench_evaluation/scoring.py
    if result:
        with_logs = True
        passed_tests = result["passed_tests"]
        failed_tests = result["failed_tests"]

        passed_tests_set = set(result["passed_tests"])
        failed_tests_set = set(result["failed_tests"])

        f2p_set = set(f2p)
        p2p_set = set(p2p)

        if f2p_set.intersection(passed_tests_set) == f2p_set:
            all_f2p_passed = True

        if len(p2p_set.intersection(failed_tests_set)) == 0:
            no_p2p_failed = True

        if all_f2p_passed and no_p2p_failed:
            resolved = True
```

即 **F2P 全部出现在 passed 集合** 且 **P2P 与 failed 集合不交** → **`resolved=True`**；无日志/解析失败时保持默认 **False**。

### 2. File Retrieval（patch 级）

`instance_level_metric_scoring` 将 **gold `patch`** 与 **`model_patch`** 包装为 **`Patch`**，调用 **`file_retrieval_metrics`** 得到 **recall / precision / F1**（实现见 `metrics/patch_metrics.py`）。

### 3. Node Retrieval（Tree-Sitter，可选）

**`--node-metrics`**（代码里参数名 **`node_retrieval_metrics`**）为真时：克隆仓库到 **`base_commit`**，用 **`_get_node_metric_inputs`** 结合数据集字段 **`modified_nodes`**（及预测 patch）构造 **y_true / y_pred**，再 **`sklearn.metrics` 的 recall / precision / f1**；异常路径返回 **-1 / None / 0** 等哨兵值。

```16:78:repos/swe-polybench/src/poly_bench_evaluation/metrics/metric_scoring.py
def instance_level_metric_scoring(
    instance: PolyBenchInstance,
    repo_path: str,
    node_retrieval_metrics: bool = False,
    modified_nodes: list = None,
) -> PolyBenchRetrievalMetrics:
    ...
    file_metrics = file_retrieval_metrics(
        reference_patch=reference_patch, predicted_patch=predicted_patch
    )
    ...
    if node_retrieval_metrics:
        ...
            y_true, y_pred, num_ref_nodes, ref_nodes, pred_nodes = _get_node_metric_inputs(
                reference_patch,
                predicted_patch,
                rm,
                return_nodes=True,
                reference_nodes_full=set(modified_nodes),
            )
        ...
            node_metrics = {
                "recall": recall_score(y_true, y_pred),
                "precision": precision_score(y_true, y_pred),
                "f1": f1_score(y_true, y_pred),
            }

    return PolyBenchRetrievalMetrics(
        instance_id=instance.instance_id,
        file_retrieval_metrics=asdict(file_metrics),
        node_retrieval_metrics=node_metrics if node_retrieval_metrics else None,
        ...
    )
```

## 评估流程

### 单实例：`evaluate_instance`（`run_evaluation.py`）

1. **`REPO_TO_PARSER_CLASS`**：按 **`instance.repo`** 取 parser 类名，缺失则 **`ValueError`**（映射表在 `constants.py`，当前 **21 个仓库** 均有条目，勿与旧版 9 条笔记混淆）。

```6:28:repos/swe-polybench/src/poly_bench_evaluation/constants.py
REPO_TO_PARSER_CLASS = {
    "google/guava": "JavaGenericParser",
    "google/gson": "JavaGenericParser",
    "apache/dubbo": "JavaGenericParser",
    ...
    "huggingface/transformers": "PythonPyUnit",
    ...
    "keras-team/keras": "PythonPyUnit",
}
```

2. **仅检索指标**：`retrieval_metrics_only=True` 时只跑 **`instance_level_metric_scoring`**，结果写 **`_metrics.json`**。
3. **空 patch**：直接 **`instance_level_scoring`**（无测试日志）+ 检索指标（空 patch 时对 metrics 用 **`_get_zero_result`**）。
4. **镜像**：**本地已有 → 拉 GHCR 预构建 → 否则 clone 到 `base_commit` 后 `docker_build`（最多 3 次重试）**。
5. **容器内**：**先应用 `test_patch`，失败则记失败并仍算检索指标**；再应用 **`model_patch`**；成功则 **`docker_run(test_command, timeout)`**，**Java `JAVA_TIMEOUT=1800`，其余 `DEFAULT_TIMEOUT=1200`**。

```228:250:repos/swe-polybench/src/poly_bench_evaluation/run_evaluation.py
    logger.info(f"docker running for {instance_id}")
    run_timeout = JAVA_TIMEOUT if language.lower() == "java" else DEFAULT_TIMEOUT

    _ = docker_manager.docker_run(test_command=test_command, timeout=run_timeout)
    ...
    if hasattr(all_parsers, parser_class_name):
        parser_class = getattr(all_parsers, parser_class_name)
        log_parser = parser_class(test_content=run_logs_string)
        result = log_parser.parse()
```

6. **`instance_level_scoring(result, f2p, p2p, ...)`** → **`_result.json`**；**`instance_level_metric_scoring`** → **`_metrics.json`**。

批量入口 **`evaluate_predictions`**：读 **CSV 或 HuggingFace `split="test"`**、合并 **predictions** 列、**按语言预建 base 镜像**、**ThreadPool** 调 **`evaluate_instance`**；支持 **`skip_existing`**、**`retrieval_metrics_only`**、**`node_retrieval_metrics`**。

### Tree-Sitter 语言配置

节点类型与路径规则由 **`metrics/tree_sitter_utils.py`**、**`node_utils.py`**、**`patch_utils.py`** 等实现（Java / Python / JS / TS 保留的 AST 节点类别见源码注释与测试）。

## 防污染机制

- 人工验证子集 (PBv)
- 无显式时间分割机制

## 与 SWE-bench 的关键差异

| 维度 | SWE-bench | SWE-PolyBench |
|------|-----------|---------------|
| 语言 | 仅 Python | Java, JS, TS, Python |
| 测试解析 | 固定 pytest | 每 repo 一个 parser |
| 指标 | 仅 resolved | resolved + file/node retrieval |
| AST 节点指标 | 无 | Tree-Sitter 路径匹配 |
| 数据标注 | 无 modified_nodes | 有预标注 modified_nodes |

## 已知局限

1. 多语言 parser 维护复杂
2. Tree-Sitter 节点匹配可能因代码风格差异产生偏差
3. 尚未覆盖 Go、Rust、C++ 等语言

## 当前 SOTA

- 以 [SWE-PolyBench 官网榜单](https://amazon-science.github.io/SWE-PolyBench/) 为准，分 **Full / PB500 / Verified**；**Resolve Rate** 随子集与 Agent 管线变化极大。
- 截至页面可见提交，**Verified** 子榜前列曾出现 **Atlassian Rovo Dev（Overall Resolve 约 49% 量级）**、**PrometheusV1.2 + GPT-5（约 34% 量级）** 等；**Full** 集上强系统亦常显著低于 Verified（难度与规模不同）。**具体名次与数值以官网表格为准**。
