# DailyTactics 业务逻辑

本文档描述当前的核心业务流程，不包含 SwiftUI 布局和具体实现细节。

## 项目范围

当前阶段只完成和维护 iOS 版本。Android 版本暂时暂停，待 iOS 功能、数据流程和产品体验稳定后再恢复开发。

## 0. 首次启动：一次性导入全部题库

App 第一次启动（或题库未导入时），先进行一次性批量导入：

- 从 `ios/DailyTactics/Resources/puzzles/` 下的 **全部 10 个等级 JSON**
  （`1000.json`–`1900.json`，每个 1000 题）读取并写入 SwiftData。
- 整个过程显示一个 Loading 页面和进度，导入完成后翻起
  `LibraryStateStore`（UserDefaults `dailytactics.libraryImported`）标志位。
- 导入是幂等的：按 `puzzleId` 去重，重复运行不会插入重复题目。
- 这个 gate 独立于 Daily Tactics，之后每次启动都跳过导入，直接进入后续流程。

题目 JSON 由 `tools/export_tier_puzzles.py` 从 `data/source/lichess_puzzles.sqlite`
按 100 分 Rating 区间抽样生成（可复现）。

## 1. Rating

Rating 由 `UserRatingStore` 保存在本地，并在首次有效尝试完成题目后按 Elo 风格规则更新。

## 2. 题库组织

题库文件按 100 分 Rating 区间组织（`1000.json`–`1900.json`），但这只是**导入时的数据分片**，
运行时不再按等级筛选或切换题库。10 个文件在首次启动时全部写入 SwiftData，总量约 10000 题。

不再有「用户当前等级」或「跨等级导入」的概念。

## 3. Daily Tactics

进入主训练后，题目来自 SwiftData。

### Difficulty Mode

Settings 中可以选择新 batch 的难度模式，默认是 `Medium`。设置保存在 UserDefaults，仅影响后续创建的 Play batch，当前 batch 和 Review 不受影响。

- `Easy`：选择 rating 不高于用户当前 Rating + 200 的题目。
- `Medium`：完全随机选择，不考虑题目 rating。
- `Hard`：选择 rating 不低于用户当前 Rating - 200 的题目。
- 当符合筛选条件的题目不足一个 batch 时，回退到未尝试题目池；未尝试题目不足时再从全部题库随机选择。

### Batch（4 小时节奏）

- 每个 batch 默认包含 5 道题，数量由 `BatchConfiguration.puzzleCount` 配置。
- 新 batch 开始时记录 `batchStartTime` 到 UserDefaults，并持久化当前题目 ID。
- 只有当 `当前时间 - batchStartTime >= BatchConfiguration.batchDuration` 时，才能开始下一个 batch；当前默认 `batchDuration = 4 小时`。
- 冷却期间重新打开 App 不会随机生成新题，只进入当前 batch 的 Review mode。
- 冷却结束后显示 `Start New Batch`，用户点击后才创建下一组题目并更新开始时间。
- Review mode 下 `Next puzzle` 只循环当前 batch；`Next batch` 与其分离，只有用户主动点击才会尝试创建新 batch。时间未到时点击会显示等待提示，仍停留在 Review mode。
- Play mode 完成 batch 后，`Next puzzle` 仍保持可用；用户点击后进入 Review mode，并从当前 batch 循环查看题目。

### Round

- 每个 round 默认包含 5 道题。
- 题目从整个题库中**随机选择尚未尝试过的** 5 道（不按 Rating 区间筛选，难度混合）。
- **查询数据库只在 batch 开始时发生一次**。一个 batch 进行中不再重新随机选择题目。
- 当未做过的题目不足 5 道时，回退为从全部题目中随机选择。

### Review mode

- Review 当前 batch 的 5 道题，最后一道之后循环回第一道。
- Hint 和 Flip board 保持可用，用户可以继续落子并查看当前题目的进度。
- Review 可以更新题目的完成/失败进度，但不修改用户 Rating。

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

## 6. Settings

Settings 提供历史记录入口。历史按每 5 道题保存为一个 batch，用户可以逐题进入 Review。


## 7. 持久化职责

```text
ios/DailyTactics/Resources/puzzles/*.json → 首次启动一次性全部导入
SwiftData  → 题目（PuzzleRecord）、题目进度（PuzzleProgress）、历史 batch（RoundHistory）
UserDefaults
  ├ dailytactics.libraryImported → 题库是否已一次性导入（首次启动 gate）
  └ dailytactics.userRating      → 当前 Rating
  └ batchStartTime                → 当前 batch 开始时间
  └ activeBatchPuzzleIDs          → 当前 batch 的固定题目顺序
```
