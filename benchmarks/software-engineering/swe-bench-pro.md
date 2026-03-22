# SWE-bench Pro

## 基本信息

| 项目 | 内容 |
|------|------|
| 名称 | SWE-bench Pro |
| 来源 | Scale AI |
| 论文 | [openreview.net/forum?id=9R2iUHhVfr](https://openreview.net/forum?id=9R2iUHhVfr) |
| GitHub | [github.com/scaleapi/SWE-bench_Pro-os](https://github.com/scaleapi/SWE-bench_Pro-os) |
| 数据集 | `ScaleAI/SWE-bench_Pro` (HuggingFace) |
| 排行榜 | [scale.com/leaderboard/swe_bench_pro_public](https://scale.com/leaderboard/swe_bench_pro_public) |
| 本地源码 | `repos/swe-bench-pro/` |

## 评估目标

评估 AI Agent 在**长时间跨度、多文件**软件工程任务上的能力。相比 SWE-bench，问题更复杂，覆盖更多仓库和语言。

## 任务构造

### 四阶段问题创建流程

1. **Sourcing**：选择 41 个活跃维护仓库（含商业应用、B2B、开发工具；18 个私有仓库）
2. **Environment**：专业工程师构建可复现 Docker 环境，安装所有依赖和构建工具
3. **Harvesting**：从连续 commits 提取问题，要求：
   - (a) 修复 bug 或实现功能
   - (b) 有 fail-to-pass 测试转换
   - (c) 有 pass-to-pass 回归测试
4. **Augmentation**：人工整理元数据为 problem_statement + requirements + interface，3 轮人工审核

### 数据规模（官方拆分）

全量 **1,865** 题、**41** 仓库；子集划分见 [公开排行榜说明](https://scale.com/leaderboard/swe_bench_pro_public)：

| 子集 | 规模 | 说明 |
|------|------|------|
| **Public（公开榜）** | **731** | 强 copyleft（如 GPL）公开仓库，对外主榜 |
| **Private** | **276** | 合作方专有代码库，另榜 |
| **Held-out** | **858** | 与 Public 类似的 copyleft 公开仓，**不对外发榜** |

### 与原版 SWE-bench 的关键差异

| 维度 | SWE-bench | SWE-bench Pro |
|------|-----------|---------------|
| 规模 | 2,294 题、12 仓库 | **全量 1,865** 题、41 仓库；**公开榜子集 731** |
| 任务类型 | 单文件为主 | 多文件、长时间跨度 |
| 数据来源 | 仅公开仓库 | 公开 + 私有（18 个） |
| 人工校验 | 无 | 所有任务人工校验 |
| 问题描述 | 原始 issue | 增强的 problem_statement + requirements + interface |

## 评估指标

### 核心指标：Resolve Rate / Overall accuracy

官方脚本从 **`parser.py` 产出的 `output.json`** 读取测试列表，取 **`status == "PASSED"`** 的测试名集合 **`passed_tests`**；与样本元数据中的 **`fail_to_pass`**、**`pass_to_pass`**（字符串经 **`eval()`** 解析为集合）做**集合包含**判定：**`(f2p | p2p) <= passed_tests`**，即 **F2P 与 P2P 中的每一个测试名都必须出现在通过集合中**（等价于「全部相关测试 PASSED」）。

```554:559:repos/swe-bench-pro/swe_bench_pro_eval.py
                        passed_tests = {x["name"] for x in output["tests"] if x["status"] == "PASSED"}
                        f2p = set(eval(raw_sample["fail_to_pass"]))
                        p2p = set(eval(raw_sample["pass_to_pass"]))
                        result = (f2p | p2p) <= passed_tests
                        eval_results[instance_id] = result
```

**汇总**：逐 instance 布尔结果写入 **`eval_results.json`**，**Overall accuracy** 为 **`sum(eval_results.values()) / len(eval_results)`**（见同文件约 569–571 行）。

## 评估流程

### Docker 三层镜像架构

```
Instance Image (每个 instance)
    └── Base/Environment Image (每个 repo+version)
           └── Base OS Image (python:3.9-slim 等)
```

#### Base Dockerfile 示例
```dockerfile
FROM python:3.9-slim
RUN mkdir /app && WORKDIR /app
RUN git clone <repo_url> .
RUN git checkout <base_commit>
```

#### Instance Dockerfile 示例
```dockerfile
FROM base_{org}__{repo}___{date}.{commit}
RUN git reset --hard {instance_base_commit}
RUN pip install ... && python setup.py develop
```

### 评估执行流程

**入口脚本 `create_entryscript(sample)`**：从样本元数据取 **`base_commit`**、**`before_repo_set_cmd`**（取 strip 后**最后一行**）、**`selected_test_files_to_run`**（`eval` 后 join）；把 Base/Instance 两个 Dockerfile 里的 **`ENV`** 行转成 **`export`** 前缀写入脚本顶部；在容器内 **`cd /app`** 后 **`git reset/checkout`** → **`git apply -v /workspace/patch.diff`** → 执行 **`before_repo_set_cmd`** → **`bash /workspace/run_script.sh {tests}`** 重定向到 **`stdout.log`/`stderr.log`** → **`python /workspace/parser.py ... /workspace/output.json`**。

```95:127:repos/swe-bench-pro/swe_bench_pro_eval.py
def create_entryscript(sample):
    before_repo_set_cmd = sample["before_repo_set_cmd"].strip().split("\n")[-1]
    selected_test_files_to_run = ",".join(eval(sample["selected_test_files_to_run"]))
    base_commit = sample["base_commit"]
    base_dockerfile = load_base_docker(sample["instance_id"])
    instance_dockerfile = instance_docker(sample["instance_id"])

    # Extract ENV commands from dockerfiles
    env_cmds = []
    for dockerfile_content in [base_dockerfile, instance_dockerfile]:
        for line in dockerfile_content.split("\n"):
            line = line.strip()
            if line.startswith("ENV"):
                # Convert ENV commands to export statements
                env_cmd = line.replace("ENV", "export", 1)
                env_cmds.append(env_cmd)

    env_cmds = "\n".join(env_cmds)

    entry_script = f"""
{env_cmds}
# apply patch
cd /app
git reset --hard {base_commit}
git checkout {base_commit}
git apply -v /workspace/patch.diff
{before_repo_set_cmd}
# run test and save stdout and stderr to separate files
bash /workspace/run_script.sh {selected_test_files_to_run} > /workspace/stdout.log 2> /workspace/stderr.log
# run parsing script
python /workspace/parser.py /workspace/stdout.log /workspace/stderr.log /workspace/output.json
"""
    return entry_script
```

**高层流程**：

```
CSV + JSON patches
    → 对每个 instance（Modal 或本地 Docker）：
        1. 拉取预构建镜像（如 Docker Hub `jefzda/sweap-images:{tag}`）
        2. 写入 workspace：patch.diff、run_script.sh、parser.py、entryscript.sh
        3. bash entryscript.sh
        4. 读 output.json，按 F2P/P2P 判 resolved
    → 写 eval_results.json，打印 Overall accuracy
```

**并行**：**`ThreadPoolExecutor`**，**`max_workers=args.num_workers`**（见约 520–536 行）。**`--use_local_docker`** 时用 **`eval_with_docker`**，否则 **`eval_with_modal`**；Apple Silicon 上若未指定 **`--docker_platform`**，会尝试默认 **`linux/amd64`**（约 507–515、533 行）。

### 每个 Instance 的独立 Parser

因不同项目使用不同测试框架，每个 instance 有自己的 `parser.py`：
- **Ansible**：解析 pytest 输出 `[gw0] 100% PASSED test/...`
- **Tutanota**：解析 ospec 输出 `All N assertions passed`
- **OpenLibrary**：解析 pytest 的 `test::Class::method PASSED`

### 运行方式
- **Modal**（默认）：云端沙盒 + Docker Hub 镜像
- **本地 Docker**：`--use_local_docker` 参数

## 防污染机制

1. **许可与访问壁垒**：公开榜子集刻意选用 **GPL 等强 copyleft** 仓库，降低被专有训练语料收录的概率；另有 **私有子集**（合作方代码）进一步测泛化。
2. **Held-out**：大规模 copyleft 子集 **不公开发榜**，供内部/未来分析。
3. **人工增强**：问题描述经整理，不直接照搬原始 issue。

## 已知局限

1. 评估成本高（每个 instance 需独立 Docker 环境）
2. 四阶段 pipeline 的 Sourcing/Harvesting 代码未开源
3. 私有仓库部分无法公开验证

## 当前 SOTA 及人类基线

依据 [Scale SWE-Bench Pro Public Leaderboard](https://scale.com/leaderboard/swe_bench_pro_public)（页面注明：榜上非灰显条目为 **turn limit 250、成本无上限**；灰显为 **50 turn + 成本上限** 的历史跑法）：

- **Claude Opus 4.5**（`claude-opus-4-5-20251101`）：约 **45.89%**（±3.60 CI）
- **Claude 4.5 Sonnet**：约 **43.60%**
- **Gemini 3 Pro Preview**：约 **43.30%**
- **GPT-5（High 等配置）**：约 **41.78%** 量级

同一页面对比：**SWE-Bench Verified** 上多数前沿模型 **70%+**，而 **Pro 公开子集** 顶尖约 **23% 量级**（论文/页面叙述中的另一套跑法或 scaffold 口径，与当前榜前列 **40%+** 并存——对比时务必对齐 **agent scaffold、turn/cost 策略与榜单版本**）。

- **人类基线**：未在公开榜中作为单独条目给出。
