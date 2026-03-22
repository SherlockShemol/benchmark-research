# AgentBench

## 基本信息

| 项目 | 内容 |
|------|------|
| 名称 | AgentBench |
| 来源 | THUDM (清华大学) |
| 论文 | [arxiv.org/abs/2308.03688](https://arxiv.org/abs/2308.03688) · [OpenReview (ICLR 2024)](https://openreview.net/pdf?id=zAdUB0aCTQ) |
| GitHub | [github.com/THUDM/AgentBench](https://github.com/THUDM/AgentBench)（**`main` 默认为 AgentBench FC**，与论文时代的 **v0.1/v0.2「8 环境」** 并存；复现需选对 **tag/分支**） |
| FC 榜（新） | [Google 表格 Leaderboard](https://docs.google.com/spreadsheets/d/e/2PACX-1vRR3Wl7wsCgHpwUw1_eUXW_fptAPLL3FkhnW_rua0O1Ji_GIVrpTjY5LaKAhwO-WeARjnY_KNw0SYNJ/pubhtml)（README 2025.10 起） |
| 本地源码 | `repos/AgentBench/` |

## 评估目标

在多类**隔离任务环境**中评测 LLM 作为自主 Agent 的交互决策能力：每类任务由独立 Docker/服务 worker 提供 HTTP API，客户端驱动「模型 ↔ 环境」多轮对话直至结束，再汇总为 per-task 与跨任务对比指标。

## 任务构造

### 当前 `main`：AgentBench FC（Function Calling，约 2025.10）

- **交互形态**：**函数调用式** prompt，与 [AgentRL](https://github.com/THUDM/AgentRL) 集成。
- **一键容器栈**：**`docker compose -f extra/docker-compose.yml up`** 拉起 **AgentRL Controller**、任务 worker（**`alfworld` / `dbbench` / `knowledgegraph` / `os_interaction` / `webshop`**）、**Freebase（KG）**、**Redis** 等（详见仓库 README）。
- **依赖**：**KG** 需自备 **Virtuoso/Freebase** 数据至约定路径；**`webshop`** 启动约需 **~16GB RAM**；README 警告 **`alfworld` worker 存在内存与磁盘泄漏**，需周期性重启 worker。

### 经典八环境（论文 / v0.2 及更早分支）

| 环境 | 典型任务前缀 | 能力侧重 |
|------|--------------|----------|
| Operating System | `os` / `operating` | 在 Linux 容器中执行命令完成目标 |
| Database | `db` / `database` | SQL 与数据库交互 |
| Knowledge Graph | `kg` / `knowledge` | 知识图谱查询与推理 |
| Digital Card Game | `card` / `cg` / `dcg` | 卡牌类策略决策 |
| ALFWorld (House-holding) | `alf` | 文本家庭环境导航与操作 |
| Web Shopping | `ws` / `webshop` | 购物场景中的选择与下单类交互 |
| Mind2Web (Web Browsing) | `m2w` / `mind2web` | Web 导航类逐步决策 |
| Lateral Thinking Puzzles | `ltp` / `literal` | 谜题类推理 |

各环境数据与 judge 逻辑在 **`src/server/tasks/<env>/`**；完整 8 类需按 README 拉取 **`longinyu/agentbench-*`** 等镜像。**对比分数前务必声明：FC 子集 vs 标准 8 环境 test。**

**相关扩展**：[VisualAgentBench](https://github.com/THUDM/VisualAgentBench)（2024.08，视觉 Agent 多环境）。

## 评估指标

### 汇总方式

- **单任务主指标**：**`TaskClient.calculate_overall`** 先在本地统计各 **`SampleStatus` 占比** 与 **history 长度**，再 **`POST /calculate_overall`** 把样本列表交给 worker；返回体为 **`{"total", "validation": {...}, "custom": <worker JSON>}`**，**`analysis.py`** 的 **`TaskHandler.get_main_metric`** 只读 **`custom`**（与 **`validation` 分桶展示**解耦）。

```127:153:repos/AgentBench/src/client/task.py
    def calculate_overall(self, results: List[TaskOutput]) -> JSONSerializable:
        statistics = {s: 0 for s in SampleStatus}
        for result in results:
            statistics[SampleStatus(result.status)] += 1
        for s in SampleStatus:
            statistics[s] /= len(results)
        statistics["average_history_length"] = sum(
            [len(result.history) for result in results]
        ) / len(results)
        statistics["max_history_length"] = max(
            [len(result.history) for result in results]
        )
        statistics["min_history_length"] = min(
            [len(result.history) for result in results]
        )
        ret = {
            "total": len(results),
            "validation": statistics,
        }
        res = requests.post(
            self.controller_address + "/calculate_overall",
            json=CalculateOverallRequest(name=self.name, results=results).dict(),
        )
        if res.status_code != 200:
            raise TaskNetworkException(res.text)
        ret["custom"] = res.json()
        return ret
```

- **跨任务分析**：**`python -m src.analysis`**（见 **`analysis.py`**）扫描 **`{output}/{agent}/{task}/overall.json`**；**`VALIDATION_MAP_FUNC`** 将人类可读标签映射到 **`validation` 内各状态比例的组合**（如 *Task Limit Exceeded* 对应多类状态之和）：

```44:53:repos/AgentBench/src/analysis.py
VALIDATION_MAP_FUNC = {
    "Completed": lambda x: x["COMPLETED"],
    "Context Limit Exceeded": lambda x: x["AGENT_CONTEXT_LIMIT"],
    "Invalid Format": lambda x: x["AGENT_VALIDATION_FAILED"],
    "Invalid Action": lambda x: x["AGENT_INVALID_ACTION"],
    # Not in above list
    "Task Limit Exceeded": lambda x: sum(
        [x[t] for t in x if t in ["UNKNOWN", "TASK_ERROR", "TASK_LIMIT_REACHED"]]
    ),
}
```

### 各环境与 `analysis.py` 中主指标映射

| 任务类型 | `TaskHandler` | 主指标来源（`overall["custom"]`） |
|----------|---------------|-------------------------------------|
| OS | `OS` | `custom["overall"]["acc"]` |
| DB | `DB` | `custom["overall_cat_accuracy"]` |
| KG | `KG` | `custom["main"]` |
| DCG | `DCG` | `custom["score"]`（或 legacy `win_rate`） |
| LTP | `LTP` | `custom["main"]` |
| ALFWorld | `HH` | `custom["overall"]["success_rate"]` |
| WebShop | `WS` | `custom["reward"]` |
| Mind2Web | `WB` | `custom["step_sr"] / 100`（转为 0–1 量级） |

具体语义（如 acc 是样本级还是回合级）以实现该任务的 `task.py` 为准。

## 评估流程

1. **依赖与环境**：推荐 **Python 3.9**（仓库 pin 旧版 numpy 等）；配置 **`configs/agents/*.yaml`** API Key；可用 **`python -m src.client.agent_test`** 自检 Agent。
2. **启动 Worker + Controller**：经典流程为 **`python -m src.start_task -a`**（占用约 **5000–5015** 端口；macOS 注意释放 **5000**）；轻量预设 **`--config configs/start_task_lite.yaml`**。**FC** 推荐 **`docker compose -f extra/docker-compose.yml up`**（见 README）。
3. **下发评测**：**`python -m src.assigner`**（或 **`--config configs/assignments/lite.yaml`**）；YAML 声明 **`assignments`**、并发、**`output`** 等。
4. **调度**：**`Assigner`** 为每个 **`(agent, task, index)`** 建线程；单样本结果追加 **`{output}/{agent}/{task}/runs.jsonl`**。
5. **单样本**（**`TaskClient.run_sample`**）：**`POST /start_sample`**（**406 → `NOT_AVAILABLE`**；非 200 → **`START_FAILED`**）→ 取 **`session_id`** → 当 **`output.status == RUNNING`** 时 **`agent.inference(history)`** → 组装 **`AgentOutput`**（含 **`AGENT_CONTEXT_LIMIT`** 分支）→ **`POST /interact`**；失败则 **`POST /cancel`** 并返回 **`AGENT_FAILED` / `INTERACT_FAILED` / `NETWORK_ERROR`**。
6. **任务级汇总**：该 **`(agent, task)`** 全部 index 完成后，**`record_completion`** 线程调用 **`calculate_overall`** 写 **`overall.json`**。
7. **聚合表**：**`python -m src.analysis -c <definition_or_assign_yaml> -o <output_dir> [-s <save_prefix>] [-t <since_timestamp>]`**（默认 **`configs/assignments/definition.yaml`**、**`outputs`**、**`analysis`**，见 **`analysis.py`** 末尾 argparse）。

### 失败与截断类状态

客户端将 agent 侧异常映射为 `TaskError`（如 `AGENT_FAILED`、`NETWORK_ERROR`）；环境侧常见终止包括达到轮次上限、非法动作、上下文超限等，并反映在 `overall.json` 的 `validation` 统计中。

## 防污染机制

- **无统一「时间切分」或隐藏测试集**：各子基准多为公开或自建环境，可复现性依赖镜像与数据版本。
- **环境隔离**：任务在 Docker/独立服务中执行，减轻串扰，但不等同于防数据泄漏。

## 已知局限

1. **工程成本高**：Controller + 多 Worker +（FC）Compose/Redis/Freebase；端口与镜像体积敏感。
2. **指标异质**：**FC 5 任务**与**经典 8 环境**不可混报「总分」；`analysis` 仅统一抽取 **per-task 主指标**。
3. **资源与稳定性**：**WebShop ~16GB**、**ALFWorld worker 泄漏**、**KG 在线端点不稳**（README 建议本地 Virtuoso）。
4. **版本分叉**：**`main` FC** 与 **v0.2 八环境** 的 **prompt 形态与任务集合**不同，纵向对比需固定 **commit**。
5. **扩展性**：新任务需实现 **`/start_sample` `/interact` `/calculate_overall`** 契约及客户端 `TaskHandler`（若走 `analysis`）。

## 当前 SOTA

- **AgentBench FC**：以 README 指向的 **[公开表格榜](https://docs.google.com/spreadsheets/d/e/2PACX-1vRR3Wl7wsCgHpwUw1_eUXW_fptAPLL3FkhnW_rua0O1Ji_GIVrpTjY5LaKAhwO-WeARjnY_KNw0SYNJ/pubhtml)** 为准（随投稿更新）；联系 **`agentbench_fc@googlegroups.com`** 投稿。
- **经典 8 环境（论文/test）**：[OpenReview ICLR 2024 PDF](https://openreview.net/pdf?id=zAdUB0aCTQ) 中 **GPT-4 系列**整体领先当时开源模型；复现请用 **[v0.2](https://github.com/THUDM/AgentBench/tree/v0.2)** 等对应分支并对照 README 旧 Leaderboard 图。
- **视觉扩展**：[VisualAgentBench](https://github.com/THUDM/VisualAgentBench) 另报多环境 VLM 结果，**不与**纯文本 AgentBench 主表直接合并。

## 源码关键片段

**客户端多轮交互**（**`TaskClient.run_sample`**，节选连续逻辑）：

```54:125:repos/AgentBench/src/client/task.py
    def run_sample(self, index: SampleIndex, agent: AgentClient) -> TaskClientOutput:
        try:
            result = requests.post(
                self.controller_address + "/start_sample",
                json=StartSampleRequest(name=self.name, index=index).dict(),
            )
        except Exception as e:
            return TaskClientOutput(error=TaskError.NETWORK_ERROR.value, info=str(e))
        if result.status_code == 406:
            return TaskClientOutput(
                error=TaskError.NOT_AVAILABLE.value, info=result.text
            )
        if result.status_code != 200:
            return TaskClientOutput(
                error=TaskError.START_FAILED.value, info=result.text
            )
        result = result.json()
        sid = result["session_id"]
        latest_result = result
        while SampleStatus(result["output"]["status"]) == SampleStatus.RUNNING:
            try:
                content = agent.inference(result["output"]["history"])
                response = AgentOutput(content=content)
            except AgentContextLimitException:
                response = AgentOutput(status=AgentOutputStatus.AGENT_CONTEXT_LIMIT)
            except Exception as e:
                if hasattr(agent, "model_name"):
                    model_name = agent.model_name
                elif hasattr(agent, "name"):
                    model_name = agent.name
                else:
                    model_name = agent.__class__.__name__
                print(f"ERROR: {model_name}/{self.name} agent error", e)
                requests.post(
                    self.controller_address + "/cancel",
                    json=CancelRequest(session_id=sid).dict(),
                )
                return TaskClientOutput(
                    error=TaskError.AGENT_FAILED.value,
                    info=str(e),
                    output=latest_result,
                )

            try:
                result = requests.post(
                    self.controller_address + "/interact",
                    json=InteractRequest(
                        session_id=sid,
                        agent_response=response,
                    ).dict(),
                )
            except Exception as e:
                return TaskClientOutput(
                    error=TaskError.NETWORK_ERROR.value,
                    info=str(e),
                    output=latest_result,
                )
            if result.status_code != 200:
                requests.post(
                    self.controller_address + "/cancel",
                    json=CancelRequest(session_id=sid).dict(),
                )
                return TaskClientOutput(
                    error=TaskError.INTERACT_FAILED.value,
                    info=result.text,
                    output=latest_result,
                )

            result = result.json()
            latest_result = result
        return TaskClientOutput(output=result["output"])
```

**按任务名抽取主指标**（`analysis.py` 中 `TaskHandler`）：

```144:263:repos/AgentBench/src/analysis.py
class TaskHandler:
    def match(self, task_name) -> bool:
        raise NotImplementedError()

    def get_main_metric(self, overall_result):
        raise NotImplementedError()
    ...
class OS(TaskHandler):
    def match(self, task_name) -> bool:
        task_name = task_name.lower()
        return task_name.startswith("os") or task_name.startswith("operating")

    def get_main_metric(self, overall_result):
        return overall_result["custom"]["overall"]["acc"]
...
class WS(TaskHandler):
    def match(self, task_name) -> bool:
        task_name = task_name.lower()
        return task_name.startswith("ws") or task_name.startswith("webshop")

    def get_main_metric(self, overall_result):
        return overall_result["custom"]["reward"]
```

**OS 任务：容器内交互后以二元结果收尾**（`_judge` 片段）：

```454:474:repos/AgentBench/src/server/tasks/os_interaction/task.py
        evaluation_result = await self._evaluate_answer(answer, config, container, session)
        ...
        jd = evaluation_result.get("success", False)
        os_score = 1 if jd else 0
        final_reward = 1 if jd else 0
        ...
        return TaskSampleExecutionResult(
            status=SampleStatus.COMPLETED, result={"result": jd}
        )
```

**任务完成后写 `overall.json`**（`Assigner.record_completion`）：

```301:327:repos/AgentBench/src/assigner.py
    def record_completion(
        self, agent: str, task: str, index: SampleIndex, result: TaskOutput
    ):
        def calculate_overall_worker():
            ...
            overall = task_client.calculate_overall(self.completions[agent][task])
            with open(
                os.path.join(self.get_output_dir(agent, task), "overall.json"), "w"
            ) as f:
                f.write(json.dumps(overall, indent=4, ensure_ascii=False))
        ...
            if len(self.completions[agent][task]) == len(self.task_indices[task]):
                overall_calculation = True
```
