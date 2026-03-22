# ToolBench

## 基本信息

| 项目 | 内容 |
|------|------|
| 名称 | ToolBench / ToolLLM |
| 来源 | OpenBMB |
| 论文 | [arxiv.org/abs/2307.16789](https://arxiv.org/abs/2307.16789) |
| GitHub | [github.com/OpenBMB/ToolBench](https://github.com/OpenBMB/ToolBench) |
| ToolEval 代码 | 仓库内 `toolbench/tooleval/` |
| 本地源码 | `repos/ToolBench/` |
| 排行榜 | [openbmb.github.io/ToolBench](https://openbmb.github.io/ToolBench/) · [Hugging Face Space（社区榜）](https://huggingface.co/spaces/qiantong-xu/toolbench-leaderboard) |

## 评估目标

在**大规模真实 RapidAPI 工具空间**上，评测模型是否能够：根据用户指令与可见 API 说明进行规划、发起合法调用、并最终给出可验证的完成态答案。数据集同时用于训练（如 ToolLLaMA），评估侧重**整条工具调用轨迹**而非单次函数名匹配。

## 任务构造

- **API 规模**：README 标注约 **16,464** 个 REST API、**3,451** 个工具类别、约 **126K** 条级对话/路径数据（版本随数据发布更新）。
- **指令类型**：单工具与多工具场景；答案标注含 **DFSDT**（深度优先搜索决策树）等推理与执行轨迹。
- **执行环境**：默认与 **RapidAPI** 生态对接；官方提供后端 key 申请方式。另有 **StableToolBench**（响应模拟、可本地部署）用于更稳定复现，见 [StableToolBench](https://github.com/zhichengg/StableToolBench) 与论文 [arXiv:2403.07714](https://arxiv.org/pdf/2403.07714.pdf)。

## 评估指标

### ToolEval：Pass Rate

- **含义**：在限定评测器调用成本下，模型轨迹被自动判定为「通过」的指令占比。
- **单次 `compute_pass_rate`**：先 **`check_has_hallucination`**（异常则默认不判幻觉）；解析 **`get_steps`**；若 **`final_step`** 中**不含**子串 **`'name': 'Finish'`** → 直接记 **failed**。否则依次 **`check_is_solved`**、**`check_task_solvable`**、**`is_passed`**；`is_passed` 为 **Unsure** 时 **0.5 随机** 为 passed/failed。

```54:112:repos/ToolBench/toolbench/tooleval/eval_pass_rate.py
        if "'name': 'Finish'" not in final_step:
            return query_id, TaskStatus.Solvable, AnswerStatus.Unsolved, "failed", "No answer", not_hallucinate
        ...
        is_passed = evaluator.is_passed(
            ...
        )
        ...
        else:
            if random.random() < 0.5: # if unsure, random choose
                label = "passed"
            else:
                label = "failed"
        return query_id, task_solvable, is_solved, label, reason, not_hallucinate
```

- **多轮采样**：对每个 `query_id` 跑 **`evaluate_times`** 次（线程池并发），累计 **`label_cnt[query_id]["passed"/"failed"]`**。
- **⚠️ 两种聚合不一致**：
  - **写 TSV 的 `write_results`**：按 **passed > failed** 决定 `final_label`，**平局随机**。
  - **打印的总 Pass rate**：**`failed <= passed` 即该 query 计 1**（**平局算通过**），再除以 query 数。

```169:176:repos/ToolBench/toolbench/tooleval/eval_pass_rate.py
        pass_rate = 0
        for query_id in label_cnt:
            if label_cnt[query_id]["failed"] <= label_cnt[query_id]["passed"]:
                pass_rate += 1
        pass_rate /= len(label_cnt)
        print(f"Test set: {test_set}. Model: {reference_model}. Pass rate: {str(pass_rate)}")
```

论文/报告需说明引用的是 **控制台 pass_rate** 还是 **TSV 列 `pass_rate_label`**。

### ToolEval：Win Rate（偏好对比）

- **含义**：对同一指令的两条解答轨迹，由评测模型（如 GPT 系列）按模板做**成对偏好**标注；用于模型间相对排序（`eval_preference.py` 等脚本）。

### 辅助维度

- **幻觉检测**：`check_has_hallucination` 等，标记调用是否越出可用工具集合（实现随评测器配置而定）。

## 评估流程

### Pass rate：`eval_pass_rate.py` 入口

- **必填/常用参数**：**`--converted_answer_path`**（按 **`{reference_model}/{test_set}.json`** 组织）、**`--test_ids`**（每 split 一个 **`{test_set}.json`**，键为允许的 `query_id`）、**`--save_path`**；**`--reference_model`** 用于命名输出；**`--evaluator`** 默认 **`tooleval_gpt-3.5-turbo_default`**；**`--max_eval_threads`**（默认 30）、**`--evaluate_times`**（默认 **4**，即每题用评测器独立判 **4** 次，累加到 `passed`/`failed` 计数）。
- **评测器实例**：启动时 **`load_registered_automatic_evaluator`** 加载 **`evaluators/`** 下 YAML 配置，线程池内 **`random.choice(evaluators)`** 分摊请求。

```14:23:repos/ToolBench/toolbench/tooleval/eval_pass_rate.py
def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('--converted_answer_path', type=str, default="", required=True, help='converted answer path')
    ...
    parser.add_argument('--evaluate_times', type=int, default=4, required=False, help='how many times to predict with the evaluator for each solution path.')
    return parser.parse_args()
```

- **外层循环**：对 **`utils.test_sets`** 中每个 **`test_set`** 读入参考预测，按 **`test_ids` 过滤**；对每个 **`query_id` × `evaluate_times`** 提交 **`compute_pass_rate`**；**每完成一条 future 就整表 `json.dump` 到 `{save_path}/{test_set}_{reference_model}.json`**（可断点续跑，跳过 `existed_ids`），最后写 **TSV** 并打印 **控制台 pass rate**。

```117:176:repos/ToolBench/toolbench/tooleval/eval_pass_rate.py
    for test_set in test_sets:
        reference_path = f"{args.converted_answer_path}/{reference_model}/{test_set}.json"
        test_ids = list(json.load(open(os.path.join(args.test_ids, test_set+".json"), "r")).keys())
        ...
                for i in range(args.evaluate_times):
                    ...
                    future.append(pool.submit(
                        compute_pass_rate,
                        query_id,
                        example
                    ))
        ...
        write_results(filename, reference_model, label_cnt)
        pass_rate = 0
        for query_id in label_cnt:
            if label_cnt[query_id]["failed"] <= label_cnt[query_id]["passed"]:
                pass_rate += 1
        pass_rate /= len(label_cnt)
        print(f"Test set: {test_set}. Model: {reference_model}. Pass rate: {str(pass_rate)}")
```

### 其他脚本

1. **准备模型输出**：将模型在测试集上的解答转为 ToolEval 所需的 **`converted_answer`** 格式（含 **`query`**、**`available_tools`**、**`answer`** 等）；完整流水线见仓库 **`tooleval/README.md`**。
2. **Preference / Win rate**：**`eval_preference.py`**、**`automatic_eval_sample.py`**（对接 **`eval_server_address`** 生成轨迹再与参考答案比偏好）等。
3. **榜单聚合**：**`eval_and_update_leaderboard.py`** 等用于合并 CSV/刷新展示（以仓库说明为准）。

## 防污染机制

- **无严格时间切分**：测试集与训练数据同源生态，存在泄漏与过拟合风险；需结合 held-out 划分与独立复现（如 StableToolBench）理解分数。
- **Live API**：真实 RapidAPI 随时间变化，旧轨迹可能无法重放；StableToolBench 旨在缓解此问题。

## 已知局限

1. **评测依赖强 LLM**：Pass/求解判定大量依赖 GPT 类等评测器，存在偏差与成本。
2. **API 可用性**：密钥、配额、接口变更影响可重复性。
3. **判定粒度**：偏好与「是否解决」部分依赖自然语言理由，难以做到像单元测试那样的客观唯一性。
4. **数据自动化构造**：指令与标注来自流水线生成，噪声会传导到评测。
5. **Pass rate 口径**：**`write_results` 的 `pass_rate_label`** 与 **脚本末尾打印的 `pass_rate`** 在 **passed==failed** 时不一致（后者计为通过），写论文需声明复现的是哪一列/哪一输出。

## 当前 SOTA

- 排行以 **[OpenBMB ToolEval Leaderboard](https://openbmb.github.io/ToolBench/)** 与 **[Hugging Face Space（社区提交榜）](https://huggingface.co/spaces/qiantong-xu/toolbench-leaderboard)** 为准；具体名次与 Pass/Win 数字随**评测器型号、API 版本与提交数据**变化，不宜在笔记里写死单一百分比。
- 官方页面说明：用 ChatGPT 类评测器在 **300** 条指令子集上与人工对比，**Pass rate 一致率约 87.1%**、**Win rate 约 80.3%**（见 [ToolEval Leaderboard 页](https://openbmb.github.io/ToolBench/) 的 *About ToolEval*）；**线上复现时评测器与 RapidAPI 环境变更**会使历史论文表与当前榜不可直接等同。

## 源码关键片段

**`compute_pass_rate` 全函数**：见上文 **「ToolEval：Pass Rate」** 引用（含 **Finish** 门闩与 **Unsure** 随机）。

**TSV 行标签（多数决 + 平局随机）与控制台 pass rate（平局计通过）**：

```25:47:repos/ToolBench/toolbench/tooleval/eval_pass_rate.py
def write_results(filename: str, reference_model: str, label_cnt: dict) -> None:
    with open(filename, 'w', newline='') as file:
        writer = csv.writer(file, delimiter="\t")
        writer.writerow(["query", "solvable", "available_tools", "model_intermediate_steps", "model_final_step", "model", "query_id", "is_solved", "pass_rate_label", "reason", "not_hallucinate"])
        for query_id in label_cnt:
            if label_cnt[query_id]["passed"] > label_cnt[query_id]["failed"]:
                final_label = "passed"
            elif label_cnt[query_id]["passed"] < label_cnt[query_id]["failed"]:
                final_label = "failed"
            else:
                if random.random() < 0.5: # if tie, random choose
                    final_label = "passed"
                else:
                    final_label = "failed"
```

```169:176:repos/ToolBench/toolbench/tooleval/eval_pass_rate.py
        pass_rate = 0
        for query_id in label_cnt:
            if label_cnt[query_id]["failed"] <= label_cnt[query_id]["passed"]:
                pass_rate += 1
        pass_rate /= len(label_cnt)
        print(f"Test set: {test_set}. Model: {reference_model}. Pass rate: {str(pass_rate)}")
```
