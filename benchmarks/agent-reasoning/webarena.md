# WebArena

## 基本信息

| 项目 | 内容 |
|------|------|
| 名称 | WebArena |
| 来源 | CMU |
| 论文 | [arxiv.org/pdf/2307.13854](https://arxiv.org/pdf/2307.13854.pdf) |
| GitHub | [github.com/web-arena-x/webarena](https://github.com/web-arena-x/webarena) |
| 复现改进 | [WebArena Verified](https://openreview.net/forum?id=CSIo4D7xBG)（OpenReview）：讨论原始评测中目标欠定、评估脆弱与**虚高成功率**等问题及更严格复评方向 |
| 本地源码 | `repos/webarena/` |

## 评估目标

在**自托管真实 Web 环境**中评估自主 Agent 完成复杂 Web 任务的能力。环境模拟了真实网站的功能和数据。

## 任务构造

### 自托管环境（7 类网站）

| 网站 | 端口 | 类型 |
|------|------|------|
| Shopping (OneStopShop) | 7770 | Magento2 电商 |
| Shopping Admin | 7780 | 电商后台 |
| Forum (Reddit) | 9999 | Postmill 论坛 |
| GitLab | 8023 | 代码托管 |
| Wikipedia | 8888 | 离线百科 |
| Map | 3000 | OpenStreetMap |
| Homepage | 4399 | 导航首页 |

### 数据规模与分布

- **812 个任务**

| 网站 | 任务数 | 占比 |
|------|--------|------|
| GitLab | 204 | 25.1% |
| Shopping | 192 | 23.6% |
| Shopping Admin | 184 | 22.7% |
| Reddit | 129 | 15.9% |
| Map | 128 | 15.8% |
| Wikipedia | 23 | 2.8% |

### 部署方式
- **AMI**（推荐）：预装所有站点的 AWS AMI
- **Docker**：各站独立容器

## 评估指标

### 核心指标：任务成功率 (0/1)

**任务级**：`evaluator_router(config)` 返回 **`EvaluatorComb`**，对 **`eval_types` 列表**中每个子评估器顺序求值，**子评估器之间得分连乘**；任一子项为 **0** 则整题为 **0**。

```336:374:repos/webarena/evaluation_harness/evaluators.py
class EvaluatorComb:
    def __init__(self, evaluators: list[Evaluator]) -> None:
        self.evaluators = evaluators

    @beartype
    def __call__(
        self,
        trajectory: Trajectory,
        config_file: Path | str,
        page: Page | PseudoPage,
        client: CDPSession,
    ) -> float:
        score = 1.0
        for evaluator in self.evaluators:
            cur_score = evaluator(trajectory, config_file, page, client)
            score *= cur_score
        return score


@beartype
def evaluator_router(config_file: Path | str) -> EvaluatorComb:
    """Router to get the evaluator class"""
    with open(config_file, "r") as f:
        configs = json.load(f)

    eval_types = configs["eval"]["eval_types"]
    evaluators: list[Evaluator] = []
    for eval_type in eval_types:
        match eval_type:
            case "string_match":
                evaluators.append(StringEvaluator())
            case "url_match":
                evaluators.append(URLEvaluator())
            case "program_html":
                evaluators.append(HTMLContentEvaluator())
            case _:
                raise ValueError(f"eval_type {eval_type} is not supported")

    return EvaluatorComb(evaluators)
```

**子评估器内部**通常也对多项检查做**连乘**（见下），故「全 1 才通过」在**字符串多条件 / URL 多 query 键 / HTML 多 target** 上层层生效。

### 三类评估器

| 评估器 | 用途 | 判定方式 |
|--------|------|----------|
| **StringEvaluator** | 文本回答 | exact_match / must_include / fuzzy_match(GPT-4) / ua_match |
| **URLEvaluator** | 页面 URL | base path + query 参数包含关系 |
| **HTMLContentEvaluator** | 页面内容 | 指定 HTML 元素中存在所需内容 |

### 评估类型组合分布

| 评估类型 | 任务数 |
|----------|--------|
| 仅 string_match | 325 |
| 仅 program_html | 282 |
| 仅 url_match | 66 |
| program_html + url_match | 129 |
| string_match + url_match | 10 |

### StringEvaluator 详细规则

- **exact_match**：`pred.lower() == ref.lower()`
- **must_include**：ref 中每个短语都出现在 pred 中
- **fuzzy_match**：GPT-4 判断语义等价
- **ua_match**：不可完成任务时的原因匹配

### HTMLContentEvaluator 高级功能

对 **`program_html`** 中每个 **target** 导航/定位 DOM 或执行 **`func:`** 辅助函数后，按 **`required_contents`** 做 **exact_match** 或 **must_include**（后者对多条内容仍 **`*=`**）。

```258:327:repos/webarena/evaluation_harness/evaluators.py
        targets = configs["eval"]["program_html"]

        score = 1.0
        for target in targets:
            ...
            if "exact_match" in target["required_contents"]:
                ...
                score *= float(cur_score)
            elif "must_include" in target["required_contents"]:
                ...
                for content in required_contents:
                    ...
                    score *= float(cur_score)
```

常用 **`func:`** 辅助见 `evaluation_harness/helper_functions.py`（如订单/GitLab/Reddit 相关 URL 或角色查询）。

### URLEvaluator 连乘细节

默认 **`url_note`** 为 **`GOLD in PRED`**：**base_path** 需命中 **`any(ref in pred)`** 得 **`base_score`**；每个 query 键上 **`query_score` 逐键相乘**（该键的任一候选值出现在 pred query 中则该因子为 1）。

```212:241:repos/webarena/evaluation_harness/evaluators.py
        pred = clean_url(page.url)
        ref_urls = configs["eval"]["reference_url"].split(" |OR| ")
        ...
        if matching_rule == "GOLD in PRED":
            ...
            base_score = float(
                any(
                    [
                        ref_base_path in pred_base_paths
                        for ref_base_path in ref_base_paths
                    ]
                )
            )
            query_score = 1.0
            for k, possible_values in ref_queries.items():
                query_score *= float(
                    any(
                        possible_ref_value in pred_query.get(k, [])
                        for possible_ref_value in possible_values
                    )
                )
            score = base_score * query_score
```

## 评估流程

1. **数据与登录**：`scripts/generate_test_data.py` 等准备任务配置；`browser_env/auto_login.py` 生成/刷新各站点 **storage_state**（cookie）。`run.py` 中若配置含 **`storage_state`**，会 **临时目录内调用 `auto_login.py`** 更新 cookie 并重写当次使用的 config（约 254–275 行）。
2. **逐任务**：**`ScriptBrowserEnv`**（Playwright）→ **`agent.reset` + `env.reset(options={"config_file": ...})`** → 主循环：每步先 **`early_stop(trajectory, max_steps, thresholds)`**（默认 **`parsing_failure_th=3`**、**`repeating_action_failure_th=3`**，见 `config()`），若触发则 **`create_stop_action("Early stop: ...")`**；否则 **`agent.next_action`** → **`env.step`**，直至 **STOP**、**terminated** 或早停。
3. **评分**：**`evaluator_router(config_file)`** 得到 **`EvaluatorComb`**，读 **trajectory**、**当前 page**、**CDP client**，返回 **float**（设计目标多为 **0/1**）。
4. **汇总**：**`Average score = sum(scores)/len(scores)`**（`run.py` 末尾）；异常路径可记 **`error.txt`**。

### 源码：`early_stop` 逻辑

```161:214:repos/webarena/run.py
def early_stop(
    trajectory: Trajectory, max_steps: int, thresholds: dict[str, int]
) -> tuple[bool, str]:
    """Check whether need to early stop"""

    # reach the max step
    num_steps = (len(trajectory) - 1) / 2
    if num_steps >= max_steps:
        return True, f"Reach max steps {max_steps}"

    last_k_actions: list[Action]
    action_seq: list[Action]

    # Case: parsing failure for k times
    k = thresholds["parsing_failure"]
    last_k_actions = trajectory[1::2][-k:]  # type: ignore[assignment]
    if len(last_k_actions) >= k:
        if all(
            [
                action["action_type"] == ActionTypes.NONE
                for action in last_k_actions
            ]
        ):
            return True, f"Failed to parse actions for {k} times"

    # Case: same action for k times
    k = thresholds["repeating_action"]
    last_k_actions = trajectory[1::2][-k:]  # type: ignore[assignment]
    action_seq = trajectory[1::2]  # type: ignore[assignment]

    if len(action_seq) == 0:
        return False, ""

    last_action: Action = action_seq[-1]

    if last_action["action_type"] != ActionTypes.TYPE:
        if len(last_k_actions) >= k:
            if all(
                [
                    is_equivalent(action, last_action)
                    for action in last_k_actions
                ]
            ):
                return True, f"Same action for {k} times"

    else:
        # check the action sequence
        if (
            sum([is_equivalent(action, last_action) for action in action_seq])
            >= k
        ):
            return True, f"Same typing action for {k} times"

    return False, ""
```

### 源码：评估器调用与单任务得分

```330:343:repos/webarena/run.py
            evaluator = evaluator_router(config_file)
            score = evaluator(
                trajectory=trajectory,
                config_file=config_file,
                page=env.page,
                client=env.get_page_client(env.page),
            )

            scores.append(score)

            if score == 1:
                logger.info(f"[Result] (PASS) {config_file}")
            else:
                logger.info(f"[Result] (FAIL) {config_file}")
```

**全套件均值**（所有任务跑完后）：

```364:365:repos/webarena/run.py
    env.close()
    logger.info(f"Average score: {sum(scores) / len(scores)}")
```

### 源码：StringEvaluator 对多参考项连乘

```123:170:repos/webarena/evaluation_harness/evaluators.py
    def __call__(
        self,
        trajectory: Trajectory,
        config_file: Path | str,
        page: Page | PseudoPage | None = None,
        client: CDPSession | None = None,
    ) -> float:
        with open(config_file, "r") as f:
            configs = json.load(f)

        last_action = self.get_last_action(trajectory)
        pred = self.clean_answer(last_action["answer"])

        score = 1.0
        for approach, value in configs["eval"]["reference_answers"].items():
            match approach:
                case "exact_match":
                    score *= self.exact_match(ref=value, pred=pred)

                case "must_include":
                    assert isinstance(value, list)
                    for must_value in value:
                        score *= self.must_include(
                            ref=must_value,
                            pred=pred,
                            tokenize=(len(value) == 1),
                        )
                case "fuzzy_match":
                    intent = configs["intent"]
                    if value == "N/A":
                        score *= self.exact_match(ref=value, pred=pred)
                        if score != 1:
                            score = 1.0 * self.ua_match(
                                intent=configs["intent"],
                                ref=configs["eval"]["string_note"],
                                pred=pred,
                            )
                    else:
                        assert isinstance(value, list)
                        for reference in value:
                            score *= self.fuzzy_match(
                                ref=reference, pred=pred, intent=intent
                            )
        return score
```

（`URLEvaluator` / `HTMLContentEvaluator` 内部同样对多个子检查做 **连乘**，与上表「全 1 才通过」一致。）

**CLI 默认**：**`--max_steps`** 默认 **30**；**`--parsing_failure_th`** / **`--repeating_action_failure_th`** 默认 **3**（见 `run.py` **`config()`**）。

## 防污染机制

- 环境自托管，数据不公开在互联网上
- 任务完成后需重置环境

## 已知局限

1. 环境搭建复杂，需自托管多个服务
2. 评估速度慢（需实时浏览器交互）
3. **StringEvaluator** 的 **fuzzy_match / ua_match** 依赖 **LLM**，成本高且随评测模型变更产生漂移
4. 环境可能因版本差异产生不一致结果
5. **评测链路易碎**：目标表述、URL/HTML 断言与 **连乘** 结构会导致**假阴/假阳**；**WebArena Verified** 等工作讨论更严格复评与误差区间（见基本信息表链接）

## 当前 SOTA

- **人类基线**：论文/官方材料常引用约 **78%** 量级成功率（以原论文与复现实验设置为准）。
- **模型侧**：公开聚合转载中可见 **70%+** 量级的系统报告（如部分榜单提及 **OpAgent ~71.6%** 等），**非官方单一托管榜**，且与 **prompt/观测类型（a11y vs image）/是否 Verified 复评**强相关；**勿与 OSWorld、AndroidWorld 成功率直接横向对比**。
- **跟踪进展**：以 **原仓库 issue/论文更新** 与 **[WebArena Verified](https://openreview.net/forum?id=CSIo4D7xBG)** 类后续工作为准，避免只采信二手排行榜上的单一数字。
