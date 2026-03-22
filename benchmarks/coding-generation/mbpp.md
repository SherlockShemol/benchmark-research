# MBPP (Mostly Basic Python Programming)

## 基本信息

| 项目 | 内容 |
|------|------|
| 名称 | MBPP |
| 来源 | Google Research（Introduced in *Program Synthesis with Large Language Models*, Austin et al.） |
| 论文 | [arXiv:2108.07732](https://arxiv.org/pdf/2108.07732.pdf)（MBPP 与评估设定见文中数据集章节） |
| 数据集 | [huggingface.co/datasets/mbpp](https://huggingface.co/datasets/mbpp)（lm-eval 任务亦用 [google-research-datasets/mbpp](https://huggingface.co/datasets/google-research-datasets/mbpp)） |
| 规模 | 974 题（常见报告使用 **test 分割约 500 题**，与 HF `split` 一致） |
| 原始发布说明 | Google Research 目录（论文配套）[github.com/google-research/google-research/tree/master/mbpp](https://github.com/google-research/google-research/tree/master/mbpp) |
| 本地源码 | **`repos/lm-evaluation-harness/`**（`lm_eval/tasks/mbpp/`）。一键浅克隆：在项目根执行 **`bash scripts/clone-benchmark-repos.sh`**（含 lm-eval 与 aider）；或手动 `git clone --depth 1 https://github.com/EleutherAI/lm-evaluation-harness.git repos/lm-evaluation-harness`。`repos/` 已在 `.gitignore`。 |

### 建议 clone / 对照的复现仓库

| 仓库 | 用途 |
|------|------|
| [EleutherAI/lm-evaluation-harness](https://github.com/EleutherAI/lm-evaluation-harness) | **`lm_eval/tasks/mbpp/`**：YAML 任务定义 + `utils.py`（HF `code_eval`、代码块提取）；默认配置为 **test split + few-shot + pass@1 风格指标** |
| [bigcode-project/bigcode-evaluation-harness](https://github.com/bigcode-project/bigcode-evaluation-harness) | 含 MBPP 等代码任务，常与 BigCode 论文设定对齐 |
| [google-research/google-research/.../mbpp](https://github.com/google-research/google-research/tree/master/mbpp) | 论文与数据说明（未必含与当今模型生态一致的统一 harness） |

**说明**：MBPP **无**像 `human-eval` 那样单一、小而全的官方执行仓；社区分数差异常来自：**展示给模型的 assert 条数**、**代码提取规则**、**是否 few-shot**、**单样本还是多采样 pass@k**、**超时与沙箱**。lm-eval 上关于多样本 pass@k 的讨论见 [Issue #2864](https://github.com/EleutherAI/lm-evaluation-harness/issues/2864)。

### EleutherAI lm-eval 中的默认 MBPP 任务（对照实现）

任务文件 **`lm_eval/tasks/mbpp/mbpp.yaml`**（`main` 分支）要点：

- **`dataset_path` / `dataset_name`**：`google-research-datasets/mbpp`、`full`；**`test_split: test`**。
- **Prompt**：`doc_to_text` 将 **`test_list[0]`～`test_list[2]` 三条断言写进题干**（与「最多展示 3 条」的常见设定一致），并以 `[BEGIN]` 结尾引导生成。
- **解码**：`generate_until` + `until: ["[DONE]"]`，**`do_sample: false`**（默认贪心式单样本，而非 pass@10 的多采样）。
- **指标**：`metric_list` 使用 **`utils.pass_at_1`**，再对题目做 **`aggregation: mean`** —— 即框架内的 **pass@1 均值**，底层走 HuggingFace **`evaluate.load("code_eval")`**，与 Chen et al. 在 **n>1 样本上的无偏 pass@k 估计**不是同一配置；若要报告 pass@10 等，需改 generation 与 metric 配置并保证 n≥k。

**代码提取**（`utils.extract_code_blocks`）：用正则取 fenced code block；实现上先把模型输出前补上 **「\`\`\`」** 再匹配，以配合 `gen_prefix` 里已加的 `` ```python `` 前缀（见源码注释）。

克隆 **`repos/lm-evaluation-harness`** 后可在本地打开下列路径（与 [GitHub `main`](https://github.com/EleutherAI/lm-evaluation-harness/tree/main/lm_eval/tasks/mbpp) 行号一致）。

**模块加载时探测 `code_eval`**（若沙箱未开代码执行，import 阶段即失败）：

```9:18:repos/lm-evaluation-harness/lm_eval/tasks/mbpp/utils.py
try:
    pass_at_k = hf_evaluate.load("code_eval")
    test_cases = ["assert add(2, 3)==5"]
    candidates = [["def add(a,b): return a*b"]]
    results = pass_at_k.compute(references=test_cases, predictions=candidates, k=[1])
except Exception as e:
    raise e
```

**默认指标 `pass_at_1`**：把单条或批量的 `predictions` 规整成 `list[list[str]]`，调用同一 `pass_at_k.compute(..., k=[1])`，取 **`["pass@1"]`**。

```20:33:repos/lm-evaluation-harness/lm_eval/tasks/mbpp/utils.py
def pass_at_1(
    references: Union[str, list[str]], predictions: Union[str, list[list[str]]]
) -> float:
    if isinstance(references, str):
        references = [references]
    if isinstance(predictions[0], str):
        predictions = [[p] for p in predictions]
    return pass_at_k.compute(
        references=references,
        predictions=predictions,
        k=[1],
    )[0]["pass@1"]
```

**`build_predictions`**：对每条模型原始输出先 **`extract_code_blocks`** 再交给 `code_eval`。

```55:57:repos/lm-evaluation-harness/lm_eval/tasks/mbpp/utils.py
def build_predictions(resps: list[list[str]], docs: list[dict]) -> list[list[str]]:
    return [[extract_code_blocks(r) for r in resp] for resp in resps]
```

**`extract_code_blocks`**：正则匹配 fenced block；先将输出与前缀 `` ``` `` 拼接以配合 `gen_prefix` 中的 `` ```python ``；若无匹配再去掉 `` ```python `` 重试。完整字面量见同文件（笔记正文避免嵌套三反引号以免破坏 Markdown）。

```1:18:repos/lm-evaluation-harness/lm_eval/tasks/mbpp/mbpp.yaml
task: mbpp
dataset_path: google-research-datasets/mbpp
dataset_name: full
unsafe_code: true
output_type: generate_until
test_split: test
doc_to_text: "You are an expert Python programmer, and here is your task: {{text}} Your code should pass these tests:\n\n{{test_list[0]}}\n{{test_list[1]}}\n{{test_list[2]}}\n[BEGIN]\n"
...
metric_list:
  - metric: !function utils.pass_at_1
    aggregation: mean
```

同目录另有 **`mbpp_instruct.yaml`**、**`mbpp_plus.yaml`**。其中 **`mbpp_plus`** 继承 `mbpp.yaml` 的指标与解码设置，但数据改为 **`evalplus/mbppplus`**（EvalPlus 系增强/去污染 MBPP），`doc_to_text` 优先用字段 **`prompt`**（若存在）否则回退 **`text`**：

```1:7:repos/lm-evaluation-harness/lm_eval/tasks/mbpp/mbpp_plus.yaml
include: mbpp.yaml
task: mbpp_plus
dataset_path: evalplus/mbppplus
dataset_name: null
doc_to_text: "You are an expert Python programmer, and here is your task: {{prompt if prompt is defined else text}} Your code should pass these tests:\n\n{{test_list[0]}}\n{{test_list[1]}}\n{{test_list[2]}}\n[BEGIN]\n"
```

更多说明见 [tasks/mbpp/README.md](https://github.com/EleutherAI/lm-evaluation-harness/blob/main/lm_eval/tasks/mbpp/README.md)。

## 评估目标

评估 LLM 解决**入门级 Python 编程**问题的能力。与 HumanEval 相比，MBPP 的问题更偏向基础编程概念，设计为新手程序员可解决的水平。

## 任务构造

### 数据来源
- 974 个**众包**的 Python 编程问题
- 覆盖字符串操作、列表操作、数学计算、基础数据结构等

### 数据集划分
- Train：374 题
- Test：500 题
- Validation：90 题
- Prompt：10 题（few-shot 示例）

### 每个问题包含
- `task_id`：数字标识
- `text`：自然语言问题描述
- `code`：参考答案
- `test_list`：基于 assertion 的测试用例（常见设定下**最多 3 条展示给模型**，完整列表用于判分）

## 评估指标

### 核心指标：pass@k

与本仓库中 **HumanEval**、**LiveCodeBench** 一致，均采用 Chen et al. 的**无偏估计**；实现可参考 `repos/human-eval/human_eval/evaluation.py` 或 **`repos/LiveCodeBench/lcb_runner/evaluation/pass_k_utils.py`** 中的 `estimator(n,c,k)`（同一公式）。

**定义**：对每道题独立采样 **n** 个程序，其中 **c** 个能在隐藏测试上全部通过，则该题在选取 k 个样本时至少一次成功的概率为：

\[
\text{pass@}k = 1 - \frac{\binom{n-c}{k}}{\binom{n}{k}}
\]

（与 HumanEval / Codex 论文一致的无偏估计；需 **n ≥ k**。）

实践中常同时报告 **pass@1**（或单次采样准确率）与 **pass@10 / pass@100**。

## 评估流程

典型自动评测管道（各框架实现等价思路，细节以所用仓库为准）：

1. **解析**：从模型输出中提取 Python 函数或完整可执行片段（正则 / AST / 启发式）。
2. **组装**：将模型代码与数据集中的 **全部** `test_list` 断言拼接为单一脚本，并在末尾加入成功标记（常见模式为执行通过后 `print('ALL_TESTS_PASSED')` 类语句）。
3. **执行**：在隔离环境（Docker 或沙箱子进程）中运行 **Python 3**，设 **30–60s** 级超时以防死循环。
4. **判定**：进程退出码为 0 且成功标记出现 → 该样本「通过」；再对多样本聚合计算 pass@k。

**与 lm-eval 默认 MBPP 对齐时**：以 `mbpp.yaml` 为准检查 **`doc_to_text` 是否注入三条 assert**、**`num_fewshot: 3`**、**`utils.pass_at_1` + `code_eval`**；写论文若声称「HumanEval 同款 pass@k」，需单独配置 **n 次采样** 并调用与 **`repos/human-eval`** / **`repos/LiveCodeBench`** 一致的 **无偏估计**实现，而不是默认 YAML 的 pass@1 均值。

### 与 HumanEval 的区别

| 维度 | HumanEval | MBPP |
|------|-----------|------|
| 来源 | 专家手工设计 | 众包 |
| 难度 | 中等算法 | 入门级 |
| 问题描述 | 函数签名 + docstring | 自然语言描述 |
| 测试用例 | 隐藏在评估脚本中 | 部分展示给模型 |
| 规模 | 164 | 974 |

## 防污染机制

- **无**。数据与标注公开且固定，无时间切分；与 LiveCodeBench 等动态基准相比更易被训练语料覆盖。

## 已知局限

1. **严重饱和**：公开测试集上前沿模型 pass@1 常报 **90%+**，区分度不足。
2. **仅 Python**：不覆盖多语言或仓库级任务。
3. **难度偏低**：以基础 API 与短程序为主，不反映系统工程能力。
4. **测试覆盖有限**：每题断言数量少，易过拟合到表面模式。
5. **复现方差**：代码提取、超时、是否 few-shot、是否只评 test split 均会影响横向可比性；写论文时应**固定评测框架与 commit**。

## 当前 SOTA

- MBPP **高度饱和**：各聚合榜/模型卡上 **pass@1（test split）** 常见落在 **约 88%～91%+** 区间，**具体模型名与分数需对照同一数据集 split 与评测脚本**（例如是否 lm-eval 默认 `mbpp`、是否 Plus 子集）。
- 可参考 [Hugging Face Open LLM Leaderboard](https://huggingface.co/spaces/HuggingFaceH4/open_llm_leaderboard) 等含 MBPP 列的榜单；第三方汇总站分数差异大，**不宜**跨站直接排名而不读脚注。
- Austin et al. (2021) 文中基线远低于当今模型，仅作历史参考；与当前 SOTA 对比必须说明 **prompt、few-shot、split、harness**。
