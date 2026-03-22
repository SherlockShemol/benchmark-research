# OSWorld

## 基本信息

| 项目 | 内容 |
|------|------|
| 名称 | OSWorld |
| 来源 | xlang-ai / 多机构 |
| 论文 | [OSWorld: Benchmarking Multimodal Agents for Open-Ended Tasks in Real Computer Environments](https://arxiv.org/abs/2404.07972)（NeurIPS 2024 Datasets & Benchmarks） |
| 项目页 | [os-world.github.io](https://os-world.github.io/) |
| GitHub | [github.com/xlang-ai/OSWorld](https://github.com/xlang-ai/OSWorld) |
| 本地源码 | `repos/OSWorld/`（浅克隆，用于对照 `show_result.py` 等） |

## 评估目标

评测**多模态 GUI Agent** 在 **真实桌面环境**（Ubuntu / Windows 等虚拟机）中完成开放式任务的能力：跨应用操作、办公套件、浏览器、文件与系统设置等，强调**可执行环境与屏幕观测**（截图 / 可访问性树等），而非仅文本规划。

## 任务构造

- **规模**：论文与早期发布约 **369** 条任务；部分任务（如部分 Google Drive 相关）需额外账号配置，社区常报告可评子集略小（具体以官方 `test_all.json` 与 Setup Guideline 为准）。
- **领域**：含 **Chrome、LibreOffice 套件、GIMP、VS Code、Thunderbird、VLC、系统与多应用组合（multi_apps）** 等 domain。
- **环境**：通过 `DesktopEnv` 驱动 **VMware / VirtualBox / Docker（需 KVM）/ AWS** 等 provider；任务含初始 VM 状态与配置说明。

## 评估指标

### 核心：Success Rate（样本均值）

- 每个任务执行结束后写入 **`result.txt`**，内容为 **0～1 的浮点得分**（全对为 1）或可由 `float()` / `eval(result)` 解析的表达式；部分任务支持**连续分**而非纯 0/1。
- 汇总脚本 **`show_result.py`** 遍历 `result_dir/{action_space}/{observation_type}/{model}/{domain}/{example_id}/result.txt`，将所有样本得分收集到 `all_result`，再：

```99:101:repos/OSWorld/show_result.py
        print("Runned:", len(all_result), "Current Success Rate:",
              round(sum(all_result) / len(all_result) * 100, 2), "%",
              f"{round(sum(all_result), 2)}", "/", str(len(all_result)))
```

- 即 **Overall Success Rate（%）= sum(scores)/n×100**；`--detailed` 按固定 domain 顺序输出 `合计分/任务数`。

### 单文件读取的容错（注意异质格式）

```34:54:repos/OSWorld/show_result.py
                    if "result.txt" in os.listdir(example_path):
                        if domain not in domain_result:
                            domain_result[domain] = []
                        result = open(os.path.join(example_path, "result.txt"), "r").read()
                        try:
                            domain_result[domain].append(float(result))
                        except:
                            domain_result[domain].append(float(eval(result)))
                        ...
                        try:
                            result = open(os.path.join(example_path, "result.txt"), "r").read()
                            try:
                                all_result.append(float(result))
                            except:
                                all_result.append(float(bool(result)))
                        except:
                            all_result.append(0.0)
```

### 与 WebArena 的差异（勿混淆）

- **WebArena**：多在自托管 Web 站点上，用 **URL / HTML / 字符串** 等 evaluator **乘积**判定。
- **OSWorld**：在 **真实 OS + 应用 GUI** 上，依赖任务 JSON 里的 **`evaluator` / `metric` / `result_getter`**，由 **`DesktopEnv.evaluate()`** 在 VM 内拉取状态并计算 **0～1（或连续分）**，再经 **`lib_run_single`** 写入 **`result.txt`**。

**`evaluate()` 核心逻辑（单指标 / 多指标）**：先执行 **`postconfig`**（评测前环境收尾配置）；若 `func == "infeasible"` 则与 Agent 是否显式 **FAIL** 联动；否则通过 **`result_getter`** 从环境取 **result_state**，可选与 **expected** 比较后调用注册的 **metric** 函数。多指标时支持 **`metric_conj`** 为 **`and` / `or`**，或返回 **均值 / max**（见下段节选）。

```429:495:repos/OSWorld/desktop_env/desktop_env.py
    def evaluate(self):
        """
        Evaluate whether the task is successfully completed.
        """

        postconfig = self.evaluator.get("postconfig", [])
        self.setup_controller.setup(postconfig, self.enable_proxy)
        ...
        if type(self.metric) == list:
            # Multiple metrics to evaluate whether the task is successfully completed
            ...
            return sum(results) / len(results) if self.metric_conj == 'and' else max(results)
        else:
            # Single metric to evaluate whether the task is successfully completed
            ...
                metric: float = self.metric(result_state, **self.metric_options)

        return metric
```

## 评估流程

### 单题闭环（`run.py` + `lib_run_single`）

1. **配置**：`run.py` 从 `evaluation_examples/test_all.json`（或 `--test_all_meta_path`）读取各 `domain` 与 `example_id`，再加载 `evaluation_examples/examples/{domain}/{example_id}.json` 作为 **`task_config`**。
2. **目录**：每题结果写入  
   `result_dir / action_space / observation_type / model / domain / example_id/`（见 `run.py` 中 `example_result_dir` 拼接）。

```184:203:repos/OSWorld/run.py
            example_result_dir = os.path.join(
                args.result_dir,
                args.action_space,
                args.observation_type,
                args.model,
                domain,
                example_id,
            )
            os.makedirs(example_result_dir, exist_ok=True)
            # example start running
            try:
                lib_run_single.run_single_example(
                    agent,
                    env,
                    example,
                    max_steps,
                    instruction,
                    args,
                    example_result_dir,
                    scores,
                )
```

3. **交互与评测**：**`lib_run_single.run_single_example`**：**`env.reset(task_config=example)`** → **`agent.reset(..., vm_ip=env.vm_ip)`** → **`sleep(60)`** 等待就绪 → **`start_recording()`** → 在 **`step_idx < max_steps` 且未 `done`** 时循环 **`agent.predict(instruction, obs)`**，对 **`actions`** 逐个 **`env.step`**，同步写 **逐步 PNG** 与 **`traj.jsonl`** → 退出循环后 **`sleep(20)`** → **`env.evaluate()`** → **`result.txt`**、**`log_task_completion`**、**`end_recording(..., recording.mp4)`**。

```12:72:repos/OSWorld/lib_run_single.py
def run_single_example(agent, env, example, max_steps, instruction, args, example_result_dir, scores):
    runtime_logger = setup_logger(example, example_result_dir)

    # Reset environment first to get fresh VM IP
    env.reset(task_config=example)

    # Reset agent with fresh VM IP (for snapshot reverts)
    try:
        agent.reset(runtime_logger, vm_ip=env.vm_ip)
    except Exception as e:
        agent.reset(vm_ip=env.vm_ip)
    
    time.sleep(60) # Wait for the environment to be ready
    obs = env._get_obs() # Get the initial observation
    done = False
    step_idx = 0
    env.controller.start_recording()
    while not done and step_idx < max_steps:
        response, actions = agent.predict(
            instruction,
            obs
        )
        for action in actions:
            # Capture the timestamp before executing the action
            action_timestamp = datetime.datetime.now().strftime("%Y%m%d@%H%M%S%f")
            logger.info("Step %d: %s", step_idx + 1, action)
            obs, reward, done, info = env.step(action, args.sleep_after_execution)

            logger.info("Reward: %.2f", reward)
            logger.info("Done: %s", done)
            # Save screenshot and trajectory information
            with open(os.path.join(example_result_dir, f"step_{step_idx + 1}_{action_timestamp}.png"),
                      "wb") as _f:
                _f.write(obs['screenshot'])
            with open(os.path.join(example_result_dir, "traj.jsonl"), "a") as f:
                f.write(json.dumps({
                    "step_num": step_idx + 1,
                    "action_timestamp": action_timestamp,
                    "action": action,
                    "response": response,
                    "reward": reward,
                    "done": done,
                    "info": info,
                    "screenshot_file": f"step_{step_idx + 1}_{action_timestamp}.png"
                }))
                f.write("\n")
            if done:
                logger.info("The episode is done.")
                break
        step_idx += 1
    time.sleep(20) # Wait for the environment to settle
    result = env.evaluate()
    logger.info("Result: %.2f", result)
    scores.append(result)
    with open(os.path.join(example_result_dir, "result.txt"), "w", encoding="utf-8") as f:
        f.write(f"{result}\n")
    
    # Log task completion to results.json
    log_task_completion(example, result, example_result_dir, args)
    
    env.controller.end_recording(os.path.join(example_result_dir, "recording.mp4"))
```

**`run.py` 默认 `max_steps`**：CLI **`--max_steps`** 默认为 **15**（见 `repos/OSWorld/run.py` **`config()`**），与部分二手文档中的「30 步」可能不一致。

4. **并行/多 Agent**：官方推荐以 `scripts/python/run_multienv.py` 或 `run_multienv_<agent>.py` 批量跑；**未完成题**可通过 `run.py` 的 **`get_unfinished`** 依据「目录下是否存在 `result.txt`」筛除（无 `result.txt` 时会清空该 example 目录以便重跑）。

### 操作清单（与 README / 官网一致）

1. **环境**：按 README 安装依赖、准备 VM 或 Docker/AWS；配置 Google 账号、代理等（否则部分任务失败拉低分）。
2. **Agent**：实现 [`mm_agents` 接口](https://github.com/xlang-ai/OSWorld/blob/main/mm_agents/README.md)，在 `run.py` 或 `scripts/python/run_multienv*.py` 中接入；指定 `observation_type`、`action_space`、`max_steps` 等。
3. **运行**：在 headless/并行模式下执行全量或子集任务，结果写入 `result_dir`（含截图、动作日志、录像等）。
4. **计分**：`python show_result.py --action_space ... --model ... --observation_type ... --result_dir ...`；`--detailed` 输出各 domain 的 `得分合计/任务数`。

### 公开榜单与可复现

- **官网** [os-world.github.io](https://os-world.github.io/) 展示模型结果；**OSWorld-Verified**（2025-07 起大更新，修 issue、增强 AWS 并行等）见 [xlang.ai blog](https://xlang.ai/blog/osworld-verified)，结果以**最新官网榜单**为准。
- **Verified 上榜**：README 说明需联系维护方在官方环境复现或提交可追溯轨迹（防自报作弊）。

## 防污染机制

- **无静态题集加密**；依赖任务多样性与环境交互。
- **OSWorld-Verified** 通过修复与统一评测流程，提升**跨实验室可比性**；与「训练集泄漏」问题正交，仍需结合披露设置理解榜单。

## 已知局限

1. **环境成本极高**：VM/Docker/AWS、下载镜像与并行调参门槛高。
2. **外部依赖**：Google 账号、代理、网络与站点变更会导致任务失败或漂移。
3. **评分异质**：任务间 0/1 与连续分混用，`eval`/bool 回退路径使异常字符串可能被记为 0 或非预期值；解读 overall 时需看 domain breakdown。
4. **自评 vs 官方验证**：非 Verified 流程下自跑分数与官网 Verified 列可能不可直接对比。

## 当前 SOTA

- **人类基线**：论文与 [官网](https://os-world.github.io/) 均引用约 **72.36%** overall success（以最新说明为准）。
- **模型**：2024 论文中最佳系统约 **12.24%**（旧表）；**OSWorld-Verified**（2025-07 起大更新：修样例、AWS 并行、统一协议）后，**官网 Verified 榜**上强 **Computer-use / Agentic** 方案可显著高于旧论文数字；**具体名次与分数以 [os-world.github.io](https://os-world.github.io/) 动态表格为准**（页面数据由 JS 加载，勿与摘要文字混用）。
- **361 vs 369**：官网说明 **8 道 Google Drive** 相关题可手动配通或**官方允许排除**，按 **361 题** 汇报时需在文中注明。

## `repos/` 与 `.gitignore`

- 推荐路径：`repos/OSWorld/`。根目录 `.gitignore` 已忽略整个 **`repos/`**，clone 不进入版本库。

```bash
git clone https://github.com/xlang-ai/OSWorld.git repos/OSWorld
```
