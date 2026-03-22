# SWE-bench Live

## 基本信息

| 项目 | 内容 |
|------|------|
| 名称 | SWE-bench Live |
| 来源 | Microsoft（GitHub Copilot 相关团队维护） |
| 论文 | [SWE-bench Goes Live! (arXiv:2505.23419)](https://arxiv.org/abs/2505.23419) |
| GitHub | [github.com/microsoft/SWE-bench-Live](https://github.com/microsoft/SWE-bench-Live) |
| HuggingFace | [huggingface.co/swe-bench-live](https://huggingface.co/swe-bench-live)（组织页，含 `SWE-bench-Live/SWE-bench-Live` 等数据集） |
| 排行榜 | [swe-bench-live.github.io](https://swe-bench-live.github.io/)（按 Lite / Full / Verified 及多语言、Windows 等 split 展示） |
| 提交结果 | [github.com/swe-bench-live/submission](https://github.com/swe-bench-live/submission)（PR 提交流程） |
| 本地 harness 参考 | `repos/swe-bench/`（上游 [SWE-bench/SWE-bench](https://github.com/SWE-bench/SWE-bench)；评估协议与原版一致，换 HF 数据集名即可） |

## 评估目标

解决原始 SWE-bench 的**数据陈旧**与**手工扩展瓶颈**：从新近 GitHub issue 中自动构建可执行、可复现的实例，使评测更贴近「当前仓库状态」，并降低对训练语料中旧 PR 的记忆优势。

## 任务构造

### 数据来源与策展
- Issue/PR 来自真实仓库；强调 **2024 年及以后** 创建的任务，与静态 SWE-bench 时间域错开。
- **自动化策展管道**（论文中描述）：抓取 → 构建/测试环境（含后续 **RepoLaunch** 等多语言、多 OS 能力，见官网 News 与 [arXiv:2603.05026](https://arxiv.org/abs/2603.05026)）→ 验证可复现性 → 写入数据集。
- 每个实例配套 **专用 Docker（或 Windows 等）镜像**，保证评估可重放。

### 数据规模与 HF Splits（以数据集 README 为准，数字随版本变）

Hugging Face 数据集 **`SWE-bench-Live/SWE-bench-Live`** 提供多个 **split**（`datasets.load_dataset(..., split=...)`）：

| Split | 含义（官方） |
|-------|----------------|
| **`lite`** | 冻结子集，控制评测成本，利于榜单横向对比 |
| **`verified`** | 经 LLM 过滤等流程的验证子集（冻结） |
| **`full`** | 含最新收录实例，用于追新与月度增量 |
| **`test`** | 数据发布中的聚合 split（具体范围见 HF 元数据） |

字段与 SWE-bench 对齐，并含 **`test_cmds`**（运行测试的命令列表）、**`log_parser`**（日志解析器类型，如 `pytest`）、**`image_key`**（实例级 Docker 镜像键）等，便于 harness 按实例选择解析与执行方式（见 [HF README](https://huggingface.co/datasets/SWE-bench-Live/SWE-bench-Live)）。

- 初版约 **1,319** 实例 / **93** 仓库；后续曾扩至 **1,565** / **164** 仓库等里程碑（见 HF News）。
- **每月约 +50** 条高质量 issue；**`lite`/`verified` 冻结**，**`full`** 承载增量（HF 2025-09 说明）。
- 除 Python 主榜外，官网另有 **多语言、Windows** 等扩展数据集/榜单 Tab（与主 Python 集可能分属不同 HF 仓库，以组织页为准）。

## 评估指标

与 SWE-bench 家族一致，核心仍为 **Resolve Rate**（实例级二值）：

- **Fail-to-Pass (F2P)**：gold 中标记为应由失败→通过的测试，在应用模型 patch 后须全部变为通过。
- **Pass-to-Pass (P2P)**：gold 中应保持通过的测试不得失败。

仅当 **F2P 与 P2P 的「成功率」均为 1** 时，`get_resolution_status` 返回 **FULL**，并在 harness 中将该实例记为 **`resolved`**（与 SWE-bench 一致）。

## 评估流程

1. **加载数据**：`load_dataset("SWE-bench-Live/SWE-bench-Live", split="lite")`（或 `verified` / `full` / `test`，与榜单口径一致）。本仓库 **`repos/swe-bench`** 中 `load_swebench_dataset(name, split)` 对任意 HF 名走 `load_dataset` 分支（见下方引用）。
2. **准备预测**：JSONL/JSON，每条含 **`instance_id`**、**`model_patch`**（或等价 patch 字段），与 SWE-bench 预测格式一致。
3. **运行 harness**（本地 Docker 示例，参数名以当前 `swebench` 版本为准）：

```bash
python -m swebench.harness.run_evaluation \
  --dataset_name SWE-bench-Live/SWE-bench-Live \
  --split lite \
  --predictions_path path/to/preds.jsonl \
  --run_id my_live_eval_lite \
  --max_workers 4 \
  --timeout 1800
```

`run_evaluation` 会 **`get_dataset_from_preds`**：用 `dataset_name`+`split` 拉齐预测与数据、过滤已完成实例，再逐实例构建镜像、应用 `test_patch`/`model_patch`、执行实例上的 **`test_cmds`** 并用对应 **`log_parser`** 解析日志（与 SWE-bench 主流程相同）。

4. **汇总**：`resolved` 实例数 / 总实例数 → **Resolve Rate**；**按 split 分别跑/分别报**，勿混 lite 与 full。

### 与静态 SWE-bench 的关系

- **判定逻辑、镜像层级、日志解析路径与 SWE-bench 同源**；差异主要在 **任务来源、时间域、数据集更新节奏** 与 **多语言/Windows 扩展**。
- 若仅克隆了 `repos/swe-bench/`，只需安装该包并指定 Live 的 HF `dataset_name`，无需单独 fork 一套评分代码。

## 防污染机制

- **时间分割**：任务来自近年 issue，缓解对旧 SWE-bench PR 的直接记忆。
- **持续刷新**：Full split 每月增量，静态训练截断难以覆盖全部未来实例。
- **榜单公平性**：Lite / Verified 冻结，避免「只报最新子集」与历史结果不可比（官网 Aug 2025 说明）。

## 已知局限

1. **策展自动化**：规模扩大后，单测质量、 flaky test、环境构建失败率仍可能波动。
2. **跨语言复杂度**：多语言 split 依赖构建链路与解析器成熟度，不同语言可比性需结合 split 说明理解。
3. **成本**：全量 + Docker/Windows 环境与 SWE-bench 同属 **高成本** 评测档位。
4. **榜单依赖提交**：官方结果通过 PR 汇总，需区分「官方托管复现」与「自报分数」。

## 当前 SOTA

- **以 [SWE-bench-Live Leaderboard](https://swe-bench-live.github.io/) 为准**：按 split（Lite / Full / Verified、多语言、Windows 等）查看 Resolved 与提交日期；分数随社区提交变化，不在此笔记中写死具体数值。
- 2026-02 官网披露：Windows 任务上曾实验 **SWE-agent / OpenHands / Claude Code** 在 Windows 容器侧受限，团队提供 **Win-agent** 作为最小可比工具链（见官网 News）。

## 源码关键片段

**`resolved` 与 F2P/P2P 判定（与 SWE-bench 共用）**：

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

```288:291:repos/swe-bench/swebench/harness/grading.py
    report = get_eval_tests_report(eval_status_map, eval_ref, eval_type=eval_type)
    if get_resolution_status(report) == ResolvedStatus.FULL.value:
        report_map[instance_id]["resolved"] = True
```

**CLI 参数（节选：`dataset_name` / `split` / `predictions_path`）**：

```586:610:repos/swe-bench/swebench/harness/run_evaluation.py
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
    parser.add_argument(
        "-p",
        "--predictions_path",
        type=str,
        help="Path to predictions file - if 'gold', uses gold predictions",
        required=True,
    )
```

**必选 `run_id`**（用于日志与镜像命名空间隔离）：

```647:649:repos/swe-bench/swebench/harness/run_evaluation.py
    parser.add_argument(
        "-id", "--run_id", type=str, required=True, help="Run ID - identifies the run"
    )
```

**从 Hugging Face 按名称加载数据集（可指向 Live 数据集）**：

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
