# 减重助手 (WeightCoach)

一个可自行设定目标的 iOS 营养、运动与体重管理 App。

[公开版安装、独立签名、App Group 与私有桥接配置指南](docs/COLLEAGUE_SETUP.md)

- 从 **Apple 健康** 读取体重、体脂率、身高、年龄、性别、活动能量
- 动态计算每日总消耗（TDEE）和减重所需热量缺口，实时显示 **今天还能吃多少千卡**
- 四种饮食记录方式：**极速拍照 / 账单识别**（可选 Mac mini 私有桥）、**扫商品条形码**（优先本地缓存 / Open Food Facts，查不到可直接本机 OCR 扫包装营养表）、**搜索常见食物**、**手动输入**
- 体重 / 体脂趋势图、目标轨迹对比、按当前速度预计达成日期
- 7 / 30 天热量、缺口与蛋白质 / 碳水 / 脂肪趋势，本周缺口统计截至昨天
- 不戴手表时可手动记录篮球、跑步等运动，并避免与 Apple 健康活动能量重复计算
- App、通知和小组件支持跟随系统、简体中文、繁體中文和 English
- 记录的体重和饮食热量会回写到 Apple 健康

## 首次运行

1. **同意 Xcode 许可**（本机还没同意过，编译前必须做一次）：
   ```bash
   sudo xcodebuild -license accept
   ```
2. 用 Xcode 打开 `WeightCoach.xcodeproj`。
3. 在 target **WeightCoach → Signing & Capabilities** 里选择你自己的 Team（真机运行需要；HealthKit 能力已配置好）。
4. 选择你的 iPhone 运行（HealthKit 数据在真机上才完整；模拟器里健康数据为空，可用手动记录测试）。
5. 首次启动会请求 **健康数据授权**；首次拍照时再申请 **相机权限**。
6. 拍照、压缩、结果核对和营养记录都在 App 内完成，不会跳转到 ChatGPT，也不在 App 内保存 API Key。若要启用真实自动识别，请按 [Mac mini 私有桥接指南](docs/BRIDGE_SETUP.md) 填写每位使用者自己的 HTTPS 私有地址；未配置时照片不会上传，仍可使用常见食物、条码、包装 OCR 和手动录入。

模拟器可用下面的启动参数检查完整的极速拍照交互（结果明确标记为演示数据）：

```bash
xcrun simctl launch <UDID> com.lukegogogo.WeightCoach -demoData -demoCapture
# 包装营养表：演示 OCR → 核对标橙字段 → 缓存商品 → 选择食用量
xcrun simctl launch <UDID> com.lukegogogo.WeightCoach -demoData -demoNutritionLabel
# 7 / 30 天趋势与本周缺口演示
xcrun simctl launch <UDID> com.lukegogogo.WeightCoach -demoData -demoTrends
```

包装营养表识别由 Apple Vision 在设备上完成，支持常见中英文标签、kJ 转千卡、每份 / 每 100 克 / 每 100 毫升 / 整包 / 每个以及基础双列标签。`%DV` 不会被当成营养含量；低置信或近似值必须人工核对。确认后的商品会按条码保存在 SwiftData，之后重复扫码直接进入食用量页面。原始标签照片不会保存或上传。

餐厅账单或菜单识别不会把账单照片保存为饮食缩略图，也不会把整单默认算成一个人吃完。保存前必须选择整单、1/2、1/4、3/4，或逐项核对实际吃到的内容。单张照片无法可靠测量重量、隐藏烹调油或所有定制项，所有 AI 结果都应在 App 内确认。

## 热量计算逻辑

- **基础代谢（BMR）**：有体脂率时用 Katch-McArdle 公式（按瘦体重），否则用 Mifflin-St Jeor。
- **每日总消耗（TDEE）**：默认（计入手表活动能量）= BMR × 1.1（食物热效应）+ Apple Watch 实测全天活动能量——实测值**替代**活动系数而非叠加，避免把日常活动算两遍；预算随当天活动量实时增长。关闭手表模式则 = BMR × 活动系数。
- **每日缺口** = 剩余公斤数 × 7700 ÷ 剩余天数，动态调整并限制在 250–1000 千卡的安全区间。
- **今天还能吃** = TDEE − 缺口 − 已摄入，且预算不低于男 1500 / 女 1200 千卡的安全底线。

> 估算仅供参考，不构成医疗建议。

## 代码结构

```
WeightCoach/
├── WeightCoachApp.swift        # 入口，SwiftData 容器
├── Models/                     # FoodEntry / WeightEntry (SwiftData)、ProfileStore（档案与目标）
├── Health/HealthKitManager.swift  # 健康数据读写
├── Engine/CalorieEngine.swift  # BMR / TDEE / 缺口 / 预测
├── Services/                   # 可替换识别端、图片准备、本地营养表 OCR/解析、商品写入/缓存
└── Views/                      # 今日仪表盘、饮食记录、体重趋势、设置
```

## 隐私与许可

- 仓库使用全新的公开历史，不包含原开发仓库的提交记录、私人桥接地址、健康数据或内部审查会话。
- `-demoData` 注入的体重、饮食与运动记录均为虚构演示数据。
- 不要提交 `WeightCoach/BridgeConfigLocal.plist`、API Key、访问令牌、个人服务 URL、健康数据导出或真机日志。
- USDA FoodData Central 与 Open Food Facts 的数据许可和归属见 [第三方数据说明](THIRD_PARTY_NOTICES.md)。
- 本项目按 [MIT License](LICENSE) 开源。
