# Benchmark 常见问题与陷阱

## 来源

综合自 BetterBench、BENCHMARK²、Agentic Benchmark Checklist (ABC) 等元分析框架。

---

## 1. 数据污染 (Data Contamination)

### 问题
模型训练数据中包含 benchmark 的测试数据，导致分数虚高。

### 典型案例
- **SWE-bench Verified**：OpenAI 发现训练数据包含相关 GitHub PR，弃用该 benchmark
- **HumanEval/MBPP**：LiveCodeBench 检测到 GPT-4O、DeepSeek 等模型的污染

### 应对策略
| 策略 | 代表 Benchmark | 原理 |
|------|----------------|------|
| 时间分割 | LiveCodeBench | 仅使用训练截止日期后的题目 |
| 持续更新 | SWE-bench Live | 定期添加新题目 |
| 私有数据集 | SWE-bench Pro | 部分仓库不公开 |
| GUID/Canary | BetterBench 建议 | 在数据中嵌入标识字符串 |

---

## 2. 评估饱和 (Benchmark Saturation)

### 问题
前沿模型分数接近天花板，benchmark 失去区分能力。

### 典型案例
- **HumanEval**：pass@1 > 95%
- **MBPP**：类似饱和
- **SWE-bench Verified**：分数膨胀至 70%+

### 诊断方法
- BENCHMARK² 的 **Discriminability Score (DS)**：DS 低则已饱和
- 观察新模型间的分数差距是否收窄

### 应对策略
- 推出更难的新 benchmark（Polyglot 替代 Python-only）
- 增加任务复杂度（SWE-bench → SWE-bench Pro）
- 多维度评估（LiveCodeBench 的 4 个 scenario）

---

## 3. 性能高估 (Performance Overestimation)

### 问题 (ABC 框架发现)

Benchmark 设计缺陷导致高估 Agent 实际能力，偏差可达 **100%**。

### 典型案例
- **SWE-bench Verified**：测试用例不充分，24% 的排行榜前 50 名位置不准确
- **τ-bench**：将空响应计为成功，尤其在"故意不可能"的任务上（如更改不可退票的机票）

### ABC 框架的三个核心检查点

1. **Task Validity（任务有效性）**
   - 防止评估捷径（trivial exploits）
   - 验证 ground-truth 标注正确性
   - 确保环境隔离
   - 指定所有工具版本和依赖

2. **Outcome Validity（结果有效性）**
   - 确保成功判定准确反映实际能力
   - 避免过松或过严的评估标准

3. **Transparent Reporting（透明报告）**
   - 要求定量文档支持 benchmark 声明
   - 公开评估方法的所有细节

### 实际影响
- 应用 ABC 到 CVE-Bench 后，性能高估减少了 **33%**

---

## 4. 测试用例不足 (Insufficient Test Cases)

### 问题
测试覆盖率不够，模型可以通过"巧合"通过测试而非真正解决问题。

### 表现
- Patch 通过了所有测试但实际上没有正确解决问题
- 测试仅覆盖 happy path，忽略边界条件

### 应对策略
- 人工审核测试用例（SWE-bench Verified 的初衷）
- 增加 pass-to-pass 回归测试数量
- 使用多层次评估（resolved + file/node retrieval，如 SWE-PolyBench）

---

## 5. 单一指标偏差 (Single Metric Bias)

### 问题
仅使用一个指标（如 resolve rate）可能掩盖模型的真实能力分布。

### 应对策略
- 多维度评估：LiveCodeBench 的 4 个 scenario
- 多粒度指标：SWE-PolyBench 的 resolved + file retrieval + node retrieval
- BFCL 的加权多维度评分

---

## 6. 环境不可复现 (Environment Irreproducibility)

### 问题
评估环境差异导致同一模型的分数不一致。

### 表现
- Docker 版本差异
- 依赖包版本不匹配
- 操作系统差异（x86_64 vs arm64）

### 应对策略
- 预构建 Docker 镜像（SWE-bench Pro 的 Docker Hub）
- 锁定依赖版本
- SWE-bench 的三层 Docker 镜像缓存策略

---

## 7. 评估成本过高 (Prohibitive Evaluation Cost)

### 问题
完整评估一次的时间和资源成本过高，限制了 benchmark 的广泛使用。

### 典型数据
- SWE-bench：需 120GB+ 磁盘、16GB RAM、8 核 CPU
- WebArena：需自托管 7 个 Web 服务
- GAIA：需要 Web 浏览和多种工具访问

### 应对策略
- 提供 Lite/采样子集（SWE-bench Lite 300 题）
- 云端评估（SWE-bench 的 Modal 支持）
- 预构建环境镜像

---

## 8. 统计显著性缺失

### 问题 (BetterBench 发现)
大多数 benchmark 不报告结果的统计显著性，无法判断分数差异是否有意义。

### 应对策略
- 报告置信区间
- 多次运行取平均（τ-bench 的 Pass^k）
- 注明样本量和方差
