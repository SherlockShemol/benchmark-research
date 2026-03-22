# BENCHMARK² 质量指标

## 基本信息

| 项目 | 内容 |
|------|------|
| 名称 | BENCHMARK² (BENCHMARK-squared) |
| 论文 | [arxiv.org/pdf/2601.03986](https://arxiv.org/pdf/2601.03986) |

## 框架目标

提出三个互补的**定量指标**来系统性评估 benchmark 的质量，从统计学角度衡量 benchmark 的可靠性和有效性。

## 三个核心指标

### 1. Cross-Benchmark Ranking Consistency (CBRC) — 跨 Benchmark 排名一致性

**定义**：衡量一个 benchmark 产生的模型排名是否与同类 benchmark 的排名一致。

**原理**：
- 如果两个 benchmark 声称测试相同能力，它们应该产生相似的模型排名
- CBRC 高 → benchmark 的排名与 "共识" 一致
- CBRC 低 → benchmark 可能有系统性偏差

**用途**：检测某个 benchmark 是否是 "outlier"（与同类 benchmark 不一致）

### 2. Discriminability Score (DS) — 区分度

**定义**：量化一个 benchmark 区分不同模型能力的能力。

**原理**：
- DS 高 → benchmark 能有效区分强弱模型
- DS 低 → 模型得分趋于一致（可能已饱和）

**用途**：检测 benchmark 是否已饱和（如 HumanEval）

### 3. Capability Alignment Deviation (CAD) — 能力对齐偏差

**定义**：识别出"强模型失败但弱模型成功"的异常实例。

**原理**：
- CAD 高 → 存在大量"反直觉"结果
- 可能原因：数据污染、题目缺陷、评估噪音

**用途**：识别有问题的具体测试实例

## 与 BetterBench 的关系

| 维度 | BetterBench | BENCHMARK² |
|------|-------------|------------|
| 分析层面 | 定性 checklist | 定量指标 |
| 评估对象 | benchmark 设计与文档 | benchmark 实际表现 |
| 输入 | 论文 + 代码 | 模型在 benchmark 上的分数 |
| 应用时机 | 设计时/选择时 | 结果分析时 |

## 实际应用

1. 用 CBRC 检查新 benchmark 是否与已有 benchmark 一致
2. 用 DS 监控 benchmark 是否需要退役（饱和）
3. 用 CAD 找出有问题的测试实例并清理
