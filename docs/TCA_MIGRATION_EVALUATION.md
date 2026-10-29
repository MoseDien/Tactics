# TCA 迁移评估（含 Settings 试点结果）

本文档记录把 app target 迁移到 The Composable Architecture（TCA, pointfree
swift-composable-architecture 1.26.x）的评估结论，以及已完成的首个试点
（Settings feature）。评估动机是**学习/体验 TCA**，不是修复具体痛点；
策略是试点先行，全量迁移看完试点再决定。

## 结论摘要

- 试点已完成：Settings（表单 + 图表 + 分块下载 + Debug 工具）从
  `@Observable SettingsViewModel` 迁到 `SettingsFeature` reducer，
  行为/布局/文案零变化，15 个 TestStore 测试全绿。
- TCA 与本项目的注入模型可以干净共存：`AppDependencies` 仍是唯一组合根，
  每个 TCA store 在呈现点经 `withDependencies` 桥接（无 liveValue 全局注册）。
- 全量迁移可行，估算 **2–3 个专注周**（含测试重写）；最难的是 Tactics
  训练流（棋盘动画不变量 + 对手回应节奏的 effect 化），约占一半时间。
- 代价：项目引入第一个第三方运行时依赖（含 15+ 传递包）；构建/测试命令
  必须从 `-project` 切到 `-workspace`；新增 `tuist install` 步骤。
- 建议：按"简单 feature 先行、Tactics 最后"的顺序推进（见下文路线）。

## 试点结果（Settings → TCA，已合入）

**新增/改动**：
- `ios/Tuist/Package.swift`（新）：SPM 外部依赖清单（TCA 1.26.2 + swift-dependencies），
  `tuist install` 解析到 `Tuist/Package.resolved`。
- `Project.swift`：app/test target 增加 `.external(name: "ComposableArchitecture"/"Dependencies"/"DependenciesMacros")`；
  下层三个 framework 不加（编译期保证 TCA 不下沉）。
- `Features/Settings/SettingsClients.swift`（新）：5 个 `@DependencyClient`
  客户端（难度/评分历史/库状态/分块下载/Debug 工具）+ `@MainActor` live 桥
  + `Store.settings(dependencies:)` 工厂。
- `Features/Settings/SettingsFeature.swift`（新）：reducer（State/Action/依赖），
  图表派生与全部行为从原 VM 原样搬运。
- `SettingsView.swift`：改为 `@Bindable var store`；`SettingsViewModel.swift` 已删除。
- `HomeView` / `TacticsView` 两处 sheet 呈现点改为 `SettingsView(store: .settings(dependencies:))`。
- `Tests/SettingsFeatureTests.swift`（新）：15 个 TestStore 用例——此前
  SettingsViewModel **零测试覆盖**，试点净增覆盖。

**实测踩坑**（后续迁移直接受益）：
1. Tuist 4 外部依赖是 workspace 里的子工程：构建/测试必须用
   `-workspace DailyTactics.xcworkspace`；`-project` 会报资源 bundle 缺失。
2. TCA 1.26 写法：`var body: some ReducerOf<Self>`；binding 匹配是
   `case .binding(\.field)`（**无** `$` 前缀）；测试发 binding 用
   `.binding(.set(\.field, value))`。
3. `@DependencyClient` 对非抛出、有返回值的端点**强制要求闭包默认值**
   （`var current: @Sendable () async -> DifficultyMode = { .medium }`）；
   `TestDependencyKey` 一致性要手写（`static let testValue = Client()`）。
4. Reduce 闭包在 1.x 是非 MainActor 的：repositories 协议全是 `@MainActor`
   且非 Sendable，live 桥必须经 `@MainActor` 辅助函数访问，不能在
   `@Sendable` 闭包里直接摸 `dependencies.data`。（TCA 2.0 reducer 转
   MainActor 后可简化。）
5. Debug 下 `RoundPolicy.roundDuration == 300` 秒——测试断言状态变化时
   "设置成默认值"会失败（TestStore 视为无变化）。
6. 构建时间：宏插件（SwiftSyntax）首编译约 +20s，之后增量无感；
   冷 clone 需 `tuist install`（联网解析一次）。

## 概念映射（现状 → TCA）

| 现状（@Observable） | TCA 等价物 |
|---|---|
| `AppDependencies`（组合根，`.environment` 注入） | 保留为组合根；`@DependencyClient` 客户端经呈现点 `withDependencies` 注入 |
| `final class` store（19 个） | `@Reducer struct` + `@ObservableState State` + `Store` |
| 展示 VM（Tactics 9 个、Settings、Favorites、Home） | State 计算属性 + view 扩展（试点中 `ratingDomain` 等即此形态） |
| `RoundTracker` 到期 `Task.sleep` 唤醒 | `Effect.run` + 注入 clock 的 sleep + `.cancellable(id:)` |
| `TacticsPacing` 延时常量 | 注入 `Clock`（测试用 TestClock 精确推进） |
| `Fakes.MutableClock` + 50ms 轮询断言 | TestStore 逐步断言 action 序列与状态 diff，无轮询 |
| 视图手写 `Binding(get:set:)` | `@Bindable var store` + `$store.field` + `BindingReducer` |
| `AppDependencies.preview()` | withDependencies 注入 preview 实现（或 store 工厂参数化） |

## 共存规则（已写入 CLAUDE.md）

1. 一个 feature 要么整体 TCA（`<Feature>Feature.swift` + 接收
   `StoreOf<<Feature>Feature>` 的视图），要么整体 @Observable store，不混用。
2. TCA store 只在呈现边界（sheet/推入目的地闭包）经 feature 的静态工厂构造，
   工厂闭包捕获父视图 `@Environment(AppDependencies.self)`；不进 environment、
   不做全局/static store、不注册 liveValue。
3. 未迁移的推入子页保持纯 SwiftUI + AppDependencies；父 feature 迁移后再
   `store.scope` 到子 feature。
4. `import ComposableArchitecture`/`Dependencies` 只允许出现在
   `ios/DailyTactics/Sources/**` 与 `Tests/**`（target 依赖图已编译期强制）。
5. 动画时序不进 reducer：延迟一律注入 Clock/客户端，reducer 里不出现
   `Task.sleep`。
6. 每迁移一个 feature 配套同批 TestStore 测试。
7. 跨 TCA 边界的类型保持 PuzzleKit 的 `Sendable` 值类型。

## 全量迁移成本排序

| 阶段 | 范围 | 规模 | 预估 |
|---|---|---|---|
| ✅ 0 | Settings（VM+View 410 LOC） | 已完成 | — |
| 1 | Onboarding（LibraryLoadingView 55 LOC） | 单 effect + 重试 | 数小时 |
| 2 | Favorites（177 LOC） | 列表加载 + 推入 | 半天 |
| 3 | History/复盘视图（~370 LOC，HistoryGrouper 已纯函数） | 列表 + 回放只读 | 1 天 |
| 4 | Home（VM 31 LOC 但读会话 store） | 与 Tactics 同期做 | 与 5 合并 |
| 5 | **Tactics（最难）**：TacticsTrainingStore 全家 362 + Session/Round/Progress 444 + 9 个展示 VM + 棋盘视图 | 动画不变量（`animatedArrival` 单一派生值）+ 对手回应/节奏交错 effect 化 + 轮窗 effect | 1.5–2 周 |
| — | 合计 | app target 4,999 LOC / 19 store / 88 个既有测试 | **2–3 专注周** |

## 收益（对学习动机）

- 强制依赖注入 + 未 stub 的端点在测试里**响亮失败**（试点 5 个客户端全部如此）。
- TestStore 穷尽式断言：状态变迁逐步可读、可回放；无 50ms 轮询。
- 时间可控：Clock/TestClock 取代真实等待。
- 单一状态变更路径 + reducer 组合，为复杂 feature（Tactics）提供可扩展骨架。
- 行业通用模式经验，可迁移到其他 SwiftUI 项目。

## 风险

- **棋盘动画不变量**：CLAUDE.md 明示"动画信号优先级列表曾反复回归"；
  迁 Tactics 时 `animatedArrival` 派生语义必须原样保留，并靠现有
  棋盘测试兜底。
- **双范式共存期**：两套习惯并存，需靠上文共存规则 + review 纪律。
- **TCA 2.0 在酝酿**：1.25+ 已有弃用批（试点按新写法写，受影响面小）。
- **工具链**：新 clone/CI 依赖 `tuist install` 联网；命令从 `-project` 改
  `-workspace`（文档已更新）。
- **体积/编译**：传递依赖 15+ 包；宏插件冷编译 +20s；binary size 增加
  （静态框架全量链接，对本地 App 影响有限）。
- **文档漂移**：README/AGENTS 曾出现阈值口径漂移（50 vs 3000，本次已修），
  迁移期每批同步文档。

## GO/NO-GO 清单（全量迁移决策点）

- [x] 两个 sheet 入口（Home 齿轮 / 训练页齿轮）行为与迁移前一致（模拟器验证）
- [x] TestStore 套件无轮询全绿（15/15）
- [x] `grep import ComposableArchitecture` 在 ChessCore/PuzzleKit/TacticsData 为空
- [x] 构建/测试全绿 + SE destination 编译通过
- [x] 文档同步（本文件 + CLAUDE/AGENTS/README/notices）
- [ ] 构建时间增幅长期可接受（试运行一两周后确认）
- [ ] 认可 Tactics 阶段 1.5–2 周的投入，且排期允许

全部勾选 → 按路线推进阶段 1→5；任一不成立 → 试点保留（回滚面仅
Settings 一组文件 + manifest），其余 feature 维持 @Observable。

## 回滚

试点是一组自洽提交：`Tuist/Package.swift`、`Package.resolved`、
`Project.swift` 依赖段、`Features/Settings/` 三个新文件 + 视图/呈现点改动、
测试文件、文档。revert 即回到纯 @Observable 形态，无数据/行为残留。
