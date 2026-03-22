# AndroidWorld

## 基本信息

| 项目 | 内容 |
|------|------|
| 名称 | AndroidWorld |
| 来源 | Google Research |
| 论文 | [AndroidWorld: A Dynamic Benchmarking Environment for Autonomous Agents](https://arxiv.org/abs/2405.14573) |
| 官网 / 任务说明 | [google-research.github.io/android_world](https://google-research.github.io/android_world/) |
| 公开排行 | [Leaderboard（Google 表格）](https://docs.google.com/spreadsheets/d/1cchzP9dlTZ3WXQTfYNhh3avxoLipqHN75v1Tb86uhHo/edit?gid=0#gid=0)（官网首页链接） |
| GitHub | [github.com/google-research/android_world](https://github.com/google-research/android_world) |
| 本地源码 | `repos/android_world/`（对照 `suite_utils.py`、`episode_runner.py`、`run.py`） |

## 评估目标

在**真实 Android 模拟器**上评测**多模态 / GUI 自动化 Agent**：通过屏幕观测（截图、无障碍树等）与 **ADB/AndroidEnv** 交互，完成跨 App 的日常与办公类任务。强调**可复现**与**基于系统状态的奖励**（durable reward），并支持**参数化任务**以产生大量实例变体。

## 任务构造

- **模板规模**：**116** 个手工设计的任务模板，分布在约 **20** 个真实 App 中（另可跑 **MiniWoB++** 子族，浏览器控件以 Android 原生组件呈现）。
- **动态实例化**：每个模板可带随机/参数化字段（如短信内容、联系人信息）；`n_task_combinations` 控制每模板采样多少组参数，从而得到**远多于 116 条轨迹**的评测。
- **环境**：推荐 **Pixel 6 + API 33 (Tiramisu)** AVD（`AndroidWorldAvd`），模拟器需 **`-grpc 8554`** 等参数以配合无障碍转发；提供**实验性 Docker** 与 **AWS/并行**扩展方向（以 README 为准）。

## 评估指标

### 单 episode 成功信号

- 任务结束后调用 **`task.is_successful(env)`**，得到 **任务是否达成**（底层依赖各 `TaskEval` 对系统状态的检查）。
- 若 Agent 未在当轮声明结束（`interaction_results.done` 为假），则**即使环境已满足目标**，官方管线仍将成功记为 **0.0**（强制要求 Agent 显式结束）。

### Step 预算（与任务复杂度绑定）

**`suite_utils.run`** 内嵌的 **`run_episode`** 调用 **`episode_runner.run_episode`**，其中 **`max_n_steps = _allocate_step_budget(task.complexity)`**，而 **`_allocate_step_budget` 实现为 `int(10 * task_complexity)`**（`complexity` 为 **None** 会抛错）。即**步数上限由任务元数据中的复杂度标量线性放大**，不是单一全局常数。

```453:503:repos/android_world/android_world/suite_utils.py
  def run_episode(task: task_eval.TaskEval) -> episode_runner.EpisodeResult:
    if demo_mode:
      _display_goal(agent.env, task)
    return episode_runner.run_episode(
        goal=task.goal,
        agent=agent,
        max_n_steps=_allocate_step_budget(task.complexity),
        start_on_home_screen=task.start_on_home_screen,
        termination_fn=(
            miniwob_base.is_episode_terminated
            if task.name.lower().startswith('miniwob')
            else None
        ),
    )
...
def _allocate_step_budget(task_complexity: float) -> int:
  if task_complexity is None:
    raise ValueError('Task complexity must be provided.')
  return int(10 * (task_complexity))
```

**`episode_runner.run_episode`**：每步 **`agent.step(goal)`**；若 **`termination_fn(env)`** 为真（MiniWoB 子族）则 **`done=True` 提前结束**；否则仅当 **`result.done`**（Agent 声明完成）才 **`done=True`**；若跑满 **`max_n_steps`** 仍未声明完成，则 **`done` 取最后一轮的 `result.done`**（通常为 **False**），与 **`is_successful` 组合后成功率为 0。

```42:105:repos/android_world/android_world/episode_runner.py
def run_episode(
    goal: str,
    agent: base_agent.EnvironmentInteractingAgent,
    max_n_steps: int = 10,
    start_on_home_screen: bool = False,
    termination_fn: Callable[[interface.AsyncEnv], float] | None = None,
    print_fn: Callable[[str], None] = print,
) -> EpisodeResult:
  ...
  for step_n in range(max_n_steps):
    result = agent.step(goal)
    ...
    if termination_fn(agent.env):
      ...
      return EpisodeResult(
          done=True,
          step_data=_transpose_lod_to_dol(output),
      )
    elif result.done:
      ...
      return EpisodeResult(
          done=result.done,
          step_data=_transpose_lod_to_dol(output),
      )
  ...
  return EpisodeResult(
      done=result.done, step_data=_transpose_lod_to_dol(output)
  )
```

### 聚合（`process_episodes`）

每完成一个实例，**`_run_task_suite`** 会调用 **`process_episodes(episodes_metadata, print_summary=True)`**。默认按 **`task_template` groupby**，得到每模板 **`num_complete_trials`**、**`mean_success_rate`（即 `IS_SUCCESSFUL` 均值）**、**`mean_episode_length`**、**`total_runtime_s`** 等，并与 **`task_metadata.json`** 中的 **difficulty/tags** merge，便于按标签分层打印。

```681:707:repos/android_world/android_world/suite_utils.py
  result_df = df.groupby(
      constants.EpisodeConstants.TASK_TEMPLATE, dropna=True
  ).agg({
      constants.EpisodeConstants.IS_SUCCESSFUL: ['count', 'mean'],
      constants.EpisodeConstants.EPISODE_LENGTH: 'mean',
      constants.EpisodeConstants.RUN_TIME: 'sum',
      ...
  })
  ...
  tagged_result_df = result_df.merge(
      metadata_df, on=[_TASK_TEMPLATE_COLUMN], how='left'
  )
```

## 评估流程

1. **一次性环境准备**：首次运行带 **`--perform_emulator_setup`** 安装 App 与权限（详见仓库 README）。
2. **启动评测**：`python run.py --suite_family=android_world --agent_name=...`；可选 **`--tasks`** 子集、**`--n_task_combinations`**、**`--checkpoint_dir`** / 默认 **`--output_path`** 下由 **`checkpointer_lib.create_run_directory`** 生成运行目录。
3. **套件调度**：**`suite_utils.run`** → **`_run_task_suite`**：按 **`{task_template}{INSTANCE_SEPARATOR}{instance_id}`** 识别实例（**`INSTANCE_SEPARATOR` 为 `'_'`**，见 `checkpointer.py`）；若 checkpoint 中该实例已成功且无失败记录则 **skip**。
4. **单实例**：**`_run_task`**：**`initialize_task`** → **`run_episode`**（见上）→ **`is_successful(env)`** → 若异常则 **`_create_failed_result`** 并 **skip 后续**（不中断整 suite）→ 正常则 **`tear_down`**。
5. **断点语义**：**`IncrementalCheckpointer`** 在 **`save_episodes`** 中落盘；**`run` 的 docstring** 说明：恢复时以「**最后一个完整完成的 task template**」为粒度，且**同一模板下所有参数实例跑完才会提交该模板的一批数据**（具体见 `suite_utils.run` 注释）。
6. **汇总**：运行过程中持续 **`process_episodes` 打印**；可用仓库内脚本对 checkpoint 再分析或可视化。

## 防污染机制

- **动态参数**降低对单一指令记忆的依赖；但并非时间切分型基准，**不**等价于 LiveBench 类防泄漏设计。
- 与 OSWorld 类似，**外部 App 版本与网络**仍可能带来漂移。

## 已知局限

1. **环境重**：Android Studio、AVD、ADB、首次 setup 与 GPU/ARM Docker 问题（Apple Silicon 上 Docker 内嵌模拟器尤慢）。
2. **Agent 必须 `done`**：环境已达标但 Agent 未停会被记失败，对比不同 Agent 实现时需理解该语义。
3. **第三方 App / 账号**：部分任务依赖商店安装或账号，未 setup 会导致失败或跳过。
4. **可比性**：`n_task_combinations`、step budget、是否 MiniWoB 子集未对齐时，横向对比意义有限。

## 当前 SOTA

- 官网摘要写明论文内建 Agent **M3A** 在 AndroidWorld 上约 **30.6%** 任务成功率，并强调动态参数会显著改变难度（见 [项目首页](https://google-research.github.io/android_world/)）。
- **公开提交分数**以首页指向的 **[Google 表格 Leaderboard](https://docs.google.com/spreadsheets/d/1cchzP9dlTZ3WXQTfYNhh3avxoLipqHN75v1Tb86uhHo/edit?gid=0#gid=0)** 为准；对比时固定 **suite_family、n_task_combinations、任务子集、Agent 名称与步数预算口径**。

## 源码关键片段

**成功判定：`is_successful` 与 `interaction_results.done` 同时约束**：

```261:276:repos/android_world/android_world/suite_utils.py
    agent_successful = task_successful if interaction_results.done else 0.0
    _log_and_print(
        '%s; %s',
        'Task Successful ✅' if agent_successful > 0.5 else 'Task Failed ❌',
        f' {task.goal}',
    )

    if demo_mode:
      _display_success_overlay(env.controller, agent_successful)

    result = {
        constants.EpisodeConstants.GOAL: task.goal,
        constants.EpisodeConstants.TASK_TEMPLATE: task.name,
        constants.EpisodeConstants.EPISODE_DATA: interaction_results.step_data,
        constants.EpisodeConstants.IS_SUCCESSFUL: agent_successful,
```

**评测入口：`run.py` 中创建 suite 并 `suite_utils.run`**（节选）：

```197:243:repos/android_world/run.py
def _main() -> None:
  """Runs eval suite and gets rewards back."""
  env = env_launcher.load_and_setup_env(
      console_port=_DEVICE_CONSOLE_PORT.value,
      emulator_setup=_EMULATOR_SETUP.value,
      adb_path=_ADB_PATH.value,
  )

  n_task_combinations = _N_TASK_COMBINATIONS.value
  task_registry = registry.TaskRegistry()
  suite = suite_utils.create_suite(
      task_registry.get_registry(family=_SUITE_FAMILY.value),
      n_task_combinations=n_task_combinations,
      seed=_TASK_RANDOM_SEED.value,
      tasks=_TASKS.value,
      use_identical_params=_FIXED_TASK_SEED.value,
  )
  suite.suite_family = _SUITE_FAMILY.value

  agent = _get_agent(env, _SUITE_FAMILY.value)

  if _SUITE_FAMILY.value.startswith('miniwob'):
    # MiniWoB pages change quickly, don't need to wait for screen to stabilize.
    agent.transition_pause = _MINIWOB_TRANSITION_PAUSE
  else:
    agent.transition_pause = None

  if _CHECKPOINT_DIR.value:
    checkpoint_dir = _CHECKPOINT_DIR.value
  else:
    checkpoint_dir = checkpointer_lib.create_run_directory(_OUTPUT_PATH.value)

  print(
      f'Starting eval with agent {_AGENT_NAME.value} and writing to'
      f' {checkpoint_dir}'
  )
  suite_utils.run(
      suite,
      agent,
      checkpointer=checkpointer_lib.IncrementalCheckpointer(checkpoint_dir),
      demo_mode=False,
  )
  print(
      f'Finished running agent {_AGENT_NAME.value} on {_SUITE_FAMILY.value}'
      f' family. Wrote to {checkpoint_dir}.'
  )
  env.close()
```

## `repos/` 与 `.gitignore`

- 推荐路径：`repos/android_world`。根目录 **`.gitignore` 已忽略 `repos/`**，克隆仅供本地对照，不进入版本库。
