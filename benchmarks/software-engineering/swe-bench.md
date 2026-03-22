# SWE-bench

## 基本信息

| 项目 | 内容 |
|------|------|
| 名称 | SWE-bench |
| 来源 | Princeton NLP / Carlos E. Jimenez et al. |
| 论文 | [arxiv.org/abs/2310.06770](https://arxiv.org/abs/2310.06770) · [OpenReview](https://openreview.net/forum?id=VTF8yNQM66) |
| GitHub | [github.com/SWE-bench/SWE-bench](https://github.com/SWE-bench/SWE-bench) |
| 文档与榜单 | [Read the Docs（SWE-bench）](https://www.swebench.com/SWE-bench/) · [总榜入口 swebench.com](https://www.swebench.com/) · [Results Viewer](https://www.swebench.com/viewer.html) |
| 数据集（HF） | **全量 test**：`princeton-nlp/SWE-bench`（README 示例 `load_dataset(..., split="test")`）；**Lite**（harness 默认）：`SWE-bench/SWE-bench_Lite`（与 `run_evaluation.py` 的 **`--dataset_name` 默认**一致） |
| 本地源码 | `repos/swe-bench/` |

## 评估目标

评估 LLM/AI Agent 在**真实软件工程场景**中解决 GitHub Issue 的能力。给定一个代码库快照和自然语言 issue 描述，模型需要生成能解决问题的代码补丁（patch）。

## 任务构造

### 数据来源
- 12 个流行 Python 开源仓库的 GitHub PR
- 每个 PR 必须已合并且关联公开 issue

### 三阶段过滤管道

1. **Execution-based Filtering**：补丁回放确保测试从 fail 转为 pass，无回归
2. **Attribute-based Filtering**：仅保留已合并且关联公开 issue 的 PR
3. **Repository Selection**：选取广泛使用、测试良好的 Python 包

### 任务构建流程（`collect/build_dataset.py`）

```
PR JSONL → create_instance() → 提取 patch, test_patch, problem_statement
  → is_valid_pull(): 已 merge + 有 resolved issues
  → is_valid_instance(): 有 patch + problem_statement
  → has_test_patch(): 有测试补丁才写入评估集
```

### 数据规模
- **完整集**：2,294 题
- **Lite**：300 题（按 patch 复杂度过滤：≤1 文件、1-3 hunks）
- 平均每实例：~3,010 非测试文件、~438,000 LOC
- Gold patch 平均：1.7 文件、3 函数、~32.8 行

### 与同仓库其它基准的关系（勿混报）

- **SWE-bench Multimodal**（[数据集](https://huggingface.co/datasets/SWE-bench/SWE-bench_Multimodal)、[论文](https://arxiv.org/abs/2410.03859)）：视觉相关 issue；**test 答案不公开**，提交走 **[sb-cli](https://github.com/swe-bench/sb-cli)** 云评，与经典 2,294 题 **不是同一榜单行**。
- **Harness 多语言**：`swebench.harness.log_parsers` 含 Java/JS/Go 等解析器，供 **SWE-bench Live、多语言扩展** 等数据集使用；**ICLR 2024 主论文 test 集**仍描述为 **Python 开源仓库** 上的 issue 修复。

## 评估指标

### 核心指标：Resolve Rate

**思路**：对日志解析得到 **`eval_status_map`（测例名 → PASSED/FAILED/…）**，与实例元数据中的 **`FAIL_TO_PASS` / `PASS_TO_PASS`** 列表对照，得到每类测例的 **success/failure 列表**，再算比率。

- **`compute_fail_to_pass`**：**F2P 成功数 / (成功+失败)**；若列表为空则返回 **1**。
- **`compute_pass_to_pass`**：**P2P 成功数 / (成功+失败)**；若列表为空则返回 **1**（代码注释称未来可能不纳入 P2P）。
- **`test_passed`**：测例状态为 **`PASSED` 或 `XFAIL`** 视为通过。

```194:232:repos/swe-bench/swebench/harness/grading.py
def compute_fail_to_pass(report: dict[str, dict[str, Any]]) -> float:
    total = len(report[FAIL_TO_PASS]["success"]) + len(report[FAIL_TO_PASS]["failure"])
    if total == 0:
        return 1
    return len(report[FAIL_TO_PASS]["success"]) / total


def compute_pass_to_pass(report: dict[str, dict[str, Any]]) -> float:
    total = len(report[PASS_TO_PASS]["success"]) + len(report[PASS_TO_PASS]["failure"])
    if total == 0:
        return 1
    return len(report[PASS_TO_PASS]["success"]) / total


def get_resolution_status(report: dict[str, dict[str, Any]]) -> str:
    f2p = compute_fail_to_pass(report)
    p2p = compute_pass_to_pass(report)

    if f2p == 1 and p2p == 1:
        return ResolvedStatus.FULL.value
    elif f2p < 1 and f2p > 0 and p2p == 1:
        return ResolvedStatus.PARTIAL.value
    else:
        return ResolvedStatus.NO.value
```

**`resolved` 标志**：仅当 **`get_resolution_status(report) == FULL`** 时 **`report_map[instance_id]["resolved"] = True`**（**PARTIAL 不算 resolved**）。

```288:290:repos/swe-bench/swebench/harness/grading.py
    report = get_eval_tests_report(eval_status_map, eval_ref, eval_type=eval_type)
    if get_resolution_status(report) == ResolvedStatus.FULL.value:
        report_map[instance_id]["resolved"] = True
```

**仓库特例**：若 **`test_spec.repo` 属于 `FAIL_ONLY_REPOS`**，则 **`get_eval_tests_report`** 使用 **`EvalType.FAIL_ONLY`**：对 F2P/P2P 测例只把「仍为 **FAILED**」算作 failure，其余算 success（与默认 **PASS_AND_FAIL** 的判定分支不同）。

**Resolve Rate = `resolved==True` 的实例数 / 总评估实例数**（与社区「strict resolved」口径一致）。

### 辅助分类
- **FAIL_TO_FAIL (F2F)**：始终失败的测试（Extra Credit）
- **PASS_TO_FAIL (P2F)**：不应考虑的测试

## 评估流程

### 安装与最小自检

```bash
pip install -e repos/swe-bench   # 或在上游仓根目录
python -m swebench.harness.run_evaluation \
  --predictions_path gold \
  --max_workers 1 \
  --instance_ids sympy__sympy-20590 \
  --run_id validate-gold
```

- **ARM / Apple Silicon**：上游 README 建议加 **`--namespace ''`**；当前 harness argparse 说明可用 **`--namespace none`** 表示**无前缀**镜像命名空间，以触发/配合**本地构建**（与默认从 Docker Hub 拉 **linux/amd64** 预构建镜像相对）。以你安装的 **`swebench` 版本帮助文案**为准。
- **`--predictions_path gold`**：用数据集中 gold patch 跑通流水线，用于环境自检。

### 全量（或 Lite）评测 CLI 骨架

```bash
python -m swebench.harness.run_evaluation \
  --dataset_name princeton-nlp/SWE-bench \
  --split test \
  --predictions_path path/to/preds.jsonl \
  --run_id my_run \
  --max_workers 4 \
  --timeout 1800
```

- **`-id` / `--run_id`**：**必填**，用于 **`logs/run_evaluation/{run_id}/...`** 下按实例落盘与最终汇总隔离。
- **`-d` / `--dataset_name`**：也可指向本地 **JSON/JSONL**；默认 **`SWE-bench/SWE-bench_Lite`** 时勿与 Full 榜单混报。
- **`-i` / `--instance_ids`**：仅跑子集调试。
- **`--modal True`**：在 **Modal** 云端跑（需凭证），与本地 Docker 二选一。
- **`--rewrite_reports True`**：不重跑容器，仅根据已有 **`test_output.txt`** 重算/补写报告（见 argparse 说明）。
- **收尾**：`main()` 末尾调用 **`make_run_report`**，在**当前工作目录**写出 **`{model_safe}.{run_id}.json`**（`KEY_MODEL` 来自预测文件），内含 **`resolved_instances`**、各 ID 列表等（`reporting.py`）。

### Docker 三层镜像架构

```
Instance Image (每个 instance 一个)
    └── Env Image (每个 repo+version 一个)
            └── Base Image (每种语言一个)
```

### 五步评估流程（`run_instance` 对齐）

1. **镜像/容器**：`build_container` 启动实例容器（镜像通常预构建）。
2. **写入 patch**：`patch.diff` 拷入容器 **`DOCKER_PATCH`**。
3. **打补丁**：在容器内依次尝试 **`GIT_APPLY_CMDS`**（与仓库一致）：

```64:68:repos/swe-bench/swebench/harness/run_evaluation.py
GIT_APPLY_CMDS = [
    "git apply --verbose",
    "git apply --verbose --reject",
    "patch --batch --fuzz=5 -p1 -i",
]
```

4. **跑测**：将 **`test_spec.eval_script`** 写入 **`/eval.sh`**，`exec_run_with_timeout(container, "/bin/bash /eval.sh", timeout)`，完整输出写入 **`test_output.txt`**（常量 `LOG_TEST_OUTPUT`）。**Live 等数据集**可在实例元数据中带 **`test_cmds` + `log_parser`**，由同一 harness 路由（与经典 Python 仓库的 **`MAP_REPO_TO_PARSER`** 路径并存）。
5. **评分与落盘**：**`get_eval_report`** → **`report.json`**；返回 **`{"completed", "resolved"}`**。

### Eval 脚本与日志标记（概念）

`eval.sh` 由 **`TestSpec`** 生成，典型模式包括：恢复测试文件、**`git apply` test patch**、在 **`START_TEST_OUTPUT` / `END_TEST_OUTPUT`** 标记之间执行 **`test_cmd`**。具体命令随 **`MAP_REPO_VERSION_TO_SPECS`** 中各仓库版本而定。

### 日志解析（`get_logs_eval`）

- 若日志含 **`APPLY_PATCH_FAIL` / `RESET_FAILED` / `TESTS_ERROR` / `TESTS_TIMEOUT`** 等坏码，或缺少起止标记 → 返回 **`({}, False)`**，后续 **`resolved` 保持默认**。
- 否则截取两标记之间文本，用 **`MAP_REPO_TO_PARSER[repo]`** 解析为 **`status_map`**。
- **回退**：若标记间解析为空（如 pytest 输出落到 stderr），再对**整份日志**调用同一 parser（见 `grading.py` 约 84–89 行）。

## 防污染机制

- 原始数据基于公开 GitHub PR，**无时间分割**
- 后续变体（Verified, Pro, Live）引入了更强的防污染措施
- OpenAI 发现 SWE-bench Verified 存在训练数据泄漏问题

## 已知局限

1. **主论文 test 集语言域**：以 **Python 仓库**为主；harness 后续为多数据集扩展了解析与镜像，但 **Full 2,294 的跨语言可比性**不等于「全栈多语言 issue 榜」。
2. **数据污染**：训练数据可能包含相关 PR；对比应优先结合 **Verified / Pro / Live** 等设计。
3. **测试依赖**：评估质量取决于测试覆盖率；flaky test 会导致噪声。
4. **Issue 质量不一**：有些 issue 描述不够清晰。
5. **单一评估指标**：Resolve Rate 不反映代码质量、可读性或安全性。
6. **成本**：Docker 镜像与并行 worker 对磁盘/CPU 要求高（常见建议 **~120GB 磁盘、16GB+ RAM、多核**）。

## 当前 SOTA 及人类基线

- **Resolve 数字以 [swebench.com](https://www.swebench.com/) 所选 Tab（Full / Lite / Verified 等）实时榜为准**，勿与论文初版表格或未注明 `dataset_name`/`split` 的二手转载混比。
- **人类基线**：论文讨论中常引用较高区间，但**非统一公开 harness 分数**；工程上更常用模型间相对排序。
- **高分与泄漏争议**：Verified 等子集在产业界有「分数膨胀」讨论，前沿对比建议**并列 Pro、Live**。
