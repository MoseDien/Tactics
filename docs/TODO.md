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
- [x] `PuzzleLibraryImporter.reset/resetProgress`、`LibraryStateStore.isImported/markImported` 无调用方 — 已删除(2026-09-03 清理);`LibraryStateStore` 收敛为仅含 `importedKey` 的枚举。

## 架构整改(2026-09-01 登记,2026-09-02 完成)

四模块拆分全部落地,每阶段独立提交且测试全绿:

- [x] **阶段 1 ChessCore 框架**:棋规独立成 static framework,hostless `ChessCoreTests`(15 个棋规测试)。
- [x] **阶段 2 PuzzleKit 框架**:实体/策略/端口;`RoundSelector` 纯函数化(注入 shuffle);`BatchPolicy`/`BatchWindow`/`BatchLookup` 替代静态常量;六个 repository 协议确立远端 API 替换接缝。
- [x] **阶段 3 TacticsData 框架**:唯一 import SwiftData 的模块;`SwiftDataRepositories` 单适配器实现四个数据端口;`BundledPuzzleSource`(`Bundle.module`)承载 10 个 tier JSON——10k 重放与导入测试不再依赖 test-host;`ModelContainerFactory` 含旧 store 恢复路径;`fetchUnattemptedRound` 删除,选题走 `RoundSelector`。
- [x] **阶段 4 组合根**:`AppDependencies`(.live()/.preview())经 environment 注入;`BatchTracker`(可注入 clock + 单次到期唤醒)删除 `batchExpiryTick`;`TacticsPacing` 可注入;app target 零 `import SwiftData`,全部静态单例删除。
- [x] **阶段 5 测试加固**:RoundSelector×7 / BatchWindow×3 / BatchTracker×3 新测试;`MutableClock`/`InMemoryBatchState` fakes;CLAUDE.md/README/BUSINESS_LOGIC 同步模块树与新路径。

最终测试规模:55 个(10 app + 15 ChessCore + 21 PuzzleKit + 9 TacticsData)。

## 题库分块下载(2026-09-03 完成)

按 2026-09-01 计划落地:数据源 https://mosedien.github.io/Tactics/puzzles/

- [x] `tools/export_puzzle_chunk.py`:1000 题/块导出 + `exported_puzzles` 标记(DB 驱动序号,`--sequence 0` 导内置块);已导出 0000–0010。
- [x] 内置资源替换:`puzzle-0000.json` 进 TacticsData bundle,10 个 tier 文件删除;`BundledPuzzleSource.decodeBundledChunk()`。
- [x] PuzzleKit 端口:`PuzzleChunkFetching` / `PuzzleProvisioning`。
- [x] TacticsData 实现:`RemotePuzzleCatalog`(部署地址)/`RemotePuzzleFetcher`(URLSession 注入,404=未发布)/`ChunkSequenceStore`(UserDefaults 序号 + 会话级 404 闩锁)/`LibraryProvisioner`(池不足→拉取→去重插入→缓存失效);`SwiftDataRepositories.invalidateLibraryCache()`。
- [x] 触发点:启动选题前(`TacticsView.task`)与新 batch(`startNextBatch`)各一次;Settings 展示块序号/题目数。
- [x] 测试 +6(FakeChunkFetcher:拉取/缓存失效/跳过/404 闩锁/错误吞掉/去重、序号单调);61 全绿;真实网络冒烟通过。

## 下载功能测试方法与代码清理(2026-09-03)

**手动测试下载的路径**(Debug 构建生效,Settings → 调试工具):
- **「回到初始状态」**(destructive,带确认):`deleteAllData()`(四表全清,含已下载块)+ `AppPreferences.wipeAll()`(rating/batch/难度/序号/gate 六个 key 全清)→ gate 清空后 RootView 自动路由回导入页重导内置 0000 块——等价删除重装,无需重启。(同日加入的「立即下载下一块」「重置数据块序号」已按需求移除,`ChunkSequenceStore.reset()` 一并删除;测试下载用「回到初始状态」+「清空未尝试题池」组合覆盖。)
- 既有工具:「清空未尝试题池」(批量标记已尝试,测自动触发路径:排干 → 冷却结束开新组 → 自动拉块)。
- 前置:`RemotePuzzleCatalog.baseURL` 指向 https://mosedien.github.io/Tactics/puzzles/ ,块 0001–0010 已发布。
- 典型闭环:回到初始状态 → 确认「数据块 0 · 1000 题」→ 清空未尝试题池 → 冷却结束开新组 → 自动拉块 → 「数据块 1 · 2000 题」。

**清理与 simplify 审查**(4 个并行 agent:复用/简化/效率/层次):
- [x] 批量 `markAttempted(_ ids:)` 下沉到 repository:排干从 ~1000 次 fetch+save(O(n²) 扫描)降为 1 fetch + 1 save;`drainUntriedPool` 收为一行调用
- [x] 删除排干里的无效缓存失效与全库重取(计数用 `ids.count`)
- [x] `invalidateLibraryCache()` 从协议撤回具体类(只为 debug 视图提升到端口是错误层次)
- [x] 删除死的升变回归测试(tier JSON 已不存在,静默 vacuous)→ 用内置块真实升变题 `fEIaZ` 重建为 `testPromotionPuzzleRequiresExactPromotionPiece`;删 `ImportTestPuzzle` DTO
- [x] importer 单块化:去掉单元素数组嵌套循环,失败返回语义改为 0/1
- [x] VM 删 `pickRandomBatch`(二次 shuffle)与 `dataset` 死存储;importer/VM/协议注释里 "tiers" 措辞全部更正;`LibraryLoadingView` 文档注释同步
- [x] `BundledPuzzleSource` public 面收窄到实际消费;`ChunkSequenceStore.reset()` 注释与编译现实对齐
- [x] alert 改用专用 `debug.notice_title`(不再复用 Section 标题)
- 跳过:`#if DEBUG` 四处分散(Swift 结构所迫,合并反而加间接层)、`Binding(get:set:)` 驱动 alert(已是 optional→bool 的标准写法)

61 测试全绿。

## 棋子移动动画(2026-09-04~05 完成)

三次方案迭代,最终收敛为「单一 arrival 映射」结构(`9d81d92`→`9836018`→`0bf936e`):

- [x] **v1 两阶段状态(废弃)**:`travelOrigin` 覆盖 + onChange/task 时序,实测瞬移——走子必换棋子 id,`.animation(value:)` 对新插入视图永不触发,机制性失效。
- [x] **v2 插入式 transition**:走子 = remove+insert,插入 transition 用偏移(原格 offset − 终格 offset)滑入;60fps 录屏逐帧验证 13 帧连续位移。
- [x] **曲线修正**:easeInOut 慢启动造成「顿一下再窜」(前 3 帧仅 18% 路程)→ `easeOut(0.18)` 首帧 27% 位移。
- [x] **错着动画修复**:错吃落到对手来格时从对手起点飞入(preview 优先级修正);被吃子幽灵回放(snapback 帧抑制其余匹配);回弹瞬移改滑回(VM 同渲染提供反向 arrival);snapback 用后即清(否则本题动画全灭——真 bug)。
- [x] **setup/开局语义拆分**:载入(淡入,generation 编入 id 防横飞)、对手第一步(正常滑入)分开;`1d0d947`。
- [x] **动画开关**:debug 两 Toggle(移动/载入),`PieceAnimationStore`,缺省开。
- [x] **重构收敛**:三参数优先级列表 → 单一 `animatedArrival` 映射;`BoardAnimation` 值分组;魔术字符串 → `BoardStamp`;`TacticsControlsView` 假视图 → 五个真子视图;`attemptMove` 拆三个具名 helper(`0bf936e`,行为零变化,录屏逐帧与基线一致)。

验证方法论:60fps `recordVideo` + AVFoundation 抽帧 + 棋盘区域逐帧像素差分(动画插值/单帧瞬切可区分);模拟器无法注入点击的场景靠结构推导。

## 文件拆分与可读性(2026-09-05)

- [x] 全仓库 >300 行文件清零:`Chess.swift`(505)→ Pieces/Square/Board/BoardRules;`TacticsViewModel`(550)→ 主文件 + Batch/Session/Rating extension;`TacticsView`(319)→ 主 + Header + Controls(`2b308e5`)。跨文件 extension 的可见性从 private 放宽到默认 internal。

## Storyboard 启动画面(2026-09-05 完成)

- [x] `DailyTactics/Resources/LaunchScreen/LaunchScreen.storyboard`:官方模板结构(document type 必须是 `...Storyboard.XIB`,`.Storyboard` 会被 ibtool 误报 "missing SDK"),水平 UIStackView 内两个 label——红 "i"(sRGB 220,20,60)+ 黑 "Tactics",boldSystem 36pt,居中。`Project.swift` 的 `UILaunchScreen: [:]` 换为 `UILaunchStoryboardName`。录屏 + 像素验证(626 红 / 6737 黑像素,词首红 i)。

## 首启导入页用 app 字标(2026-09-05 完成)

- [x] 新 `AppWordmark`(Tactics 目录):红 "i"(crimson 220,20,60,与启动 storyboard 同色)+ 黑 "Tactics",bold 36pt,一处实现两处同步。`LibraryLoadingView` 头部的 crown 图标 + "iTactics" 标题换成该字标——首启导入读作启动的延续。注意:`Text` 拼接用 `(Text+Text)` 而非字符串插值内嵌 styled Text(插值会把内层样式压平,红 i 丢失);静态截图验证需录屏抓导入瞬间(导入 ~1s 即跳转)。

## Hint 二段行为(2026-09-05 完成)

- [x] 第一次点 Hint:高亮期望着法(现有行为,立即按失败结算);再次点:自动走出该着法(升变直接采用答案棋子,不弹选择器)。评分只结一次(惩罚在第一段已落),auto-play 后正常进对手回复链路。配套修复:错着预演进行中触发 auto-play 时,预演与真着同帧正确衔接(attemptMove 开头统一清预演)。棋盘点击会清高亮 → 再点 Hint 回到显示段(「继续自己下」的信号)。

## History 增强:按周分组 + 整组复盘(2026-09-05 完成)

- [x] `HistoryGrouper`(纯函数,注入 Calendar/now):rounds 按周分桶倒序;最近三周相对措辞(本周/上周/前周),更早用日期区间;`Week.summary` 出周汇总(题数/对/错)。
- [x] `HistoryView` 重写:List Section 按周;行 = 周几+时刻 + 当行结果标记串(✓/×/虚圈)+ `4/5` 胶囊(全对绿);无障碍聚合标签。删 `RoundHistoryDetail` 中间层。
- [x] `BatchReviewView`(新):历史 batch 的连续复盘播放器——纯 dataset(不碰评分/repo/tracker),单题步进(同 ReviewPuzzleView 语义)+ 题间导航(末题循环),结果行高亮当前题。
- [x] 测试 +6(grouper:跨周边界/同周合并/倒序/汇总/相对标题/区间标题,固定 Monday-first 日历);69 全绿;iPhone 16e(最小可用)编译通过。

## 收藏功能(2026-09-05 完成)

- [x] 数据层:`PuzzleProgress` + `isFavorite`/`favoritedAt`(存量行默认 false,schema 未发布无需迁移);端口 `setFavorite/isFavorite/favoriteIDs`;SwiftData 实现(fetch-or-insert,`favoriteIDs` 单谓词 fetch)。
- [x] VM:`isCurrentFavorite`(载题刷新)+ `toggleFavorite`(guard 完成态;play/review 一致;不碰评分)。
- [x] 首页按钮:flip 右边 heart 轮廓(粉=已收藏/灰=未收藏,无 fill),未完成时 opacity 0 + 不可点(占位防布局跳动);无障碍 favorite/unfavorite。
- [x] FavoritesView(Settings → 历史 下方):难度星级列 + 题号/rating/练习数 + 主题胶囊,点开 `ReviewPuzzleView`(从 git 恢复,上次 History 重写误删了它的最后引用);空态 ContentUnavailableView + 引导文案。
- [x] 主题名本地化 8 键 + favorites/tactics/settings 键(en/zh-Hans 同步)。
- [x] 测试 +4(数据层 3:建行/更新、过滤、重置清空;app 1:完成前 no-op、完成收藏持久化、再点取消);73 全绿;iPhone 16e 编译通过。

## 走子动画按距离自适应时长(2026-09-05 完成)

- [x] 需求:固定 180ms 对短距拖沓/长距仓促;改为恒速模型 `duration = 90ms + 45ms/格`(切比雪夫距离,1 格 135ms、7 格 405ms),Lichess 同族惯例。参数收在 `BoardAnimation.slideBaseDuration/slideDurationPerSquare` 单点可调。
- [x] 方案迭代:**per-piece modifier 动画被录屏证伪**——`AnyTransition.modifier(active:identity:)` + modifier 内 `.animation(value: settled)` 的插值需要容器事务 tween,State 首帧即终值、onAppear 同帧置真不产生变化 → 实测零中间帧瞬移。退回**容器动画驱动**(可靠路径),时长取本手 arrival 的**最长距离**(易位双子微差 ≤1 格,牺牲换可靠)。
- [x] 验证:60fps 录屏,开局 1 格着法连续 9 帧(~150ms)位移、easeOut 减速尾部清晰;此前同场景为 0 帧。附:验证脚本修了 paint 帧未更新 prev 导致全屏误报的 bug。73 测试全绿。

## App Store 上架:代码侧准备(2026-09-05 完成)

- [x] **PrivacyInfo.xcprivacy**(app bundle):`NSPrivacyTracking=false`、无收集数据类型、UserDefaults 申报 `CA92.1`。无第三方 SDK,清单极简。上架硬性要求(2024 起)。
- [x] **加密出口合规**:`ITSAppUsesNonExemptEncryption = false`(仅 HTTPS,豁免类)——免每年 App Store Connect 加密问卷。
- [x] **iPhone 收窄**:`TARGETED_DEVICE_FAMILY = 1`(布局按 iPhone 设计;iPad 待后续布局专项)。原「iPad 设备族」开放项就此关闭。
- [x] **THIRD_PARTY_NOTICES** 题库路径修正(tier 文件 → `puzzle-0000.json` + 按需块)。
- 验证:产物 Info.plist 三键落位(Privacy 清单打包/加密 false/UIDeviceFamily=[1]),73 测试全绿,冷启动正常。

**上架余项(非代码,App Store Connect)**:6.9"/6.5" 截图、描述/关键词(建议 Games→Board)、隐私政策 URL(landing page 加一页:不收集数据/本地存储/仅静态 CDN 拉题库)、年龄分级(4+)、版权行、TestFlight 走一轮真机、归档 bump build。

## 仍开放(有意保留或待产品决定)

- **`tuist test` 不可用(Tuist 4.197)**:该命令只解析 workspace 级 scheme,而本项目不再生成 workspace(生成文件已退出 git,见工程卫生一节)。曾尝试 `Workspace.swift` manifest 定义 workspace scheme:buildAction 的 `.project(path:, target:)` 可用,但 testAction 的 `TestableTarget` 只接受字符串、lint 又强制要求带 project path,二者矛盾,无法通过。验证命令已改为 `xcrun xcodebuild test -project DailyTactics.xcodeproj -scheme DailyTactics`(三份文档已同步)。若未来升级 Tuist 解决此矛盾,可恢复 `tuist test`。
- ~~全局 UserDefaults 静态命名空间~~ **已解决(2026-09-02 架构整改阶段 4)**:`BatchStore`/`DifficultyModeStore`/`LibraryStateStore` 全部改为注入实例(`UserDefaultsBatchStateStore` 等),经 `AppDependencies` 组合根分发;`BatchTracker` 持有可注入 clock,`batchExpiryTick` 轮询 hack 已删除,测试用 `MutableClock`/`InMemoryBatchState` 无需 sleep。
- **ViewModel 内三处 pacing 延时**:已收敛为可注入的 `TacticsPacing`(测试用 `.instant`),`PuzzleSession` 保持纯函数。进一步拆 BatchCoordinator 留待有实际需要时。
- ~~iPad 设备族~~ **已解决(2026-09-05 上架准备)**:`TARGETED_DEVICE_FAMILY = 1` 收窄为 iPhone;iPad 支持待后续布局专项再放开。
- **SwiftData schema 迁移**:无 `VersionedSchema`/`SchemaMigrationPlan`。当前 schema 尚未发布(1.0 未上架),首次发布前若改 model 需补迁移计划。
- **`PuzzleProgress.puzzleId` 无 `.unique` 约束**:加约束需要迁移;在发布前补上最合适(当前 fetch-then-insert 模式实际防止了重复)。
- ~~`rating_puzzles.json`~~ 已删除(2026-09-03 清理,确认无代码引用)。

---

## 功能计划(进行中)

### Rating 历史曲线(2026-08-31 完成 — 已包含在 55 测试内)

目标:记录 rating 随时间的变化,在 Settings 中用曲线展示;每个 batch 完成时记录一次。

- [x] **独立 `RatingSnapshot` SwiftData 模型**(`TacticsData/Sources/Models/RatingSnapshot.swift`):`id`/`recordedAt`/`rating`,不与 `RoundHistory` 关联——为将来每题一记或 batch 之外的 rating 事件(如重新评估)留出演进空间。
- [x] **记录时机**:`TacticsViewModel.markCurrentSolved()` 在 batch 最后一题结算完成、rating 更新之后写入快照(快照值包含最后一题的 delta);复用 `roundRecorded` 防重逻辑保证每个 batch 恰好一条,Review 重解不重复。Hint 早退路径同样记录。
- [x] **Settings 曲线**:新 Section 用 Swift Charts(`LineMark` + monotone 插值)展示 `recordedAt` → `rating`;空数据占位文案;en/zh-Hans 同步补 key。
- [x] **容器注册**:`DailyTacticsApp` 与 `TacticsView` preview 的 `modelContainer(for:)` 补 `RatingSnapshot.self`。
- [x] **回归测试**:单题 batch 干净解出 → `ratingHistory()` 恰 1 条且等于结算后的 rating;Review 重解后仍 1 条。
- [x] 当前 Rating 的存储不变:仍是 `UserDefaults` 标量(`dailytactics.userRating`),快照只追加时间序列。
