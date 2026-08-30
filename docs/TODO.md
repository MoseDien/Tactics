# DailyTactics 问题清单 / TODO

审查日期:2026-08-30。来源:文档(CLAUDE.md / AGENTS.md / README.md / docs/BUSINESS_LOGIC.md / THIRD_PARTY_NOTICES.md)与 iOS 实现的交叉审查,全部 10,100 道内置题目逐题重放验证。

仅记录,暂不修复。修复时从 P0 开始,逐项勾选。

---

## P0 — 必现功能 Bug(直接影响用户)

- [ ] **升变题无法解出(2/10100 题)** — `TacticsViewModel.swift:319-321`
  用户升变时强制变为皇后(`promotion: .queen`),无升变棋子选择 UI。题库中 `o8GIU`(1000.json,期望 `e2e1r` 升车)和 `LnGZ6`(1100.json,期望 `d7d8n` 升马)永远判错,用户还会被扣分。
  修法:增加升变棋子选择 UI,或按期望着法匹配升变子。

- [ ] **最后一题使用 Hint 会丢失整轮历史记录** — `TacticsViewModel.swift:379-393`
  `applyHintPenalty` 置 `ratingAppliedForPuzzle = true`;之后完成该题时 `markCurrentSolved` 在 `:384` 的 guard 提前返回,跳过 `:388` 的 `progress?.recordRound(...)`。
  后果:batch 最后一题用过 Hint → 整轮在 History 里完全没有记录。需配回归测试。

- [ ] **Review 模式重解最后一题会插入重复 RoundHistory 行** — `TacticsViewModel.swift:387-389`
  `loadPuzzle(at:)` 会重置 `ratingAppliedForPuzzle`(`:307`),Review 循环回最后一题再解一次,`recordRound` 会再插一行。
  违反 CLAUDE.md "Review must not mutate the live solve result"。需配回归测试。

- [ ] **导入失败仍标记 `libraryImported = true`,永久降级为 3 道样例题** — `PuzzleLibrary.swift:71-78` + `LibraryLoadingView.swift:44`
  所有 tier 文件解码失败时 `try?` 全部返回 nil、`guard total > 0` 静默 return,但调用方无条件置位 `libraryImported = true`,之后每次启动都跳过导入 gate,静默回落到 3 道样例。

- [ ] **batch 周期三处互相矛盾** — 已确认真实预期为 **4 小时**
  代码 `BatchStore.swift:5` = 2 分钟(错误值);`docs/BUSINESS_LOGIC.md:51` = 4 小时(为准);`SettingsView.swift:47` 文案 = "within an hour"(需改)。
  附带影响:2 分钟窗口下,短暂退到后台再回来(`DailyTacticsApp.swift:31`)就会被路由进 Review 模式、永久失去该 batch 的 Rating 资格。

- [ ] **本地化 key 错误,Settings footer 显示原始 key** — `SettingsView.swift:26`
  引用 `"settings.historyFooter"`(驼峰),string table 里是 `"settings.history_footer"`(下划线)。两种语言下 footer 都显示字面 key。

- [ ] **`TacticsView` #Preview 缺少 RoundHistory schema** — `TacticsView.swift:286`
  预览容器只注册 `[PuzzleProgress, PuzzleRecord]`,App 注册了 `RoundHistory`(`DailyTacticsApp.swift:10`)。预览里解完最后一题调 `recordRound` 会命中未注册 model。

## P1 — 质量、规则与文档

### 代码

- [ ] **`Puzzle.loadBundled()` 指向不存在的文件** — `Puzzle.swift:87`
  加载 `Resources/puzzles.json`,但该文件不存在(只有 `1000.json`–`1900.json`)。函数永远回落到 3 道手写样例;`fatalError` 分支是死代码。它还是 `TacticsViewModel.init` 的默认参数(`TacticsViewModel.swift:49`),任何省略 `dataset:` 的调用都会静默拿到 3 道样例题。删除或修复。

- [ ] **首次导入阻塞主线程** — `PuzzleLibrary.swift:35-95`
  `PuzzleLibraryImporter` 是 `@MainActor`,`importAllBundled` 同步执行 3.3MB JSON 读取 + 10,000 次解码 + 10,000 次 insert + 40 次 save。`Task.yield()` 不会把工作移出主线程,Loading 动画会卡死;也不检查 `Task.isCancelled`。

- [ ] **"Next batch" 冷却期内无等待提示** — `TacticsViewModel.swift:186-198` vs `docs/BUSINESS_LOGIC.md:54`
  文档承诺显示等待提示并停留 Review;实际静默 `mode = .reviewBatch; currentIndex = 0`,按钮叫 "Next batch" 却只是重看同一批题。实现文档承诺的提示,或改文档。

- [ ] **时序 sleep 位于 ViewModel 而非视图层** — `TacticsViewModel.swift:177`(300ms)、`:352`(550ms)、`:366`(450ms)
  450ms 对手回复延时位于 `playOpponentMove()` 状态机内部,对正确性起承载作用(`start()` 在 `:263` 依赖 `currentMoveIndex == 0` 与 sleep 窗口竞速)。违反 "Keep animation timing outside domain rules"。

- [ ] **全局可变状态** — `BatchStore` / `UserRatingStore` / `DifficultyModeStore` 均为 UserDefaults 直读直写的静态命名空间,从 ViewModel/View 直接访问。违反 "Avoid global mutable state"。

- [ ] **写死频率的隐形刷新定时器** — `TacticsView.swift:11,42-44`
  `currentDate` 只写不读,唯一作用是强制每 30 秒重算 `canStartNewBatch`(它读取不被追踪的 `BatchStore.isWithinDuration`)。整个 body 每 30 秒重渲染一次;删掉这个"未使用"的 timer 会导致 batch 到期不刷新且无任何编译/测试信号。

- [ ] **Review 模式 Hint 按钮永不禁用** — `TacticsView.swift:210`
  `.disabled(mode == .play && !hintEnabled)` 合取式意味着 Review 下永远可点,点了又被 `requestHint()` 内部 guard 静默吞掉。

- [ ] **硬编码英文串绕过 string catalog** — `TacticsViewModel.swift:312,339,371`、`ChessBoardView.swift:105-110`(棋盘无障碍标签)、`ReviewRoundView.swift:13,22,25,74-76,97,105`、`SettingsView.swift:38-48`、`LibraryLoadingView.swift:21-23`、`TacticsView.swift:158,191,197`、`PuzzleResultRow.swift:51`
  其中多处 key 在 en/zh-Hans catalog 里**已存在**(`review.label`、`settings.how_to_play`、`loading.library`、`common.got_it` 等)却未使用。同时清理无引用的死 key(`tactics.start_new_batch`、`rating.baseline_*`、`common.continue` 等)。

### ChessCore 规则引擎(当前数据重放全部通过,暂不触发,但属公共 API)

- [ ] **FEN 解析丢弃第 3–6 字段** — `Chess.swift:121-153`。王车易位权、过路兵目标格、半步钟、步数全部不解析;`fields.count >= 2` 即通过(样例题 `Puzzle.swift:67` 甚至用 2 字段 FEN)。
- [ ] **`isLegal` 只是形状校验** — `Chess.swift:200-278`。不查将军/被牵制/易位/过路兵;且**拒绝**易位(`e1g1` 返回 false)和过路兵;兵到底线无升变后缀也判合法。`TacticsViewModel.swift:322-326` 的 `isExpected` 旁路注释明确承认是在绕过这些缺口。
- [ ] **过路兵 `apply` 是无条件破坏性启发** — `Chess.swift:174-178`。斜走兵到空格即删除 `(to.file, from.rank)`,不校验该格是否真有敌兵,可能误删己方棋子。
- [ ] **易位 `apply` 无前置校验** — `Chess.swift:163-170`,车不在位时静默产生 g1 王无车。
- [ ] **`Board.sideToMove` 是 `let`,apply 后不更新** — `Chess.swift:119`,走子后即过期。

### 文档

- [ ] **README Rating 规则失实** — README 称答错记 `result = 0`,实际答错**完全不更新 Rating**(`TacticsViewModel.swift:330-333`),只有用 Hint 才扣分。
- [ ] **`Rating.swift:18` 强制 delta 为 ±1 的规则任何文档都没写**(真实 Elo delta 四舍五入为 0 时仍强制 ±1)。
- [ ] **难度模型文档过时** — `docs/BUSINESS_LOGIC.md:32,60` 称"不再有用户当前等级概念、不按 rating 筛选",但 `PuzzleProgress.swift:130-146` 的 DifficultyMode(Easy/Hard 按用户 Rating ±200 筛选)已重新引入等级驱动选择。
- [ ] **CLAUDE.md 架构图缺漏** — Settings、Onboarding/LibraryLoadingView、ReviewRoundView(HistoryView/RoundHistoryDetail/ReviewPuzzleView)、PuzzleResultRow 未出现;Persistence 一节缺 `BatchStore`、`DifficultyMode`、`RoundHistory`、`PuzzleLibrary`。CLAUDE.md 还声称 BUSINESS_LOGIC.md 含 "localization transition rules",实际没有。
- [ ] **THIRD_PARTY_NOTICES.md 缺漏** — 资产路径写错(应为 `ios/DailyTactics/...`);10,100 道 Lichess 衍生题库数据无署名/许可条目;App 图标无来源条目;`third_party/lichess/*.png` 无条目且 README 称该目录"含 notices"不实;Android 目录下同一套棋子图无覆盖。
- [ ] **README 断句残缺** — `README.md:105-107` "plus\nPuzzle tier JSON files are generated from…" 句子中断;`rating_puzzles.json`(100 题)被捆绑但无代码引用(死资源);tools/ 3 个脚本只文档化了 1 个;`Project.swift` 的显示名 `iTactics` 无任何文档记载。

## P2 — 测试缺口与工程卫生

### 测试缺口

- [ ] ChessCore 错误路径(FEN 各 error case、isLegal 拒绝易位/过路兵、允许王送将/被牵制子移动)零覆盖。
- [ ] 升变逻辑(apply 升变、`moveNeedsPromotion`、强制后升变)零覆盖 — 一条重放 `o8GIU` 的测试即可抓住 P0 第 1 项。
- [ ] Rating 数学只测了 3 个不等式;K 因子、强制 ±1 最小值、[400,3000] 钳制、钳制后 UI 显示未钳制 delta 的不一致(`TacticsViewModel.swift:404-405`)均未测。
- [ ] 会话失败/重试/review stepping 流程未测;`testHintImmediatelyCostsRating`(`ChessAndPuzzleTests.swift:282-308`)依赖 450ms 实时 sleep,CI 下易 flaky。
- [ ] 持久化行为(RoundHistory 记录、BatchStore、导入回退链)零覆盖 — P0 第 2/3/4 项都是可直接写回归测试的。
- [ ] `testBoardAutoOrientsToPlayerColor`(`ChessAndPuzzleTests.swift:244-253`)没测它名字声称的东西:`progress` 为 nil 时 `loadNextRound` 直接 return,第二次断言检查的还是同一个 session。

### 工程卫生

- [ ] **根目录 `DailyTactics.xcworkspace/` 已提交且已损坏** — `contents.xcworkspacedata` 引用不存在的根目录 `DailyTactics.xcodeproj`;`xcuserdata/.../UserInterfaceState.xcuserstate`(二进制用户状态)也被提交,因为 `.gitignore:6` 的规则只作用于 `ios/` 前缀。
- [ ] **`ios/` 下 Tuist 生成的 `.xcodeproj`/`.xcworkspace` 被提交** — 与 AGENTS.md "Avoid committing generated Xcode state" 自相矛盾,`.gitignore` 未覆盖。
- [ ] **Project.swift 配置** — 资源 glob `DailyTactics/Resources/**` 会把 `.DS_Store`/`.gitkeep` 打进 bundle;无 `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`;App 图标 PNG 带 alpha 通道(App Store 校验会拒);`DEVELOPMENT_TEAM` 硬编码提交在共享 manifest;iPad 在 target 设备里但布局纯 iPhone。
- [ ] **死代码清理** — `TacticsView.swift:9,98-100` 的 `reviewPuzzle` sheet 状态永不赋值;`restart()`、`attachProgress`、`PuzzleLibraryImporter.reset/resetProgress`、`LibraryStateStore` 全套无调用方;`TacticsView.swift:123,227`、`ChessBoardView.swift:78` 注释掉的代码残留。
- [ ] **崩溃风险模式** — 两处 `Dictionary(uniqueKeysWithValues:)` 依赖 `.unique` 约束才不崩(`BatchStore.swift:24`、`ReviewRoundView.swift:80`);`Puzzle.swift:93` `fatalError` / `TacticsViewModel.swift:64` `preconditionFailure` / `Chess.swift:41` `precondition` 构成"单条坏数据即启动崩溃"链;`PuzzleProgress.puzzleId` 无 `.unique` 约束,重复行会导致 `fetchCount` 双计。

## 已确认无需处理(审查时排除)

- ChessCore / PuzzleKit 无架构违规(只 import Foundation,SwiftData 限定在 Persistence/,全部类型 Sendable)。
- 并发无明显缺陷(`@MainActor` 使用一致,无数据竞争、无循环引用)。
- Rating 的 Review 隔离已正确实现:所有 review 路径都不写 Rating。
- Android build 产物未提交到 git(磁盘上的 build/ 已被 ignore)。
- 10,100 道内置题全部通过 `Board.init`/`apply` 重放验证,数据本身无坏行。
