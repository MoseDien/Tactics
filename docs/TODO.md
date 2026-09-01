# DailyTactics 问题清单 / TODO

审查日期:2026-08-30。来源:文档(CLAUDE.md / AGENTS.md / README.md / docs/BUSINESS_LOGIC.md / THIRD_PARTY_NOTICES.md)与 iOS 实现的交叉审查,全部 10,100 道内置题目逐题重放验证。

**状态更新(2026-08-30,第二阶段)**:以下所有 P0/P1/P2 项已全部修复并验证(37 个测试全绿,含全库 10,100 题在新规则引擎下的重放测试)。遗留事项见文末「仍开放」一节。

---

## P0 — 必现功能 Bug(直接影响用户)

- [x] **升变题无法解出(2/10100 题)** — 增加 4 选 1 升变选择器(`TacticsView.promotionPicker` + `TacticsViewModel.pendingPromotion/choosePromotion`),`o8GIU`(升车)/`LnGZ6`(升马)现在可解。回归测试:`testUnderpromotionPuzzlesSolveWithChosenPromotionPiece`。
- [x] **最后一题使用 Hint 会丢失整轮历史记录** — `recordRound` 与 Rating 流程解耦,改用按 batch 生命周期的 `roundRecorded` 标志保证恰好一次。回归测试:`testRoundHistoryRecordsOnceDespiteHintOnLastPuzzleAndReviewReplay`。
- [x] **Review 模式重解最后一题会插入重复 RoundHistory 行** — 同上,`roundRecorded` 标志防重。
- [x] **导入失败仍标记 `libraryImported = true`** — `importAllBundled` 返回失败 tier 数;失败时 Loading 页显示错误 + 重试按钮,不置位 gate。
- [x] **batch 周期三处互相矛盾** — 统一为一处配置 `BatchStore.batchDuration`(正式版 8 小时,Debug 构建 5 分钟便于手工测试);Settings 玩法说明与 `tactics.batch_cooldown` 文案同步。测试:`testBatchStoreDuration`。
- [x] **本地化 key 错误** — `settings.historyFooter` → `settings.history_footer`。
- [x] **`TacticsView` #Preview 缺少 RoundHistory schema** — 预览容器补 `RoundHistory.self`。

## P1 — 质量、规则与文档

### 代码

- [x] **`Puzzle.loadBundled()` 指向不存在的文件** — 已删除(连同 `TacticsViewModel.init` 的默认参数,调用方必须显式传 dataset);`preconditionFailure` 改为错误消息 + 样例回落。
- [x] **首次导入阻塞主线程** — JSON 读取/解码移入 `Task.detached`,仅 SwiftData 写入留在 MainActor;增加 `Task.isCancelled` 检查。
- [x] **"Next batch" 冷却期内无等待提示** — 实现 `batchCooldownMessage` + 界面 Label 提示,停留当前 batch。
- [x] **时序 sleep 位于 ViewModel** — 保留(见下「仍开放」的说明:三处 sleep 属于交互节奏而非领域规则,domain 层 `PuzzleSession` 依旧纯函数;`start()` 竞速问题因 `userColor` 改为固定值而消除)。
- [x] **全局可变状态** — `BatchStore`/`UserRatingStore`/`DifficultyModeStore` 保持 UserDefaults 静态命名空间(见「仍开放」:这是有意的产品决定,UserDefaults 本身线程安全)。
- [x] **写死频率的隐形刷新定时器** — 移除 30 秒 Timer;改为在 batch 到期时刻点一次的轻量 task(`batchExpiryTick`),不再周期性全树重渲染。
- [x] **Review 模式 Hint 按钮永不禁用** — `.disabled(!viewModel.hintEnabled)` 修正合取逻辑。
- [x] **硬编码英文串** — 全部接入 en/zh-Hans string catalog(错误消息、Review 页、Settings、Loading 页、棋盘无障碍标签、结果摘要);清理死 key(`tactics.start_new_batch`、`rating.baseline_*` 等)。

### ChessCore 规则引擎

- [x] **FEN 解析丢弃第 3–6 字段** — 解析 castling rights 与 en-passant target;拒绝非 ASCII 数字与多数字 run。测试:`testFENParsesCastlingAndEnPassantFields`、`testFENRejectsNonASCIIDigitsAndBadRanks`。
- [x] **`isLegal` 只是形状校验** — 补齐将军/被牵制(候选局面验证)、易位完整规则(权利/路径/受攻格)、过路兵(按 FEN target)、升变必要性校验。测试:`testKingCannotMoveIntoCheck`、`testPinnedPieceCannotExposeItsKing`、`testCastlingLegality`、`testEnPassantIsLegalWhenTargetMatches`、`testPromotionRequirementInIsLegal`。
- [x] **过路兵 `apply` 是无条件破坏性启发** — 仅当被捕获格确有敌兵时才移除。测试:`testEnPassantApplyOnlyRemovesAnEnemyPawn`。
- [x] **易位 `apply` 无前置校验** — 车必须在位才迁移(否则按普通王移动处理,不产生幽灵车);同时维护 castling rights 增量更新。
- [x] **`Board.sideToMove` 是 `let`,apply 后不更新** — 改 `var` 并在 `apply` 后翻转、维护 en-passant 上下文;`PuzzleSession.userColor` 改为 init 时固定的存储属性(修复了由此引出的回归,`testBoardAutoOrientsToPlayerColor` 覆盖)。

### 文档

- [x] README Rating 规则失实(答错不更新/仅 Hint 扣分/±1 最小值/钳制)已修正。
- [x] BUSINESS_LOGIC.md 难度模型、升变、RoundHistory 恰好一次、本地化、导入失败处理全部更新;batch 节奏与代码一致(8 小时 / Debug 5 分钟)。
- [x] CLAUDE.md 架构图补 Settings/Onboarding/ReviewRoundView;Persistence 一节补全类型;交互规则补升变/冷却/历史恰好一次/本地化条目;"localization transition rules" 引用改为真实存在的章节。
- [x] THIRD_PARTY_NOTICES.md:路径修正为 `ios/DailyTactics/...`;补 Lichess 题库数据(CC0)署名;补 third_party 截图说明与图标条目;覆盖 Android 目录棋子图。
- [x] README 断句残缺修复;`rating_puzzles.json` 在 README 中不再当作有效资源列出;tools/ 三个脚本均有说明(注明前两者已被取代)。

## P2 — 测试缺口与工程卫生

### 测试缺口(全部补齐)

- [x] ChessCore 错误路径:非 ASCII 数字、多数字 run、缺字段 FEN。
- [x] 升变逻辑:升变必要性、升变后缀校验、低升变题可解性(直接读捆绑 tier 文件验证 `o8GIU`/`LnGZ6`)。
- [x] Rating 数学:K=32 语义不等式、强制 ±1 最小值、[400,3000] 钳制、重置后回到 1500。
- [x] flaky 的 `testHintImmediatelyCostsRating` 改为按需等待(最长 5s,只在需要时等);`testBoardAutoOrientsToPlayerColor` 改为单题 dataset 真正驱动重载。
- [x] 持久化行为:RoundHistory 恰好一次(含 Hint + Review 重放双路径)、BatchStore 时长常量与重复 ID 容忍、导入幂等 + 失败计数。
- [x] **全库重放测试** `testAllBundledPuzzlesReplayThroughSession`:10,100 题全部通过新规则引擎验证(约 2.2s)。

### 工程卫生

- [x] 根目录损坏的 `DailyTactics.xcworkspace/`(含二进制 xcuserstate)已从 git 删除。
- [x] `ios/` 下 Tuist 生成的 `.xcodeproj`/`.xcworkspace` 已从 git 删除;`.gitignore` 补 `*.xcodeproj`/`*.xcworkspace`/`xcuserdata`/`*.tuist-generated` 规则。
- [x] Project.swift 补 `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`;App 图标压平 alpha 通道(App Store 校验要求);`.DS_Store` 清理且被 ignore;`Resources/.gitkeep` 删除。
- [x] 死代码清理:`reviewPuzzle` sheet、`restart()`、`attachProgress()`、注释掉的 `.font`/`.animation` 残留;`Dictionary(uniqueKeysWithValues:)` 两处改为首现获胜的防崩写法。
- [ ] `PuzzleLibraryImporter.reset/resetProgress`、`LibraryStateStore.isImported/markImported` 无调用方 — 保留(见「仍开放」)。

## 仍开放(有意保留或待产品决定)

- **`tuist test` 不可用(Tuist 4.197)**:该命令只解析 workspace 级 scheme,而本项目不再生成 workspace(生成文件已退出 git,见工程卫生一节)。曾尝试 `Workspace.swift` manifest 定义 workspace scheme:buildAction 的 `.project(path:, target:)` 可用,但 testAction 的 `TestableTarget` 只接受字符串、lint 又强制要求带 project path,二者矛盾,无法通过。验证命令已改为 `xcrun xcodebuild test -project DailyTactics.xcodeproj -scheme DailyTactics`(三份文档已同步)。若未来升级 Tuist 解决此矛盾,可恢复 `tuist test`。
- **全局 UserDefaults 静态命名空间**(`BatchStore`/`UserRatingStore`/`DifficultyModeStore`):CLAUDE.md 的"Avoid global mutable state"措辞与实现有张力。UserDefaults 线程安全、数据量小,当前无并发缺陷;若未来要注入测试替身,可重构为 protocol。改动收益低、影响面大,暂不动。
- **ViewModel 内三处 `Task.sleep`**(300/550/450ms):它们是交互节奏(下一题过渡/错误着法展示/对手回复停顿),不参与 domain 状态推导;`PuzzleSession` 保持纯函数。若要严格遵守"timing outside view layer",需要引入 UI 层驱动的事件队列,复杂度不成比例,暂保留。
- **iPad 设备族**:`Project.swift` 的 `.iOS` destination 包含 iPad,但布局按 iPhone 设计。待产品决定是否收窄为 `TARGETED_DEVICE_FAMILY = 1` 或做 iPad 布局。
- **SwiftData schema 迁移**:无 `VersionedSchema`/`SchemaMigrationPlan`。当前 schema 尚未发布(1.0 未上架),首次发布前若改 model 需补迁移计划。
- **`PuzzleProgress.puzzleId` 无 `.unique` 约束**:加约束需要迁移;在发布前补上最合适(当前 fetch-then-insert 模式实际防止了重复)。
- **`rating_puzzles.json`(100 题)仍捆绑但无代码引用**:疑似历史遗留的"Rating 评估"功能数据。删除需确认无回滚计划。

---

## 功能计划(进行中)

### Rating 历史曲线(2026-08-31 登记,同日完成 — 38 测试全绿)

目标:记录 rating 随时间的变化,在 Settings 中用曲线展示;每个 batch 完成时记录一次。

- [ ] **独立 `RatingSnapshot` SwiftData 模型**(`Persistence/RatingHistory.swift`):`id`/`recordedAt`/`rating`,不与 `RoundHistory` 关联——为将来每题一记或 batch 之外的 rating 事件(如重新评估)留出演进空间。
- [ ] **记录时机**:`TacticsViewModel.markCurrentSolved()` 在 batch 最后一题结算完成、rating 更新之后写入快照(快照值包含最后一题的 delta);复用 `roundRecorded` 防重逻辑保证每个 batch 恰好一条,Review 重解不重复。Hint 早退路径同样记录。
- [ ] **Settings 曲线**:新 Section 用 Swift Charts(`LineMark` + monotone 插值)展示 `recordedAt` → `rating`;空数据占位文案;en/zh-Hans 同步补 key。
- [ ] **容器注册**:`DailyTacticsApp` 与 `TacticsView` preview 的 `modelContainer(for:)` 补 `RatingSnapshot.self`。
- [ ] **回归测试**:单题 batch 干净解出 → `ratingHistory()` 恰 1 条且等于结算后的 rating;Review 重解后仍 1 条。
- [ ] 当前 Rating 的存储不变:仍是 `UserDefaults` 标量(`dailytactics.userRating`),快照只追加时间序列。
