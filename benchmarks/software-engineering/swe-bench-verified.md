# SWE-bench Verified

## 基本信息

| 项目 | 内容 |
|------|------|
| 名称 | SWE-bench Verified |
| 来源 | OpenAI Preparedness × Princeton NLP（SWE-bench 团队） |
| 发布说明 | [Introducing SWE-bench Verified (OpenAI)](https://openai.com/index/introducing-swe-bench-verified/) |
| 数据集（HF） | [`SWE-bench/SWE-bench_Verified`](https://huggingface.co/datasets/SWE-bench/SWE-bench_Verified)（文档中亦见 `princeton-nlp/SWE-bench_Verified` 写法，以 HF 实际集名为准） |
| 上游 Harness | [github.com/SWE-bench/SWE-bench](https://github.com/SWE-bench/SWE-bench) |
| 本地源码 | `repos/swe-bench/`（与完整 SWE-bench **共用** `swebench.harness`） |

## 评估目标

与 SWE-bench 相同：给定仓库快照与 issue 描述，评测模型能否生成 **patch**，使测试从失败变为通过且**不引入回归**。Verified 子集在数据质量上强调「工程师确认可解、表述与测试更干净」，**不**改变评分定义。

## 任务构造

### 人工验证流程
- 专业软件开发者逐个审核样本
- 确保 issue 描述**清晰、可执行**
- 确保单元测试**与问题对齐且充分**
- 剔除含糊、歧义或测试不当的实例

### 数据规模与字段
- **500** 实例（从原版 2,294 中筛出）
- 字段与主集一致；Verified 另含 `difficulty` 等扩展字段（见 `repos/swe-bench/docs/guides/datasets.md`）。

```63:69:repos/swe-bench/docs/guides/datasets.md
SWE-bench Verified also includes:

{
    # ... standard fields above ...
    "difficulty": "Difficulty level"
}
```

标准字段含 `instance_id`、`repo`、`problem_statement`、`patch`、`test_patch`、`FAIL_TO_PASS`、`PASS_TO_PASS` 等，与 SWE-bench 一致。

## 评估指标

与 SWE-bench **完全相同**：

- **Resolve Rate**：实例级 `resolved == True` 的比例
- **`resolved` 条件**：**F2P 全部通过** 且 **P2P 全部保持**（`get_resolution_status` 为 `FULL`）

## 评估流程

1. **安装**：按 [SWE-bench 文档](https://github.com/SWE-bench/SWE-bench) 安装 `swebench` 包。
2. **加载数据**：`load_dataset('SWE-bench/SWE-bench_Verified', split='test')`，或通过 CLI/`load_swebench_dataset` 传入同名 HF 数据集字符串。
3. **推理**：生成 `model_patch`（与主集相同 JSONL 预测格式）。
4. **运行 harness**：`python -m swebench.harness.run_evaluation`，指定 **`--dataset_name SWE-bench/SWE-bench_Verified`**（或文档中的 `princeton-nlp/...` 别名，以 HF 实际名为准）、**`-p predictions.jsonl`、`-id <run_id>`**；默认 **`--split test`**，单实例超时默认 **1800s**（`--timeout`）。可选 **`--modal True`** 在 **Modal** 云端跑实例（需配置凭证，见 `validate_modal_credentials` / `run_instances_modal`）。

```587:596:repos/swe-bench/swebench/harness/run_evaluation.py
    parser.add_argument(
        "-d",
        "--dataset_name",
        default="SWE-bench/SWE-bench_Lite",
        type=str,
        help="Name of dataset or path to JSON file.",
    )
    parser.add_argument(
        "-s", "--split", type=str, default="test", help="Split of the dataset"
    )
```

```673:674:repos/swe-bench/swebench/harness/run_evaluation.py
    parser.add_argument("--modal", type=str2bool, default=False, help="Run on Modal")
```

5. **单实例 Docker 闭环（与主集相同）**：`run_instance` 为每个 `instance_id` 建日志目录 → 启动容器 → 将预测写入 `patch.diff` 并尝试 **`git apply` / `patch`** 系列命令应用 → 把 **`test_spec.eval_script`** 拷入容器并执行 **`/bin/bash /eval.sh`**（带 `exec_run_with_timeout`）→ 测试输出落盘后用 **`get_eval_report`** 解析 F2P/P2P → 写 **`report.json`** 并返回 `resolved`。

```236:247:repos/swe-bench/swebench/harness/run_evaluation.py
        # Get report from test output
        logger.info(f"Grading answer for {instance_id}...")
        report = get_eval_report(
            test_spec=test_spec,
            prediction=pred,
            test_log_path=test_output_path,
            include_tests_status=True,
        )
        logger.info(
            f"report: {report}\n"
            f"Result for {instance_id}: resolved: {report[instance_id]['resolved']}"
        )
```

6. **`main()` 层**：`get_predictions_from_file` → `get_dataset_from_preds`（只保留**有预测且 patch 非空**的实例，并可跳过已存在 `report.json` 的完成项）→ `build_env_images` + `run_instances` 并行 → `make_run_report` 汇总。

与主集共用 **Docker 实例镜像 / env 镜像、`eval.sh`、按 repo 的 log parser**；Verified 与全量集的差异仅在于 **`dataset_name` 对应的 HF 子集与元数据字段**（如 `difficulty`）。

## 防污染机制

- **人工验证**：提升可解性与标注质量，**不等于**防泄漏。
- **无时间切分**：与主集一样，PR/issue 仍可能进入预训练语料 → OpenAI 等指出存在 **数据污染与分数膨胀** 风险。

## 已知局限（为何常被标为「不推荐」）

### 行业侧批评（含 OpenAI 2025 起公开表态）
1. **数据泄漏**：训练数据可能含相关 GitHub PR，模型或靠记忆而非推理。
2. **测试与任务质量**：即使用 Verified，仍可能存在边界质量问题。
3. **分数膨胀**：Resolve 率持续走高，与真实工程能力提升是否对齐存疑。

### 适用建议
- **小模型 / 消融 / 与主集对比**：仍可作为固定 500 题子集使用。
- **前沿闭源模型「唯一主榜」**：更推荐 **SWE-bench Pro**、**SWE-bench Live** 等强调防污染或私有/新数据的基准。

## 当前 SOTA

- 公开报道与部分榜单上 Verified **Resolve 率**曾达 **70%+** 量级，但伴随 **泄漏与分数膨胀** 争议；**不宜单独当作真实工程能力**。
- 请以 [SWE-bench Verified 榜](https://www.swebench.com/verified)、总入口 [swebench.com](https://www.swebench.com/) 与 **同一 `swebench` 版本 + HF 数据集 revision + 相同预测格式（及是否 Modal）** 为准；前沿对比更推荐同步关注 **SWE-bench Pro / SWE-bench Live**。

## 源码关键片段

**`resolved` 判定（与主集共用）**：

```215:232:repos/swe-bench/swebench/harness/grading.py
def get_resolution_status(report: dict[str, dict[str, Any]]) -> str:
    """
    Determine resolved status of an evaluation instance

    Criteria:
        - If fail-to-pass (Resolution) = 1 and pass-to-pass (Maintenance) = 1 -> FULL
        - If (fail-to-pass (Resolution) < 1 and > 0) and pass-to-pass (Maintenance) = 1 -> PARTIAL
        - Otherwise -> NO
    """
    f2p = compute_fail_to_pass(report)
    p2p = compute_pass_to_pass(report)

    if f2p == 1 and p2p == 1:
        return ResolvedStatus.FULL.value
    elif f2p < 1 and f2p > 0 and p2p == 1:
        return ResolvedStatus.PARTIAL.value
    else:
        return ResolvedStatus.NO.value
```

**从 HF 按名称加载（可将 `name` 换为 Verified 数据集）**：

```133:167:repos/swe-bench/swebench/harness/utils.py
def load_swebench_dataset(
    name="SWE-bench/SWE-bench", split="test", instance_ids=None
) -> list[SWEbenchInstance]:
    """
    Load SWE-bench dataset from Hugging Face Datasets or local .json/.jsonl file
    """
    # ...
        else:
            dataset = cast(Dataset, load_dataset(name, split=split))
```
