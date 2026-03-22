# BFCL (Berkeley Function Calling Leaderboard)

## 基本信息

| 项目 | 内容 |
|------|------|
| 名称 | BFCL (Berkeley Function Calling Leaderboard) |
| 来源 | UC Berkeley / Gorilla 项目 |
| 论文 | [openreview.net/pdf?id=2GmDdhBdDk](https://openreview.net/pdf?id=2GmDdhBdDk) |
| GitHub | [github.com/ShishirPatil/gorilla](https://github.com/ShishirPatil/gorilla/tree/main/berkeley-function-call-leaderboard) |
| 排行榜 | [BFCL V4 Leaderboard](https://gorilla.cs.berkeley.edu/leaderboard.html)（页面注明 **Last Updated**、固定评测 **commit** 与 **`bfcl-eval` PyPI 版本**，复现应对齐） |
| 本地源码 | `repos/gorilla/berkeley-function-call-leaderboard/`（即 Gorilla 仓内 **`berkeley-function-call-leaderboard/`**） |

## 评估目标

全面评估 LLM 的**函数调用（tool use）**能力，覆盖从简单单函数到复杂多轮 Agent 场景。

## 任务构造

### 五大评估维度（加权评分）

| 维度 | 权重 | 子分类 |
|------|------|--------|
| **Non-Live** | 10% | simple_python, simple_java, simple_javascript, multiple, parallel, parallel_multiple, irrelevance |
| **Live** | 10% | live_simple, live_multiple, live_parallel, live_parallel_multiple, live_irrelevance, live_relevance |
| **Irrelevance** | 10% | non_live + live 的 irrelevance 合并 |
| **Multi-Turn** | 30% | base, miss_func, miss_param, long_context |
| **Agentic** | 40% | web_search_base, web_search_no_snippet, memory_kv, memory_vector, memory_rec_sum |

### 六类单轮场景

1. **Simple**：单函数调用（Python/Java/JavaScript）
2. **Multiple**：顺序多次调用
3. **Parallel**：并行多次调用
4. **Parallel Multiple**：并行+顺序混合
5. **Irrelevance**：不应产生函数调用
6. **Relevance**：应产生函数调用

## 评估指标

### 总体加权准确率（`data_overall.csv`）

**`eval_runner_helper.py`** 对五大桶 **`overall_accuracy_non_live` / `overall_accuracy_live` / `total_irrelevance` / `overall_accuracy_multi_turn` / `overall_accuracy_agentic`** 使用权重 **`[10, 10, 10, 30, 40]`**，经 **`calculate_percentage_weighted_accuracy`** **先归一化权重和为 1**，再做加权和写入汇总：

```508:519:repos/gorilla/berkeley-function-call-leaderboard/bfcl_eval/eval_checker/eval_runner_helper.py
        # TODO: @HuanzhiMao adjust the weights
        total_overall_accuracy = calculate_percentage_weighted_accuracy(
            [
                overall_accuracy_non_live,
                overall_accuracy_live,
                total_irrelevance,
                overall_accuracy_multi_turn,
                overall_accuracy_agentic,
            ],
            [10, 10, 10, 30, 40],
            display_na_if_category_missing=False,
        )
```

**`calculate_percentage_weighted_accuracy` 核心**：断言 **权重列表与 accuracy 列表等长**；**`weights_norm = [w/sum(weights) for w in weights]`**；逐桶 **`total_accuracy += accuracy_dict["accuracy"] * weight`**，并累计 **`total_count`**；若某桶 **`display_accuracy == "N/A"`** 且 **`display_na_if_category_missing`** 则整体显示 **N/A**（见同文件约 65–115 行）。

**⚠️ 与官网文案对齐**：Leaderboard 页曾写 **Overall 为各子类「未加权平均」**；与上式 **五大桶加权和** 并非同一句话。写论文或对比分数时应 **以同 commit 的 `eval_runner` 产出的 `score/data_overall.csv` 与 CHANGELOG/博客为准**，勿混用两种口径。

### 各维度准确率
- 各子类先在同类内聚合成 `accuracy_dict`，再进入上式；细项列见同文件写入 CSV 的字段（simple/multiple/parallel、multi_turn 子项、web_search、memory 等）。

## 评估流程

### 0. CLI 与产物目录（V4）

安装与入口以仓库 README 为准；典型流程：**先 `generate` 再 `evaluate`**。Typer 入口 **`bfcl_eval/__main__.py`**：

- **`python -m bfcl_eval generate`**：按模型配置生成各 **`test_category`** 的模型回复 JSON（写入 **`RESULT_PATH`** 下，可用 **`--result-dir`** 覆盖）。
- **`python -m bfcl_eval evaluate`**：调用 **`eval_runner.main`**，读取 **`result_dir`** 下结果，写入 **`score_dir`**（默认 **`SCORE_PATH`**）。支持 **`--partial-eval`**：仅对结果文件中**已出现**的条目计分，**与完整跑分的官方榜可能不一致**（`eval_runner.py` 结束时会打印警告）。
- **`python -m bfcl_eval scores`**：从 **`data_overall.csv`** 摘列打印表格。

评测完成后 **`eval_runner.main`** 会提示查看 **`data_overall.csv`**、**`data_live.csv`**、**`data_non_live.csv`**、**`data_multi_turn.csv`**、**`data_agentic.csv`**、**`data_format_sensitivity.csv`**（见 `eval_runner.py` 约 860–869 行）。

**模型名注意**：`evaluation_main` 内会把配置里的 **`/` 换成 `_`** 以适配文件路径，与 **`openfunctions_evaluation.py`** 所用 **`/` 格式区分（见 `eval_runner.py` 约 846–849 行注释）。

### 1. 单轮 AST 评估 (`ast_checker.py`)

**入口路由**：按 `test_category` 选择 `parallel` / `multiple` / 默认 simple（且要求 `len(model_output)==1`）。

```33:61:repos/gorilla/berkeley-function-call-leaderboard/bfcl_eval/eval_checker/ast_eval/ast_checker.py
def ast_checker(
    func_description,
    model_output,
    possible_answer,
    language: Language,
    test_category: str,
    model_name: str,
):
    if "parallel" in test_category:
        return parallel_function_checker_no_order(
            func_description, model_output, possible_answer, language, model_name
        )

    elif "multiple" in test_category:
        return multiple_function_checker(
            func_description, model_output, possible_answer, language, model_name
        )

    else:
        if len(model_output) != 1:
            return {
                "valid": False,
                "error": ["Wrong number of functions."],
                "error_type": "simple_function_checker:wrong_count",
            }

        return simple_function_checker(
            func_description[0], model_output[0], possible_answer[0], language, model_name
        )
```

**`simple_function_checker`（节选）**：先 `convert_func_name`（含部分模型 `_`↔`.` 规则），再检查函数名键、**required 参数齐全**、无 **unexpected** 参数，再按语言做 Java/JS/Python 类型转换与值校验。

```353:380:repos/gorilla/berkeley-function-call-leaderboard/bfcl_eval/eval_checker/ast_eval/ast_checker.py
    func_name = convert_func_name(func_name, model_name)

    # Check if function name matches
    if func_name not in model_output:
        result["valid"] = False
        result["error"].append(
            f"Function name {repr(func_name)} not found in model output."
        )
        result["error_type"] = "simple_function_checker:wrong_func_name"
        return result

    model_params = model_output[func_name]

    # Check for required parameters in model output
    for param in required_params:
        if param not in model_params:
            result["valid"] = False
            result["error"].append(f"Missing required parameter: {repr(param)}.")
            result["error_type"] = "simple_function_checker:missing_required"
            return result

    # Validate types and values for each parameter in model output
    for param, value in model_params.items():
        if param not in param_details or param not in possible_answer:
            result["valid"] = False
            result["error"].append(f"Unexpected parameter: {repr(param)}.")
            result["error_type"] = "simple_function_checker:unexpected_param"
            return result
```

### 2. 多轮评估 (`multi_turn_checker.py`)

**`multi_turn_checker`**：按 turn 对模型输出 **decode** 后，用 **`execute_multi_turn_func_call`** 先在每步执行模型侧调用，再对 **GT 调用序列** 执行一遍；每轮结束后：

1. **`state_checker`**：要求 **`model_instances` 与 `ground_truth_instances` 键集合一致**，并对每类实例用 **`_compare_instances`** 比对**公开属性**是否一致。
2. **`response_checker`**：将**截至当前 turn 的模型侧执行返回**与**当前 turn 的 GT 返回**比较，使用 **`_is_subsequence_unordered`**——即模型侧（含历史 turn）的返回集合需**覆盖**当前 turn GT 的每条返回，**不强制顺序**（注释说明并行场景）。

```100:120:repos/gorilla/berkeley-function-call-leaderboard/bfcl_eval/eval_checker/multi_turn_eval/multi_turn_checker.py
        ## Check after each turn ##
        assert len(model_instances) == len(
            ground_truth_instances
        ), f"Model instances and ground truth instances do not match in length for turn {turn_index}. Model instances: {len(model_instances)}, Ground truth instances: {len(ground_truth_instances)}"
        assert set(model_instances.keys()) == set(ground_truth_instances.keys())

        # Check the state of the instances
        state_check_result = state_checker(model_instances, ground_truth_instances)
        if not state_check_result["valid"]:
            state_check_result["execution_result"] = execution_results
            return state_check_result

        # Check the response of the function calls
        response_check_result = response_checker(
            all_turn_model_execution_results,
            single_turn_ground_truth_execution_results,
            turn_index,
        )
        if not response_check_result["valid"]:
            return response_check_result
```

**`multi_turn_irrelevance_checker`**：当某 turn 的 **GT 调用列表为空** 时，模型侧须 **`is_empty_execute_response`**（不应再产出有效调用）。

**子场景**：`base`、`miss_func`、`miss_param`、`long_context`（及含 **`composite`** 时长上下文标志）等，由 **`test_category`** 与数据字段驱动。

### 3. Agentic 评估 (`agentic_checker.py`)

对**最终文本**做 **`standardize_string`**（去空白、去掉 `,./-_*^()` 等标点并小写、单引号转双引号），再对每个候选答案做 **整词正则 `\b...\b`** 匹配；任一命中则 **`valid: True`**。

```6:49:repos/gorilla/berkeley-function-call-leaderboard/bfcl_eval/eval_checker/agentic_eval/agentic_checker.py
def agentic_checker(model_response: str, possible_answer_list: list[str]) -> dict:
    """
    Check if one of the possible answers is contained in the model response, ignoring case, whitespace and ",./-_*^" punctuation.
    """
    standardized_possible_answer_list = [
        standardize_string(possible_answer) for possible_answer in possible_answer_list
    ]
    ...
    standardized_model_response = standardize_string(model_response)

    for possible_answer in standardized_possible_answer_list:
        if re.search(rf"\b{re.escape(possible_answer)}\b", standardized_model_response):
            return {"valid": True, "error": []}

    return {
        "valid": False,
        "error_message": f"None of the expected answers were found in the model response.",
        "error_type": "agentic:answer_not_found",
        ...
    }


def standardize_string(input_string: str):
    """
    This function standardizes the string by removing all the whitespace, ",./-_*^()" punctuation, and converting it to lowercase
    ...
    """
    regex_string = r"[\,\.\/\-\_\*\^\(\)]"
    return re.sub(regex_string, "", input_string).lower().replace("'", '"')
```

**子场景**：Web Search、Memory (KV/Vector/RecSum) 等，由 **`eval_runner.py`** 中 **`agentic_runner` / `_evaluate_single_agentic_entry`** 调度（取对话**最后一条 assistant 消息**再送 `agentic_checker`）。

## 防污染机制

- **Live 分类**：使用实际 API 的实时数据
- **Non-Live 分类**：固定数据集

## 已知局限

1. 单轮 AST 侧**不评价**真实调用时序与对话语境（由 Multi-Turn / Agentic 等维度部分弥补）。
2. **Agentic** 主要对**最后一条模型文本**做标准化子串/词界匹配，**不审计**中间工具轨迹是否最优。
3. **Python/Java/JS** 语法与类型系统差异带来公平性争议；**Live** 子集依赖外部 API 稳定性。
4. **官网 Overall 文案**与 **`eval_runner_helper` 五大桶加权和**可能让读者误解，对比分数需锁定 **commit + `bfcl-eval` 版本 + 是否 partial eval**。

## 当前 SOTA

- **[BFCL V4 榜](https://gorilla.cs.berkeley.edu/leaderboard.html)**（截至抓取时页面写有 **Last Updated: 2025-12-16**）：要求复现使用页面给出的 **Gorilla commit**（如 **f7cf735**）或 **`pip install bfcl-eval==2025.12.17`**，并与 **[BFCL-Result](https://github.com/HuanzhiMao/BFCL-Result)** 公开轨迹对照。
- 具体名次与 Overall 数值随提交与维度扩展变化，**不在此笔记写死**；对比时说明 **FC vs Prompt**、**Format sensitivity**（非 FC 模型）等列含义（见榜首页说明）。
