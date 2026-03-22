# GAIA (General AI Assistants)

## 基本信息

| 项目 | 内容 |
|------|------|
| 名称 | GAIA (General AI Assistants) |
| 来源 | Meta AI 等（见论文作者列表） |
| 论文 | [GAIA: a benchmark for General AI Assistants (arXiv:2311.12983)](https://arxiv.org/abs/2311.12983) |
| 数据集 | [huggingface.co/datasets/gaia-benchmark/GAIA](https://huggingface.co/datasets/gaia-benchmark/GAIA)（**Gated**：需登录并接受条款，禁止将 validation/test 以可爬取形式再分发） |
| 排行榜 | [huggingface.co/spaces/gaia-benchmark/leaderboard](https://huggingface.co/spaces/gaia-benchmark/leaderboard) |
| 官方计分参考实现 | HF Space 源码（本仓库克隆于 `repos/gaia-leaderboard/`，含 `scorer.py`） |

## 评估目标

评测具备**工具、检索、多步规划**能力的「通用助手」在**真实世界任务**上的表现：问题对人类概念上往往不难，但需要 **Web/代码执行/读文件/多模态附件** 等组合能力才能得到**唯一、简短的标准答案**。

## 任务构造

### 规模与划分
- 总计 **450+** 道非平凡题（常见写作 **466**）；分 **Level 1 / 2 / 3** 三档难度。
- **Dev**：可公开用于调试（含答案与元数据）。
- **Test**：题目可获取，**标准答案与部分元数据不公开**；正式分数仅能通过 **Leaderboard 提交** 计算，以降低污染与爬虫泄漏风险。
- 字段（2025-10 起 Parquet 与旧 JSONL 对齐）：`task_id`、`Question`、`Level`、`Final answer`、`file_name`、`file_path`、`Annotator Metadata` 等；部分题带 **PDF/图片/表格** 等附件，`file_path` 相对数据集根目录。

### 能力覆盖
- 浏览与检索、工具编排、多步推理、读附件、基础规划与分解等。

## 评估指标

### 核心：按题的布尔正确 + 总体 Accuracy

- 对每一题，将模型最终输出与 **ground truth** 比较，得到 **True/False**；总体 **Accuracy = 正确题数 / 总题数**。
- 可按 **Level** 与 **Overall** 分别报告。

### 答案匹配规则（官方 `question_scorer`）

计分**不是**简单的 `pred in ref`，而是按 ground truth **类型**分支：

1. **GT 为数值**（可 `float`）：对模型答案做 **`normalize_number_str`**（去掉 `$`、`%`、`,` 等）后转浮点，与 GT 比较相等。
2. **GT 含列表分隔符**（`,` 或 `;`）：将 GT 与模型答案按分隔符切分，**长度须一致**；各元素若可解析为数字则按数值比，否则用 **`normalize_str(..., remove_punct=False)`** 比字符串（保留标点差异）。
3. **GT 为普通字符串**：两侧经 **`normalize_str`**：去全部空白、可选去掉标点、转小写，再相等则判对。

```29:81:repos/gaia-leaderboard/scorer.py
def question_scorer(
    model_answer: str,
    ground_truth: str,
) -> bool:
    def is_float(element: any) -> bool:
        try:
            float(element)
            return True
        except ValueError:
            return False
        
    if model_answer is None:
        model_answer = "None"

    # if gt is a number
    if is_float(ground_truth):
        print(f"Evaluating {model_answer} as a number.")
        normalized_answer = normalize_number_str(model_answer)
        return normalized_answer == float(ground_truth)

    # if gt is a list
    elif any(char in ground_truth for char in [",", ";"]):
        gt_elems = split_string(ground_truth)
        ma_elems = split_string(model_answer)
        if len(gt_elems) != len(ma_elems):
            warnings.warn(
                "Answer lists have different lengths, returning False.", UserWarning
            )
            return False
        comparisons = []
        for ma_elem, gt_elem in zip(ma_elems, gt_elems):
            if is_float(gt_elem):
                normalized_ma_elem = normalize_number_str(ma_elem)
                comparisons.append(normalized_ma_elem == float(gt_elem))
            else:
                comparisons.append(
                    normalize_str(ma_elem, remove_punct=False)
                    == normalize_str(gt_elem, remove_punct=False)
                )
        return all(comparisons)

    # if gt is a str
    else:
        print(f"Evaluating {model_answer} as a string.")
        return normalize_str(model_answer) == normalize_str(ground_truth)
```

```84:104:repos/gaia-leaderboard/scorer.py
def normalize_str(input_str, remove_punct=True) -> str:
    ...
    no_spaces = re.sub(r"\s", "", input_str)

    if remove_punct:
        translator = str.maketrans("", "", string.punctuation)
        return no_spaces.lower().translate(translator)
    else:
        return no_spaces.lower()
```

## 评估流程

1. 参与者在**不泄露 test 答案**的前提下，用任意 Agent/工具链跑测试集，产出每题 **最终答案字符串**（格式须符合提交规范）。
2. 向 **Hugging Face GAIA Leaderboard** 提交；主办方用与 `scorer.py` 一致的逻辑在服务端比对 **私有答案**。
3. 公开展示 Overall / Level 拆分及元数据（具体列以榜单为准）。

自评时仅能对 **dev** 或本地持有答案的子集复现；**test 官方分数不可自算全量**。

### Leaderboard 服务端计分（`repos/gaia-leaderboard/app.py`）

Space 使用 **`YEAR_VERSION = "2023"`**，从私有集 **`GAIA_internal`** 读 **gold**（含 `Final answer`、`Level`），对提交 JSONL **逐行**调用 **`question_scorer(model_answer, gold_final_answer)`**，累计 **Overall 与 Level 1/2/3** 正确数；并强制 **test 集题量与分层题量**与常量一致：

```31:33:repos/gaia-leaderboard/app.py
YEAR_VERSION = "2023"
ref_scores_len = {"validation": 165, "test": 301}
ref_level_len = {"validation": {1: 53, 2: 86, 3: 26}, "test": {1: 93, 2: 159, 3: 49}}
```

```145:182:repos/gaia-leaderboard/app.py
        # SCORE SUBMISSION
        file_path = path_to_file.name        
        scores = {"all": 0, 1: 0, 2: 0, 3: 0}
        num_questions = {"all": 0, 1: 0, 2: 0, 3: 0}
        task_ids = []
        with open(f"scored/{organisation}_{model}.jsonl", "w") as scored_file:
            with open(file_path, 'r') as f:
                for ix, line in enumerate(f):
                    try:
                        task = json.loads(line)
                    except Exception:
                        return format_error(f"Line {ix} is incorrectly formatted. Please fix it and resubmit your file.")

                    if "model_answer" not in task:
                        return format_error(f"Line {ix} contains no model_answer key. Please fix it and resubmit your file.")
                    answer = task["model_answer"]
                    task_id = task["task_id"]
                    try:
                        level = int(gold_results[val_or_test][task_id]["Level"])
                    except KeyError:
                        return format_error(f"{task_id} not found in split {val_or_test}. Are you sure you submitted the correct file?")

                    score = question_scorer(task['model_answer'], gold_results[val_or_test][task_id]["Final answer"])
                    
                    scored_file.write(
                        json.dumps({
                            "id": task_id,
                            "model_answer": answer,
                            "score": score,
                            "level": level
                        }) + "\n"
                    )
                    task_ids.append(task_id)

                    scores["all"] += score
                    scores[level] += score
                    num_questions["all"] += 1
                    num_questions[level] += 1
```

```188:189:repos/gaia-leaderboard/app.py
        if any([num_questions[level] != ref_level_len[val_or_test][level] for level in [1, 2, 3]]):
            return format_error(f"Your submission has {num_questions[1]} questions for level 1, {num_questions[2]} for level 2, and {num_questions[3]} for level 3, but it should have {ref_level_len[val_or_test][1]}, {ref_level_len[val_or_test][2]}, and {ref_level_len[val_or_test][3]} respectively. Please check your submission.")
```

**总分写入榜单**（比例为 **正确数 / 该 split 参考题量**；展示时 UI 再 ×100 为百分比列）：

```213:224:repos/gaia-leaderboard/app.py
        eval_entry = {
            "model": model,
            "model_family": model_family,
            "system_prompt": system_prompt,
            "url": url,
            "organisation": organisation,
            "score": scores["all"]/ref_scores_len[val_or_test],
            "score_level1": scores[1]/num_questions[1],
            "score_level2": scores[2]/num_questions[2],
            "score_level3": scores[3]/num_questions[3],
            "date": datetime.datetime.today().strftime('%Y-%m-%d')
        }
```

说明：**test 为 301 题（Level 93/159/49）** 与常见「466 总题」口径并存时，以 **Leaderboard 所绑定的内部元数据与 `ref_*` 常量**为准；数据集改版时需同步 Space 代码。

## 防污染机制

- **Gated 数据集** + **test 答案闭源** + 禁止公开再托管可爬副本。
- Leaderboard 作为**唯一**权威 test 评分入口（在合规提交前提下）。

## 已知局限

1. **字符串归一化边界**：特殊符号、单位、多语言答案可能与 `normalize_str` / 数值规则不完全一致，存在「人对但分错」。
2. **时效性**：依赖网页或实时信息的题目，GT 可能随时间失效（需版本化与人工维护）。
3. **附件与解析**：模型强依赖 OCR/PDF/表格解析链路，评测的是「助手+工具栈」而不仅是裸 LLM。
4. **榜单可比性**：**多 Agent 编排 / 搜索 API / 是否人审**差异极大，比较需读提交说明，勿仅看单一百分比。

## 当前 SOTA

- **人类**（论文）：约 **92%** overall。
- **模型/系统**：分数随提交快速变化；**单模型**与**完整 Agent 系统**不可混排。请以 **[官方 Leaderboard](https://huggingface.co/spaces/gaia-benchmark/leaderboard)** 为准；历史参考如公开报道中 **Claude Sonnet 4.5** 等在 **~75%** 量级曾居前列（具体以榜单时间与提交类型为准）。

## 本地 `repos/` 说明

- **`repos/gaia-leaderboard/`**：`git clone` 自 Hugging Face Space `gaia-benchmark/leaderboard`，便于离线阅读 `scorer.py`；根目录 `.gitignore` 已忽略 `repos/`，无需再改。
