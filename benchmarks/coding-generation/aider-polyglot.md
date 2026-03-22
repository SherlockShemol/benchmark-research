# Aider Polyglot Benchmark

## 基本信息

| 项目 | 内容 |
|------|------|
| 名称 | Aider Polyglot Benchmark |
| 来源 | Aider-AI |
| 博客 | [aider.chat/2024/12/21/polyglot.html](https://aider.chat/2024/12/21/polyglot.html) |
| GitHub | [github.com/Aider-AI/polyglot-benchmark](https://github.com/Aider-AI/polyglot-benchmark) |
| 排行榜 | [aider.chat/docs/leaderboards](https://aider.chat/docs/leaderboards/) |
| 本地源码 | `repos/aider-polyglot/`（**练习语料**）；harness 在 **`repos/aider/benchmark/`**（需自行 `git clone https://github.com/Aider-AI/aider.git repos/aider`，`repos/` 已在 `.gitignore`） |
| 评测入口（上游） | 主脚本为 [`benchmark/benchmark.py`](https://github.com/Aider-AI/aider/blob/main/benchmark/benchmark.py)（Typer CLI）；官方说明见 [`benchmark/README.md`](https://github.com/Aider-AI/aider/blob/main/benchmark/README.md) |

## 评估目标

评估 **Aider 编辑器 + LLM** 联合的代码编辑能力，覆盖 6 种编程语言。重点测试模型在多语言环境下生成和编辑代码的能力。

## 任务构造

### 数据来源
- 基于 **Exercism** 编程练习平台
- 6 种语言的 track：C++, Go, Java, JavaScript, Python, Rust

### 难度筛选（独创方法）

1. 7 个模型在全部 697 个练习上预跑
2. 仅保留 **≤3 个模型能解出** 的 225 个练习

| 解出模型数 | 题目数 | 累计 |
|-----------|--------|------|
| 0 | 66 | 66 |
| 1 | 61 | 127 |
| 2 | 50 | 177 |
| 3 | 48 | 225 |

### 各语言练习数量

| 语言 | 练习数 |
|------|--------|
| C++ | 26 |
| Go | 39 |
| Java | 47 |
| JavaScript | 49 |
| Python | 34 |
| Rust | 30 |
| **合计** | **225** |

### 每个练习结构

```
exercise-name/
├── .docs/
│   ├── introduction.md
│   ├── instructions.md
│   └── instructions.append.md
├── .meta/
│   ├── config.json          # solution/test/example 文件定义
│   └── example.*            # 参考实现（LLM 不可见）
├── <solution_files>          # 待实现
└── <test_files>              # 单元测试
```

## 评估指标

### 核心指标：通过率 `pass_rate_*`

汇总逻辑在 **`summarize_results()`**（读取各题目录下 `.aider.results.json` 中的 `tests_outcomes` 列表）：

- **`pass_rate_1`**：首轮编辑后单测即全过的练习占比（仅统计 **`completed_tests`** 已完成题）。
- **`pass_rate_2`**（默认 `--tries=2`）：两轮内**曾经**全测通过的占比：首轮失败、次轮才过的题**只**计入 `pass_rate_2`，不计入 `pass_rate_1`。
- 公式：`pass_rate_j = 100 * pass_num_j / completed_tests`（与上游打印一致）。

`--tries` 可大于 2，此时会有 `pass_rate_3` …（视运行输出而定）。

### 辅助指标
- `percent_cases_well_formed`：编辑格式正确率
- `syntax_errors`：语法错误次数
- `test_timeouts`：测试超时次数
- `total_cost`：API 调用总成本
- `seconds_per_case`：每题平均耗时

## 评估流程

### 仓库分工（避免混淆）

- **`repos/aider-polyglot/`**：仅含各语言 **Exercism 风格练习目录**（`.meta/config.json`、测试与说明），**不包含**发起模型调用、重试、计分的 Python harness。
- **官方 harness**：**Aider** 仓库的 **`benchmark/`**。推荐按 [benchmark README](https://github.com/Aider-AI/aider/blob/main/benchmark/README.md)：`tmp.benchmarks/polyglot-benchmark` 下放语料副本，Docker 内 `pip install -e .[dev]` 后执行 **`./benchmark/benchmark.py`**。

### Docker 与门禁

- 上游在 **`benchmark/benchmark.py`** 中要求环境变量 **`AIDER_DOCKER`**：若未设置，会打印警告并 **`return`**，**不会**进入实际跑题逻辑（避免在非容器环境执行模型生成的未审核代码）。
- 推荐流程：`docker_build.sh` 构建镜像 → `docker.sh` 进入容器 → 在容器内安装 aider 再跑 `benchmark.py`（详见 README）。

### CLI 示例（与上游 README 一致）

```bash
./benchmark/benchmark.py RUN_NAME --model gpt-3.5-turbo --edit-format whole --threads 10 --exercises-dir polyglot-benchmark
```

常用参数：`--tries` / `-r`（每题最多尝试轮数，默认 2）、`--num-tests` / `-n`、`--keywords` / `-k`、`--languages` / `-l`、`--stats` 仅对已跑完的目录汇总 YAML 风格统计。

### 各语言测试命令（`run_unit_tests` 内）

在 **Docker 镜像**中，JS/C++ 使用镜像内绝对路径（本地裸跑需自行对齐路径）。下列摘录在 clone **`repos/aider`** 后对应 `benchmark/benchmark.py`（与 [GitHub `main`](https://github.com/Aider-AI/aider/blob/main/benchmark/benchmark.py) 行号一致）：

```985:992:repos/aider/benchmark/benchmark.py
TEST_COMMANDS = {
    ".py": ["pytest"],
    ".rs": ["cargo", "test", "--", "--include-ignored"],
    ".go": ["go", "test", "./..."],
    ".js": ["/aider/benchmark/npm-test.sh"],
    ".cpp": ["/aider/benchmark/cpp-test.sh"],
    ".java": ["./gradlew", "test"],
}
```

单测子进程超时默认 **180s**（`timeout = 60 * 3`），工作目录为各题拷贝后的 `testdir`。

### 单题流程

```
1. 从 config.json 读 solution/test 文件
2. 恢复 solution 文件到初始版本
3. 构造 prompt（introduction + instructions + addendum）
4. 用 Aider Coder 调用 LLM 修改 solution 文件
5. 运行对应语言的测试命令
6. 失败时追加错误信息，重试（默认 2 轮）
```

### 特殊处理
- **JavaScript**：由 `npm-test.sh` 包装（容器内路径 `/aider/benchmark/npm-test.sh`）；常见逻辑含依赖与测试名替换（见上游脚本）。
- **Java**：`run_unit_tests` 在跑 Gradle 前用正则去掉测试文件中的 `@Disabled(...)` 行。
- **重试循环**：每轮调用 Aider `Coder.run` 应用编辑；若仍有测试失败，把测试输出拼进下一轮 `instructions`（见 `prompts.test_failures`）；**任一轮全过则 `break`**，不再用尽 `tries`。

### 源码关键片段（`repos/aider/benchmark/benchmark.py`）

**`AIDER_DOCKER` 门禁**：

```252:254:repos/aider/benchmark/benchmark.py
    if "AIDER_DOCKER" not in os.environ:
        print("Warning: benchmarking runs unvetted code from GPT, run in a docker container")
        return
```

**结果目录与默认语料文件夹名**：

```33:36:repos/aider/benchmark/benchmark.py
BENCHMARK_DNAME = Path(os.environ.get("AIDER_BENCHMARK_DIR", "tmp.benchmarks"))

EXERCISES_DIR_DEFAULT = "polyglot-benchmark"
```

**`--tries` 与 `--exercises-dir`（`main()` 形参，节选）**：

```200:200:repos/aider/benchmark/benchmark.py
    tries: int = typer.Option(2, "--tries", "-r", help="Number of tries for running tests"),
```

```215:217:repos/aider/benchmark/benchmark.py
    exercises_dir: str = typer.Option(
        EXERCISES_DIR_DEFAULT, "--exercises-dir", help="Directory with exercise files"
    ),
```

**`pass_rate_*` 打印与写入 `SimpleNamespace`**：

```557:562:repos/aider/benchmark/benchmark.py
    for i in range(tries):
        pass_rate = 100 * passed_tests[i] / res.completed_tests
        percents[i] = pass_rate
        setattr(res, f"pass_rate_{i + 1}", f"{pass_rate:.1f}")
        setattr(res, f"pass_num_{i + 1}", passed_tests[i])
```

`passed_tests` 的更新见同文件 `summarize_results()` 中对 `tests_outcomes` 与「末轮是否通过」的处理（约 502–511 行）。

## 防污染机制

- 题目公开，无时间分割
- 依赖难度筛选提供区分度

## 已知局限

1. 与 Aider 工具深度绑定，评估的是 Aider+LLM 联合效果
2. 仅 225 题，规模较小
3. 难度筛选依赖预跑模型的选择
4. 无显式防污染机制

## 当前 SOTA

- 以 [Aider Polyglot 排行榜](https://aider.chat/docs/leaderboards/) 为准；比较时需注明 **模型名、`edit_format`、`--tries`、Aider `versions`、commit hash、是否在 Docker**。
- 截至近期页面快照，**Polyglot 全量 225 题**条目前列包括 **OpenAI `gpt-5`（high，`diff`）`pass_rate_2` ≈ 88%**、`gpt-5`（medium）**≈ 86.7%** 等；**具体名次与数值以官网实时数据为准**（榜单随新提交 PR 更新）。
