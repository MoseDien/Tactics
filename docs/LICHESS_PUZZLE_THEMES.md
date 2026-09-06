# Lichess Puzzle Themes 简介

Lichess puzzle 的 `themes` 字段是一组标签，用来描述题目的战术主题、目标、对局阶段或解题长度。一道题可以同时包含多个 theme；例如，它既可能是中局题，也可能要求通过牺牲完成将杀。

DailyTactics 当前只解析 Lichess theme 的一个子集。本页说明的是 `PuzzleTheme` 枚举中实际支持的 12 个值，不是 Lichess 的完整 theme 清单。

## 数据格式

在 DailyTactics 的 JSON 数据中，themes 是字符串数组：

```json
{
  "id": "sample-001",
  "themes": ["sacrifice", "mate"]
}
```

Lichess 原始 CSV 则把多个 theme 放在同一字段中，并以空格分隔：

```text
advantage attraction fork middlegame sacrifice veryLong
```

Theme 名称区分大小写，并使用 lower camel case，例如 `discoveredAttack` 和 `rookEndgame`。

## 当前支持的 themes

### 战术主题

| Theme | 中文说明 |
|---|---|
| `fork` | **双重攻击**：一步棋同时攻击对方两个或更多目标。 |
| `pin` | **牵制**：被牵制棋子一旦移动，就会暴露其后的王或更高价值棋子。 |
| `skewer` | **串击**：先攻击前方的高价值棋子，迫使它移动，再攻击或吃掉后方价值较低的棋子；可理解为与牵制相反。 |
| `discoveredAttack` | **闪击**：移开挡在线路上的棋子，释放车、象或后等长距离棋子的攻击。 |
| `sacrifice` | **牺牲**：短期主动放弃子力，以便在强制变化后获得补偿或更大优势。 |
| `defensiveMove` | **防守着法**：必须找到精确着法，避免丢子、被将杀或失去已有优势。 |

### 题目目标

| Theme | 中文说明 |
|---|---|
| `mate` | **将杀**：题目的最终目标是将死对方。它不单独说明需要几步完成。 |
| `advantage` | **取得优势**：抓住机会获得决定性优势。Lichess 将其定义为解法结束时约有 200–600 centipawn 的优势。 |

### 对局阶段

| Theme | 中文说明 |
|---|---|
| `middlegame` | **中局**：战术发生在对局的中间阶段。 |
| `endgame` | **残局**：战术发生在对局的最后阶段。 |
| `rookEndgame` | **车兵残局**：以车和兵为主要子力的残局。它通常也会同时带有 `endgame`。 |

### 解题长度

| Theme | 中文说明 |
|---|---|
| `short` | **短题**：Lichess 定义为用户需要找到两手棋的题目。机器在两手用户着法之间回应。 |

## 多个 theme 如何理解

以下组合来自项目的示例题：

```json
["advantage", "endgame", "rookEndgame", "short"]
```

这些标签分别从不同角度描述同一道题：

- `advantage` 表示解题目标是取得决定性优势。
- `endgame` 表示局面处于残局阶段。
- `rookEndgame` 进一步说明这是车兵残局。
- `short` 表示用户需要找到两手棋。

Theme 并不是互斥分类，也没有“第一个 theme 一定最重要”的约定。UI 当前只展示数组中的第一个 theme，但存储层会保留所有受支持的值。

## 导入行为

`BundledPuzzleSource` 将每个字符串转换为 `PuzzleTheme`：

```swift
themes.compactMap(PuzzleTheme.init(rawValue:))
```

因此：

- 与枚举 raw value 完全匹配的 theme 会被保留。
- DailyTactics 尚未支持的 Lichess theme 会被安全忽略，不会导致整道题解码失败。
- 如果后续需要展示或筛选更多 theme，应先扩展 `PuzzleTheme`，再补充本地化名称和相关测试。

## Theme 与其他字段的区别

- `themes` 描述题目的类型和解法特征。
- `openingTags` 描述题目来源局面的开局名称，不属于 puzzle theme。
- `rating` 表示题目难度，不代表战术类别。
- `fen` 描述初始局面，`moves` 描述解法；theme 本身不能用于还原棋盘或验证着法。

## 官方参考

- [Lichess Puzzle Themes](https://lichess.org/training/themes)：完整分类、名称和说明。
- [Lichess puzzle database](https://database.lichess.org/#puzzles)：原始 CSV 字段格式和示例。
- [Lichess PuzzleTheme source](https://github.com/lichess-org/lila/blob/master/modules/puzzle/src/main/PuzzleTheme.scala)：Lichess 当前使用的 theme 定义与分类。

