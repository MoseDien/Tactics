# DailyTactics 业务逻辑

本文档描述当前的核心业务流程，不包含 SwiftUI 布局和具体实现细节。

## 项目范围

当前阶段只完成和维护 iOS 版本。Android 版本暂时暂停，待 iOS 功能、数据流程和产品体验稳定后再恢复开发。

## 0. 首次启动：导入内置题库块

App 第一次启动（或题库未导入时），先进行一次性批量导入：

- 从 `ios/TacticsData/Resources/Puzzles/puzzle-0000.json` 读取 1000 道内置题并写入 SwiftData。
- JSON 读取与解码在后台线程执行，只有 SwiftData 写入留在主线程。
- 整个过程显示一个 Loading 页面和进度，导入完成后翻起
  `LibraryStateStore`（UserDefaults `dailytactics.libraryImported`）标志位。
- **内置块解析失败不会置位标志位**：Loading 页显示错误与「重试」按钮，
  避免静默降级到内置样例题。
- 导入是幂等的：按 `puzzleId` 去重，重复运行不会插入重复题目。
- 这个 gate 独立于 Daily Tactics，之后每次启动都跳过导入，直接进入后续流程。

## 题库分块与按需下载

- 题库以块为单位交付：每块 1000 题，一个 `puzzle-NNNN.json`；App 内置第 0 块，其余部署在远端目录。
- App 在本地记录「当前数据序号」（UserDefaults `dailytactics.puzzleSequence`，内置块 = 0）。
- 当未尝试题目不足以组成一个 round（< `RoundPolicy.puzzleCount`）时，自动下载下一块并导入：启动选题前与每次开始新 round 时各检查一次。
- 下载失败（断网/超时/坏数据/404）静默跳过，选题回退到既有链条（未尝试不足 → 全库随机）；404 表示块未发布，本次会话不再重试。
- 导入按 puzzleId 去重，重复下载同一块无副作用。
- Settings 中展示当前块序号与已载入题目数。

题目 JSON 由 `tools/export_puzzle_chunk.py` 从 `data/source/lichess_puzzles.sqlite`
随机抽样生成（可复现，按 `exported_puzzles` 表标记避免重复导出）。

## 1. Rating

Rating 由 `UserRatingStore` 保存在本地，并在首次有效尝试成功、首次走错或使用 Hint 时按 Elo 风格规则结算。

每个 round 完成时（最后一题结算之后）追加一条 `RatingSnapshot`（SwiftData）：记录该 round 结算后的 Rating 值，形成随时间变化的趋势序列，供 Settings 中的曲线展示。当前 Rating 仍以 `UserDefaults` 标量为准，快照只追加、不回写。

## 2. 题库组织

题库按 1000 题一块组织为 `puzzle-NNNN.json`。App 首次启动只导入内置的第 0 块；后续在未尝试题池不足一个 round 时按序下载第 1、2、3……块。

块编号不代表难度等级。「用户当前等级」不驱动题库块切换；Difficulty Mode（见下）在所有已导入题目中，按用户当前 Rating 与题目 Rating 的相对关系筛选新 round。

## 3. Daily Tactics

进入主训练后，题目来自 SwiftData。

### Difficulty Mode

Settings 中可以选择新 round 的难度模式，默认是 `Medium`。设置保存在 UserDefaults，仅影响后续创建的 Play round，当前 round 和 Review 不受影响。

- `Easy`：选择 rating 不高于用户当前 Rating + 200 的题目。
- `Medium`：完全随机选择，不考虑题目 rating。
- `Hard`：选择 rating 不低于用户当前 Rating - 200 的题目。
- 当符合筛选条件的题目不足一个 round 时，回退到未尝试题目池；未尝试题目不足时再从全部题库随机选择。

### Round（8 小时节奏）

- 每个 round 默认包含 5 道题，数量由 `RoundPolicy.puzzleCount` 配置。
- 新 round 开始时记录 `dailytactics.roundStartTime` 到 UserDefaults，并持久化当前题目 ID。
- 只有当 `当前时间 - roundStartTime >= RoundPolicy.roundDuration` 时，才能开始下一个 round；正式版 `roundDuration = 8 小时`，Debug 构建缩短为 1 小时以便手工测试完整周期。
- 冷却期间重新打开 App 不会随机生成新题，只进入当前 round 的 Review mode。
- 冷却结束后 `Next round` 解锁；用户点击后才创建下一组题目并更新开始时间。
- Review mode 下 `Next puzzle` 只循环当前 round；`Next round` 与其分离，只有用户主动点击才会尝试创建新 round。时间未到时点击会显示等待提示（剩余冷却说明），仍停留在 Review mode。
- Play mode 完成 round 后，`Next puzzle` 仍保持可用；用户点击后进入 Review mode，并从当前 round 循环查看题目。

### Round

- 每个 round 默认包含 5 道题。
- 题目从整个题库中随机选择尚未尝试过的 5 道（按 Difficulty Mode 的相对 rating 规则筛选）。
- **查询数据库只在 round 开始时发生一次**。一个 round 进行中不再重新随机选择题目。
- 当未做过的题目不足 5 道时，回退为从全部题目中随机选择。
- 一轮完成时恰好写入一条 `RoundHistory`：最后一题用 Hint 不影响历史记录；Review 中重解最后一题也不会重复写入。

### Review mode

- Review 当前 round 的 5 道题，最后一道之后循环回第一道。
- Hint 和 Flip board 保持可用，用户可以继续落子并查看当前题目的进度。
- Review 可以更新题目的完成/失败进度，但不修改用户 Rating。
- Review 不会改变实时解题结果，也不会触发对手自动回应。

### 单题流程

1. 系统先自动执行 Lichess puzzle line 的第一步机器走子。
2. 用户尝试自己的应对着法。
3. 答错时显示错误反馈，允许继续尝试。
4. 答对后自动执行对手回复，直到题目完成。
5. 题目完成后保存进度和 Rating 结果。

### 棋子动画

棋盘的移动动画完全由**一个派生映射**驱动(`TacticsViewModel.animatedArrival`):「本次渲染中哪个格刚得到棋子、它视觉上从哪格来」。映射为空即「无着法附着」——不动画。所有场景由这一个语义覆盖,无逐例特判:

| 场景 | 行为 |
|---|---|
| 载入新题(setup) | 棋子**淡入**(0.18s),呈现就绪局面 |
| 对手开局第一步 | 滑入(与普通着法相同) |
| 用户/对手正常着法、王车易位 | 移动棋子（及易位车）滑入 easeOut，**时长按距离、封顶**：`45ms + 50ms/格`，最多按 2 格计（1 格 95ms、**≥2 格一律 145ms**）；易位取王/车中较长者 |
| 错着预演 | 错误棋子滑到目标格,~0.55s 后**滑回**原格 |
| 吃子 | 被吃棋子立即消失(不做滑走) |
| 翻转棋盘 / Reduce Motion | 瞬切,无动画 |

两个安全不变量(由结构保证,是历次缺陷的修复结论):

- **载入代号编入棋子 id**(`boardGeneration`):换题时全部棋子都是全新视图,不存在「沿用旧视图而 offset 被插值」的棋子横飞路径。
- **映射为空时事务本身不带动画**:持久视图不插值、插入原样出现。

动画开关(Debug 构建,Settings → 调试工具):「棋子移动动画」与「棋盘载入动画」两个独立 Toggle,缺省开,`AppPreferences.wipeAll` 覆盖(回到初始状态会还原默认)。动画实现集中在 `ChessBoardView`(`BoardAnimation` 值进、transition 出),域层(`PuzzleSession`)不含任何动画时序。

### 升变

兵到达底线时，界面弹出 4 选 1 升变选择器（后/车/象/马）。期望着法是低升变（如 `e2e1r`）的题目必须选择对应棋子才能判对，不再强制升变为皇后。

## 4. Puzzle 数据和完成标记

SwiftData 中使用两个概念保存用户状态：

- `PuzzleRecord`：题目本身，包括 FEN、走法、Rating 和主题。
- `PuzzleProgress`：用户对题目的运行时状态（是否尝试、是否完成、是否失败）。

每道题第一次被用户尝试时，会在 `PuzzleProgress` 中标记 `isAttempted`。
Round 选择时优先排除已尝试的题目。

## 5. Rating 更新规则（Elo 风格，K=32）

### 只对首次有效尝试更新 Rating

- 题目之前没有被尝试过，并且第一次尝试答对：根据 Elo 风格规则更新 Rating。
- 题目第一次尝试答错：立即按失败结算并扣分；即使之后答对，也不再增加 Rating。
- 使用 Hint 即视为放弃，立即按失败结算并扣分。
- 题目之前已经做过：无论本次答对或答错，都不再修改 Rating。
- 真实 delta 四舍五入为 0 时，强制为 +1（答对）/ −1（答错）：每次结算 Rating 必有变化。
- Rating 存储值钳制在 `[400, 3000]`。

Rating 是一个本地训练分数，不再是 Lichess 官方 Rating，也不再驱动题库切换。

### 题目完成状态

即使该题不再影响 Rating，题目仍会记录完成状态和失败状态，用于历史进度。

## 5.5 收藏(Favorites)

- 只有**完成的题目**才能收藏(play 完成时或 review 时;`currentPuzzleFinished` 保持真,回看不撤销)。
- 收藏/取消在 play 与 review 模式下行为一致,不影响任何评分或进度。
- 收藏状态存于 `PuzzleProgress.isFavorite`(含 `favoritedAt` 时间戳);Debug 重置随之清空。
- 首页按钮:flip 右边的爱心轮廓,粉色 = 已收藏,灰色 = 未收藏;题目未完成时隐藏(保留占位)。
- Settings → 收藏:收藏题列表(题号、难度星级、rating/练习数、主题标签),点开进入单题逐步复盘。

## 6. Settings

Settings 提供难度模式选择、玩法说明和历史记录入口。历史按每 5 道题保存为一个 round;历史列表按**周**分组(本周/上周/前周用相对措辞,更早显示日期区间,每组带题数与对错汇总),每个 round 一行(完成时刻 + 结果标记 + 正确率)。点开一个 round 进入**整组连续复盘**(RoundReviewView):单题可逐步回放,题间直接切换、末题循环;复盘只读,不影响任何进度或评分。

Debug 构建额外显示「调试工具」区:棋子动画的两个开关(见「棋子动画」一节)、「清空未尝试题池」(触发自动下载路径)与「回到最初始状态」(清空全部 SwiftData 与 UserDefaults,重走首次导入)。

## 7. 本地化

界面文案统一走 `Resources/Localization/{en,zh-Hans}.lproj/Localizable.strings`。新增用户可见文案时必须同时补两个语言条目；棋盘格子的无障碍标签同样本地化。

## 8. 持久化职责

```text
ios/TacticsData/Resources/Puzzles/puzzle-0000.json → 首次启动导入内置块
SwiftData  → 题目（PuzzleRecord）、题目进度（PuzzleProgress）、历史 round（RoundHistory）、
             每 round 的 rating 快照（RatingSnapshot）
UserDefaults
  ├ dailytactics.libraryImported → 题库是否已一次性导入（首次启动 gate）
  ├ dailytactics.userRating      → 当前 Rating
  ├ dailytactics.puzzleSequence → 当前已载入的题库块序号
  ├ dailytactics.difficultyMode  → 新 round 的难度模式
  ├ dailytactics.pieceAnimation  → 棋子移动动画开关（debug，缺省开）
  ├ dailytactics.setupAnimation  → 棋盘载入动画开关（debug，缺省开）
  ├ dailytactics.roundStartTime          → 当前 round 开始时间
  └ dailytactics.activeRoundPuzzleIDs    → 当前 round 的固定题目顺序
```
