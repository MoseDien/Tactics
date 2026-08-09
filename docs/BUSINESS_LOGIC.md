# DailyTactics 业务逻辑

本文档描述当前的核心业务流程，不包含 SwiftUI 布局和具体实现细节。

## 0. 首次启动：一次性导入全部题库

App 第一次启动（或题库未导入时），先进行一次性批量导入：

- 从 `ios/DailyTactics/Resources/puzzles/` 下的 **全部 10 个等级 JSON**
  （`1000.json`–`1900.json`，每个 1000 题）读取并写入 SwiftData。
- 整个过程显示一个 Loading 页面和进度，导入完成后翻起
  `LibraryStateStore`（UserDefaults `dailytactics.libraryImported`）标志位。
- 导入是幂等的：按 `puzzleId` 去重，重复运行不会插入重复题目。
- 这个 gate 独立于 Rating Assessment，之后每次启动都跳过导入，直接进入后续流程。

题目 JSON 由 `tools/export_tier_puzzles.py` 从 `data/source/lichess_puzzles.sqlite`
按 100 分 Rating 区间抽样生成（可复现）。

## 1. Rating Assessment：建立用户 baseline rating

题库导入完成后，若尚未完成评估，进入 Rating Assessment。

### 题目来源

- 从 `ios/DailyTactics/Resources/puzzles/rating_puzzles.json`（100 道、覆盖宽 Rating 范围）
  读取评估题集合。
- 按难度分布随机抽取评估题；当前评估题数量为 4 道（参数可调）。

### 评估规则

- 每道题只允许第一次尝试。
- 第一次答对，记录为成功。
- 第一次答错，立即记录为失败并进入下一题。
- 评估过程中显示当前执棋方、题目进度和成功/失败列表。

### baseline rating

完成所有评估题后，根据题目平均难度和用户答对比例计算 baseline rating。

用户会看到包含具体 Rating 数值的确认弹窗。用户点击确认后：

1. 通过 `RatingAssessmentStore` 保存 baseline rating 和评估完成状态。
2. 通过 `UserRatingStore` 写入当前 Rating。
3. 进入 Daily Tactics。

> 注意：评估**不再导入任何等级题库**——题库已在首次启动时一次性全部导入。
> 如果用户没有确认，评估完成状态不会写入，下一次启动仍会继续评估流程。

## 2. 题库组织

题库文件按 100 分 Rating 区间组织（`1000.json`–`1900.json`），但这只是**导入时的数据分片**，
运行时不再按等级筛选或切换题库。10 个文件在首次启动时全部写入 SwiftData，总量约 10000 题。

不再有「用户当前等级」或「跨等级导入」的概念。

## 3. Daily Tactics

进入主训练后，题目来自 SwiftData。

### Round

- 每个 round 默认包含 5 道题。
- 题目从整个题库中**随机选择尚未尝试过的** 5 道（不按 Rating 区间筛选，难度混合）。
- **查询数据库只在 round 开始时发生一次**：round 1 在进入 Tactics 时查询，
  后续 round 在用户点击「Start over」时查询。一个 round 进行中不再访问数据库。
- 当未做过的题目不足 5 道时，回退为从全部题目中随机选择。

### 单题流程

1. 系统先自动执行 Lichess puzzle line 的第一步机器走子。
2. 用户尝试自己的应对着法。
3. 答错时显示错误反馈，允许继续尝试。
4. 答对后自动执行对手回复，直到题目完成。
5. 题目完成后保存进度和 Rating 结果。

## 4. Puzzle 数据和完成标记

SwiftData 中使用两个概念保存用户状态：

- `PuzzleRecord`：题目本身，包括 FEN、走法、Rating 和主题。
- `PuzzleProgress`：用户对题目的运行时状态（是否尝试、是否完成、是否失败）。

每道题第一次被用户尝试时，会在 `PuzzleProgress` 中标记 `isAttempted`。
Round 选择时优先排除已尝试的题目。

## 5. Rating 更新规则（Elo 风格，K=32）

### 只对首次有效尝试更新 Rating

- 题目之前没有被尝试过，并且第一次尝试答对：根据 Elo 风格规则更新 Rating。
- 题目第一次尝试答错：标记为已尝试；即使之后答对，也不再修改 Rating。
- 使用 Hint 即视为放弃，立即按失败结算并扣分。
- 题目之前已经做过：无论本次答对或答错，都不再修改 Rating。

Rating 是一个本地训练分数，不再是 Lichess 官方 Rating，也不再驱动题库切换。

### 题目完成状态

即使该题不再影响 Rating，题目仍会记录完成状态和失败状态，用于历史进度。

## 6. Settings：重新评估 baseline rating

用户可以在 Settings 中主动重新评估 baseline rating。

确认后：

- 通过 `resetProgress()` 清除 SwiftData 中的题目进度 `PuzzleProgress`
  （题目重新变为「未尝试」，但**保留已导入的题库 `PuzzleRecord`**，避免重新导入万级数据）。
- 重置 Rating Assessment 完成状态。
- 重置已保存的 Rating。

`LibraryStateStore` 标志位保持为 true（题库已导入），然后重新进入 Rating Assessment 流程。

## 7. 持久化职责

```text
ios/DailyTactics/Resources/puzzles/*.json → 首次启动一次性全部导入
SwiftData  → 题目（PuzzleRecord）、题目进度（PuzzleProgress）、评估状态（RatingAssessment）
UserDefaults
  ├ dailytactics.libraryImported → 题库是否已一次性导入（首次启动 gate）
  └ dailytactics.userRating      → 当前 Rating
```
