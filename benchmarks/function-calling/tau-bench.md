# Tau-Bench (τ-Bench)

## 基本信息

| 项目 | 内容 |
|------|------|
| 名称 | τ-Bench (Tau-Bench) |
| 来源 | Sierra Research |
| 论文 | [arxiv.org/abs/2406.12045](https://arxiv.org/abs/2406.12045) |
| GitHub | [github.com/sierra-research/tau-bench](https://github.com/sierra-research/tau-bench) |
| 本地源码 | `repos/tau-bench/` |

## 评估目标

评估 AI Agent 在**动态对话场景**中，与模拟用户交互并使用工具完成任务的能力，同时检验是否严格遵守**领域特定策略**。

## 任务构造

### 两个领域

| 领域 | 场景 | 工具 |
|------|------|------|
| **Retail（零售）** | 在线零售客服 | 订单查询/取消/修改、退换货、用户认证 |
| **Airline（航空）** | 航空客服 | 航班查询/改签/取消、行李、常旅客 |

### 任务结构 (Task)

```python
class Task:
    user_id: str           # 用户 ID
    actions: List[Action]   # Ground truth 工具调用序列
    instruction: str        # 用户模拟器指令
    outputs: List[str]      # Agent 必须说出的内容（可选）
```

### 策略来源
- `wiki.md`：领域 wiki 文档，作为 system prompt 传给 Agent
- 包含认证流程、操作规范、沟通要求等

**零售域策略要点**：
- 必须先通过邮箱或姓名+邮编认证用户身份
- 执行数据库修改操作前必须列出操作详情并获得用户确认
- 每次只能调用一个工具

## 评估指标

### 核心指标：Average Reward + Pass^k

**数据哈希**：环境将内存中的 `data`（JSON 风格嵌套 dict/list/set/标量）递归转为 **可哈希元组** 后做 **`sha256(str(...).encode()).hexdigest()`**（见 `to_hashable` / `consistent_hash`）。

```27:41:repos/tau-bench/tau_bench/envs/base.py
def to_hashable(item: ToHashable) -> Hashable:
    if isinstance(item, dict):
        return tuple((key, to_hashable(value)) for key, value in sorted(item.items()))
    elif isinstance(item, list):
        return tuple(to_hashable(element) for element in item)
    elif isinstance(item, set):
        return tuple(sorted(to_hashable(element) for element in item))
    else:
        return item


def consistent_hash(
    value: Hashable,
) -> str:
    return sha256(str(value).encode("utf-8")).hexdigest()
```

**Reward 计算**（源码 **`Env.calculate_reward`**，默认 **1.0**，任一步失败置 **0.0**）：

1. 取 Agent 轨迹结束时的 **`data_hash = get_data_hash()`**（当前 `self.data`）。
2. **重载**初始数据库 **`self.data = self.data_load_func()`**，再按 **`task.actions`** 依次 **`self.step(action)`** 重放 ground truth（跳过 `terminate_tools` 中的动作名），得到 **`gt_data_hash`**；若 **`data_hash != gt_data_hash`** 则 **`reward = 0`**。
3. 若 **`task.outputs` 非空**：对每个必需字符串，须在 Agent 已执行的 **`RESPOND`** 类动作中，找到某条回复 **`content`**，使得 **`output.lower()`** 是该 **`content.lower().replace(",", "")` 的子串**；否则 **`reward = 0`**。

```124:164:repos/tau-bench/tau_bench/envs/base.py
    def calculate_reward(self) -> RewardResult:
        data_hash = self.get_data_hash()
        reward = 1.0
        actions = [
            action for action in self.task.actions if action.name != RESPOND_ACTION_NAME
        ]

        # Check if the database changes are correct. If they are not correct, then we set the reward to 0.
        # TODO: cache gt_data_hash in tasks.py (low priority)
        self.data = self.data_load_func()
        for action in self.task.actions:
            if action.name not in self.terminate_tools:
                self.step(action)
        gt_data_hash = self.get_data_hash()
        info = RewardActionInfo(
            r_actions=data_hash == gt_data_hash, gt_data_hash=gt_data_hash
        )
        if not info.r_actions:
            reward = 0.0

        if len(self.task.outputs) > 0:
            # check outputs
            r_outputs = 1.0
            outputs = {}
            for output in self.task.outputs:
                found = False
                for action in self.actions:
                    if (
                        action.name == RESPOND_ACTION_NAME
                        and output.lower()
                        in action.kwargs["content"].lower().replace(",", "")
                    ):
                        found = True
                        break
                outputs[output] = found
                if not found:
                    r_outputs = 0.0
                    reward = 0.0
            info = RewardOutputInfo(r_outputs=r_outputs, outputs=outputs)
            
        return RewardResult(reward=reward, info=info, actions=actions)
```

**Pass^k**（与论文一致的无偏组合估计；**`n = num_trials`**，**`c`** 为该 `task_id` 在 n 次 trial 中 **reward≈1** 的次数）：

```180:203:repos/tau-bench/tau_bench/run.py
def display_metrics(results: List[EnvRunResult]) -> None:
    def is_successful(reward: float) -> bool:
        return (1 - 1e-6) <= reward <= (1 + 1e-6)

    num_trials = len(set([r.trial for r in results]))
    rewards = [r.reward for r in results]
    avg_reward = sum(rewards) / len(rewards)
    # c from https://arxiv.org/pdf/2406.12045
    c_per_task_id: dict[int, int] = {}
    for result in results:
        if result.task_id not in c_per_task_id:
            c_per_task_id[result.task_id] = 1 if is_successful(result.reward) else 0
        else:
            c_per_task_id[result.task_id] += 1 if is_successful(result.reward) else 0
    pass_hat_ks: dict[int, float] = {}
    for k in range(1, num_trials + 1):
        sum_task_pass_hat_k = 0
        for c in c_per_task_id.values():
            sum_task_pass_hat_k += comb(c, k) / comb(num_trials, k)
        pass_hat_ks[k] = sum_task_pass_hat_k / len(c_per_task_id)
    print(f"🏆 Average reward: {avg_reward}")
    print("📈 Pass^k")
    for k, pass_hat_k in pass_hat_ks.items():
        print(f"  k={k}: {pass_hat_k}")
```

### 注意
- **官方 harness 仅支持 `retail` 与 `airline`**（`run()` 开头 `assert config.env in ["retail", "airline"]`），**不存在**本笔记旧版误写的「telecom」域。
- 策略遵守**无独立程序化 checker**，主要靠 **GT 重放后的 DB 哈希**与 **outputs 子串**间接约束；违规往往体现为哈希不一致。

## 评估流程

入口 **`tau_bench/run.py` 的 `run(config)`**：

- **`get_env`** 按 `task_split`（train/test/dev）与可选 **`task_ids` / 索引区间** 载入 **Retail 或 Airline**。
- **`agent_factory`** 按 **`agent_strategy`** 选择 **`tool-calling` / `act` / `react` / `few-shot`**（见同文件 124–177 行）。
- 支持 **`num_trials`** 轮与 **`ThreadPoolExecutor(max_workers=config.max_concurrency)`** 并行跑题；每题 **独立 `get_env(..., task_index=idx)`** 后调用 **`agent.solve`**，结果写入 **checkpoint JSON**。

对话中 **`env.step`**：若动作为 **回复用户**，则走 **`user.step`**，当观测含 **`###STOP###`** 时 **`done=True`**，此时触发 **`calculate_reward()`** 并将 **reward** 写回 `EnvResponse`（见 `base.py` `step`）。

```
run(config):
    → get_env(retail|airline) + agent_factory
    → for trial in num_trials:
          ThreadPoolExecutor: 每 task_id → isolated_env + agent.solve
    → display_metrics（avg reward + Pass^k）→ 写 ckpt JSON
```

### 终止条件
- 用户模拟器回复 `###STOP###`
- Agent 调用 `transfer_to_human_agents`
- 达到 `max_num_steps`（默认 30）

### 用户模拟器策略

| 策略 | 说明 |
|------|------|
| `llm` | 普通 LLM 生成回复 |
| `react` | 先 Thought 后 Response |
| `verify` | 生成后用另一 LLM 判断满意度 |
| `reflection` | verify 失败后生成 Reflection 再重试 |
| `human` | 真人输入 |

## 防污染机制

- 任务和数据在仓库中公开
- 无时间分割机制

## 已知局限

1. **仅 retail / airline 两域**，与部分第三方汇总页写的「telecom」等**不一致**（以本仓库为准）。
2. **策略遵守**无显式规则引擎，靠 **DB 哈希 + 输出子串** 间接约束；**子串匹配**可能过宽或过严（如标点、大小写、逗号被去掉）。
3. **`calculate_reward` 重放 GT `task.actions`** 时会再次 **`step`**，实现细节（与 `terminate_tools` 交互）需升级版本时对照源码。
4. **用户模拟器**（`UserStrategy` + LLM）质量影响可复现性与难度曲线。
5. **二值 reward**，Pass^k 需 **足够 trials** 才稳定。

## 当前 SOTA

- **无单一官方实时总榜**；社区常引用 **HAL** 等汇总页分域展示（如 [TAU-bench Retail](https://hal.cs.princeton.edu/taubench_retail)、[TAU-bench Airline](https://hal.cs.princeton.edu/taubench_airline)），**Pass^1 / Average reward** 与 **是否多 trial** 需看脚注。
- 横向对比务必固定：**领域（retail vs airline）**、**agent_strategy**、**user_strategy / user_model**、**temperature**、**num_trials**、**仓库 commit**。
