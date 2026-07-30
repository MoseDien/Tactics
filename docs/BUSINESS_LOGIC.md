# DailyTactics 业务逻辑

本文档描述当前 MVP 的核心业务流程，不包含 SwiftUI 布局和具体实现细节。

## 1. Rating Assessment：建立用户 baseline rating

用户第一次启动 App，或在 Settings 中主动选择重新评估时，进入 Rating Assessment。

### 题目来源

- 从 `rating_puzzles.json` 读取固定的评级题集合。
- 按难度分布随机抽取评估题。
- 当前评估题数量由 App 配置参数控制，目前为 4 道，未来可以改为 10 道。

### 评估规则

- 每道题只允许第一次尝试。
- 第一次答对，记录为成功。
- 第一次答错，立即记录为失败并进入下一题。
- 评估过程中显示当前执棋方、题目进度和成功/失败列表。

### baseline rating

完成所有评估题后，根据题目平均难度和用户答对比例计算 baseline rating。

用户会看到包含具体 Rating 数值的确认弹窗。用户点击确认后：

1. 根据 baseline rating 选择对应的 100 分等级题库。
2. 显示题库导入 Loading 和进度。
3. 将对应 JSON 题库导入 SwiftData。
4. 保存 baseline rating 和评估完成状态。
5. 进入 Daily Tactics。

如果用户没有确认，评估完成状态不会写入，下一次启动仍会继续评估流程。

## 2. Rating 等级

当前等级范围为 1000–1999，每 100 分一个等级：

| 等级文件 | Rating 范围 |
| --- | --- |
| `1000.json` | 1000–1099 |
| `1100.json` | 1100–1199 |
| `1200.json` | 1200–1299 |
| `1300.json` | 1300–1399 |
| `1400.json` | 1400–1499 |
| `1500.json` | 1500–1599 |
| `1600.json` | 1600–1699 |
| `1700.json` | 1700–1799 |
| `1800.json` | 1800–1899 |
| `1900.json` | 1900–1999 |

用户的 Rating 和当前等级会持久化保存。

## 3. Daily Tactics

进入主训练后，题目来自 SwiftData，而不是直接从 JSON 读取。

### Round

- 每个 round 默认包含 5 道题。
- round 数量通过参数配置，未来可以调整。
- 题目从当前用户等级对应的 Rating 范围中随机选择。
- 当前测试阶段，一个 round 完成后会重新随机选择下一 round。

### 单题流程

1. 系统先自动执行 Lichess puzzle line 的第一步机器走子。
2. 用户尝试自己的应对着法。
3. 答错时显示错误反馈，允许在普通 Daily Tactics 模式中继续尝试。
4. 答对后自动执行对手回复，直到题目完成。
5. 题目完成后保存进度和 Rating 结果。

## 4. Puzzle 数据和完成标记

SwiftData 中使用两个概念保存用户状态：

- `PuzzleRecord`：题目本身，包括 FEN、走法、Rating 和主题。
- `PuzzleProgress`：用户对题目的运行时状态。

每道题第一次被用户尝试时，会在 `PuzzleProgress` 中标记 `isAttempted`。

后续 round 会优先从尚未尝试过的题目中随机选择。

## 5. Rating 更新规则

### 只对首次有效尝试更新 Rating

- 题目之前没有被尝试过，并且第一次尝试答对：根据 Elo 风格规则更新 Rating。
- 题目第一次尝试答错：标记为已尝试；即使之后答对，也不再修改 Rating。
- 题目之前已经做过：无论本次答对或答错，都不再修改 Rating。

这样可以避免用户反复练习同一道题来重复获取 Rating。

### 题目完成状态

即使该题不再影响 Rating，题目仍会记录完成状态和失败状态，用于历史进度和后续筛选。

## 6. Round 完成后的等级检查

当一个 round 完成后，系统检查用户当前 Rating 对应的 100 分等级：

- 如果 Rating 达到更高等级范围，提示用户升级。
- 如果 Rating 下降到更低等级范围，提示用户降级。
- 用户确认后，导入对应等级的 JSON 题库到 SwiftData。
- 导入过程会去重，不重复插入已有题目。
- 后续 round 从新的等级范围中选择题目。

## 7. Settings：重新评估 baseline rating

用户可以在 Settings 中主动重新评估 baseline rating。

确认后会清除：

- SwiftData 中的题库记录 `PuzzleRecord`
- SwiftData 中的题目进度 `PuzzleProgress`
- Rating Assessment 完成状态
- 已保存的 Rating

然后重新进入 Rating Assessment 流程。

## 8. 持久化职责

```text
rating_puzzles.json  → 首次 baseline assessment
1000.json–1900.json  → 按等级导入的题库
SwiftData             → 题目、题目进度、Assessment 状态
UserDefaults          → 当前 Rating 和等级缓存
```
