# WeightCoach（减重助手）— AI 协作指南

给接手本项目的 AI 编码助手：这份文件包含你无法从代码中直接推断的上下文、决策原因和操作命令。改动核心逻辑前请先读完。

## 项目背景

- WeightCoach 是可自行配置目标的个人营养、运动与体重管理 App。新安装必须先完成 onboarding，不得预置任何真实用户的身体数据。
- App 支持简体中文、繁體中文与 English，并可读取 Apple Watch / Apple Health 数据。
- 公开仓库：https://github.com/xjtuyanshi/WeightCoach-Public 。每位开发者都必须使用自己的签名、Bundle ID、App Group 与私有识别桥。

## 技术栈与结构

SwiftUI + SwiftData，iOS 17 起，Swift 5 语言模式（**不是** Swift 6 严格并发），Xcode 26。

```
WeightCoach/
├── WeightCoachApp.swift      # 入口：ModelContainer + 两个环境对象
├── Models/                   # FoodEntry、WeightEntry（SwiftData @Model）；ProfileStore（ObservableObject，UserDefaults 持久化）
├── Health/HealthKitManager.swift   # @Observable；HealthKit 读写全在这
├── Engine/CalorieEngine.swift      # 纯函数：BMR/TDEE/缺口/预测
├── Services/                 # FoodRecognitionProvider（可替换识别端）、OpenFoodFactsService（条码）、统一食品写入/缓存
├── Support/DemoMode.swift    # 模拟器演示数据（启动参数触发）
└── Views/                    # 每个 Tab 一个文件 + 录入 sheet
```

注入约定（有意混用，别"统一"它）：`HealthKitManager` 是 `@Observable`，走 `.environment()` / `@Environment(HealthKitManager.self)`；`ProfileStore` 是 `ObservableObject`，走 `.environmentObject()` / `@EnvironmentObject`。

## 构建 / 运行 / 验证

```bash
# 完整构建（模拟器，无需签名）
xcodebuild -project WeightCoach.xcodeproj -scheme WeightCoach \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  build CODE_SIGNING_ALLOWED=NO

# 快速类型检查（几秒，不出产物；在 WeightCoach/ 源码目录下执行）
xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios17.0-simulator \
  WeightCoachApp.swift Models/*.swift Health/*.swift Engine/*.swift Services/*.swift Views/*.swift Support/*.swift

# 模拟器运行（演示模式：注入示例饮食+体重数据，跳过 HealthKit 授权弹窗）
xcrun simctl launch <UDID> com.lukegogogo.WeightCoach -demoData -uitab 0   # -uitab 0..4 直达对应 Tab
# 自动打开演示餐盘，验证图片准备 → 自动识别 → 确认：
xcrun simctl launch <UDID> com.lukegogogo.WeightCoach -demoData -demoCapture
# 自动打开一句话补记，验证文字解析 → 逐项核对 → 日期/餐次：
xcrun simctl launch <UDID> com.lukegogogo.WeightCoach -demoData -demoSentenceBackfill
# 自动打开演示餐厅账单，验证菜品识别 → 整单食用比例 → 逐项确认：
xcrun simctl launch <UDID> com.lukegogogo.WeightCoach -demoData -demoReceipt
# 自动打开演示包装营养表，验证本机 OCR 解析 → 低置信核对 → 商品缓存 → 份量：
xcrun simctl launch <UDID> com.lukegogogo.WeightCoach -demoData -demoNutritionLabel
# 自动打开运动补记并注入篮球示例，验证净活动热量与 Apple 健康去重说明：
xcrun simctl launch <UDID> com.lukegogogo.WeightCoach -demoData -demoExercise
# 自动打开常见食物并预选一个大号水煮蛋，验证标准份量 → 可食克重 → 营养换算：
xcrun simctl launch <UDID> com.lukegogogo.WeightCoach -demoData -demoCommonFood
# 把“常吃与最近”移到今日页顶部，验证 30 天排序、一键再记与撤销：
xcrun simctl launch <UDID> com.lukegogogo.WeightCoach -demoData -demoRepeatFoods
```

模拟器注意：无摄像头（拍照/实时扫码不可用，扫码页会自动降级为手动输码）、无健康数据（所以有 DemoMode）。真机才能完整测 HealthKit 和相机。机器上已有 iPhone 17 Pro 模拟器（iOS 26.5）。

## UI 交互验收门槛（强制）

- 构建成功和单元测试通过只能证明代码完整性，**不能**证明按钮、表单、弹窗、导航或手势真的可用。
- 凡是修改用户可见交互，或修复“点击后发生错误行为”的问题，在声称完成、安装真机或合并前，必须通过模拟器、浏览器或真机的真实 UI 自动化实际操作该路径；至少点击本次改动的控件、同一容器内的相邻/破坏性控件，以及保存后的重试或返回路径。
- 每条 UI 验收必须读取操作后的可见状态，并保留至少一种证据（截图、录屏、可访问性树或 UI 测试结果）。只看源码、Preview、编译日志或单元测试不得标为“交互已验证”。
- 能在现有 UI 测试 target 中自动化的回归必须加自动化用例；没有 UI 测试 target、且新增 target 会涉及工程配置时，不得手改 `project.pbxproj`，应先用 Computer Use 做可重复的真实点击验收，并把新增 target 作为独立工程变更处理。
- HealthKit、相机、通知、麦克风、后台恢复等硬件/系统行为必须再做真机验收。模拟器通过时只能明确写“模拟器交互通过”。
- 若环境阻塞导致真实交互没有执行，必须明确写“未验证”和唯一阻塞；不得用 `BUILD SUCCEEDED`、安装成功或进程存在替代产品验收结论。

## 核心业务决策（改前三思）

1. **TDEE 用「替代模型」**：开启手表活动能量时 `TDEE = BMR × 1.1(仅食物热效应) + 全天活动能量`，活动系数**不参与**；关闭时才用 `BMR × 活动系数`。原因：Apple Watch 的 activeEnergyBurned 覆盖全天所有活动（不只锻炼），若叠加久坐系数 1.2 会把日常活动算两遍（多算 150-300 千卡/天）。这是一次审查修复的结论，别改回叠加模型。
2. **BMR**：有体脂率用 Katch-McArdle（370 + 21.6×瘦体重），否则 Mifflin-St Jeor。
3. **每日缺口动态化**：`剩余kg × 7700 / 剩余天数`，钳位 [250, 1000] 千卡；预算下限男 1500 / 女 1200。
4. **数据优先级**：HealthKit 数据优先，ProfileStore 里的身高/年龄/性别只是兜底；体重取 HealthKit 与本地记录中较新者。
5. **AI 识别**：App 不跳转到外部聊天界面，也不在 iPhone 客户端保存云端 API Key。图片识别只依赖 `FoodRecognitionProviding`，一句话补记只依赖独立的 `FoodTextRecognitionProviding`；二者都通过每位使用者自己的 Mac mini 私有桥使用已登录的 ChatGPT 会话，客户端不得携带 prompt、API Key 或任意命令字段。文字原句只通过 Codex stdin 传递，不进进程参数或服务日志；文字请求使用规范 UUID v4，关闭页面或重新估算时必须以同一 ID 调用鉴权取消端点并先释放旧任务，避免占用单任务槽。日期和餐次由 App 决定且必须单独确认，所有文字估算都必须逐项人工确认后才调用 `FoodEntryWriter`。确认后编辑名称、份量或热量必须撤销该项确认并清空旧的派生营养值。不得把演示 Provider 当真实识别，也不得恢复客户端 Claude/OpenAI API。任何未来凭据仍只能进钥匙串，绝不硬编码、不进 UserDefaults、不进仓库。
6. **条码**：本地 `FoodProduct` 缓存优先，未命中再查 Open Food Facts v2（免 Key，必须带自定义 User-Agent；`serving_quantity` 可能是字符串，解析用 JSONSerialization 容错）。仍查不到 → 直接扫描包装营养表：Apple Vision 本机 OCR，规则解析必须排除 `%DV`，低置信/近似值必须由用户确认，按条码缓存后下次秒开。原始标签照片不持久化、不上传。手动只填热量时营养素记 nil（别按 100g 折算）。
7. 所有饮食记录会回写 HealthKit `dietaryEnergyConsumed`，体重/体脂回写对应类型。

## 工程文件注意事项

- pbxproj 是 objectVersion 77 的 **PBXFileSystemSynchronizedRootGroup**：`WeightCoach/` 文件夹里新建文件自动进 target，**不需要也不要手改 pbxproj 加文件引用**。
- entitlements 在 `WeightCoach.entitlements`（与 xcodeproj 同级，不在源码文件夹里），HealthKit capability 已配置。
- Info.plist 由构建设置生成（GENERATE_INFOPLIST_FILE + INFOPLIST_KEY_*），健康/相机/相册用途描述都在 target 构建设置里。
- SwiftData 模型只在主线程改。`FoodEntry` 保存 HealthKit 饮食样本 UUID，删除/撤销时必须先删对应远端样本；远端删除失败时保留本地记录。

## 待办候选

可选 LiDAR/多角度精确扫描与 Watch App。LiDAR 不能成为默认极速记录路径；涉及真实相机、HealthKit 或设备桥接的改动必须在对应真机上单独验收。
