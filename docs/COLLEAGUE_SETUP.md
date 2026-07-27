# 公开版自建配置指南

这份指南适用于从公开仓库 clone WeightCoach、改成自己的签名与设备配置，并在
自己的 iPhone 上运行。每位使用者都应拥有独立的
Apple 开发者身份、App Group 和 AI 桥接；不要复用仓库作者的私人设备、地址、
ChatGPT 订阅或任何凭据。

## 1. 获取公开仓库

clone 默认分支：

```bash
git clone https://github.com/xjtuyanshi/WeightCoach-Public.git
cd WeightCoach-Public
git switch main
```

本公开版按仓库根目录的 [MIT License](../LICENSE) 授权，可以使用、修改与分发；
软件按原样提供，不附带任何担保。

## 2. 开发环境

- Xcode 26
- iOS 17 或更高版本
- Swift 5 语言模式
- 真机测试需要可用于签名的 Apple Developer Team

用 Xcode 打开 `WeightCoach.xcodeproj`。不要手工编辑 `project.pbxproj`；本工程使用
synchronized folder，新文件会由 Xcode 自动收录。

## 3. 改成自己的签名与标识

在 Xcode 的 **Signing & Capabilities** 中完成配置，不要继续使用作者的标识：

1. 为 App target `WeightCoach` 和 Widget target `WeightCoachWidgetExtension`
   选择你自己的 Apple Developer Team。
2. 为 App 设置一个唯一 Bundle ID，例如
   `com.yourname.WeightCoach`。
3. 为 Widget 设置另一个唯一 Bundle ID，例如
   `com.yourname.WeightCoach.WeightCoachWidget`。
4. 在你自己的 Apple Developer 账号中注册一个唯一 App Group，例如
   `group.com.yourname.WeightCoach`，并把同一个 App Group 同时添加到 App 与
   Widget target。

App Group 字符串必须在以下位置完全一致：

- `WeightCoach.entitlements`
- `WeightCoachWidgetExtension.entitlements`
- `WeightCoach/Support/AppLanguage.swift` 中的
  `AppLanguageStorage.appGroupIdentifier`
- `WeightCoach/Services/WidgetBudgetPublisher.swift` 中的
  `WidgetBudgetPublisher.appGroupIdentifier`
- `WeightCoachWidget/WeightCoachWidget.swift` 中的
  `WidgetBudgetStorage.appGroupIdentifier`

少改任何一处都可能导致语言设置或“今日还能吃”小组件无法在 App 与 Widget 间共享。

## 4. HealthKit

App target 必须保留 **HealthKit** capability；Widget target 不需要 HealthKit。
首次真机启动时，按系统提示授权需要的健康数据。模拟器没有完整健康数据，只适合
界面和演示模式验证，不能代替真机 HealthKit 验收。

如果更换了 Team、Bundle ID 或 provisioning profile，请在
**Signing & Capabilities** 中再次确认：

- App target 的 HealthKit capability 仍存在；
- App 与 Widget target 都使用同一个新 App Group；
- 两个 target 的签名均无错误。

## 5. AI 拍照识别是每人独立配置

WeightCoach 不在 iPhone App 内保存云端 API Key，也不会让 fresh clone 自动连接
作者的 Mac mini。需要 AI 拍照识别时，每位使用者必须使用：

- 自己控制的 Mac；
- 自己的 Tailscale 私有网络与 HTTPS 地址；
- 自己的 ChatGPT / Codex 登录和订阅权限；
- 自己部署并维护的 `MacMiniBridge/`。

不要共享作者的 Tailscale 地址、ChatGPT 订阅、登录会话、Token、API Key 或服务日志，
也不要把无身份验证的桥接开放到公网。完整部署和 App 内配置步骤见
[私有 AI 识别桥接配置](./BRIDGE_SETUP.md)。

fresh clone 未配置桥接时，AI 拍照识别会明确显示不可用；以下功能仍然可用：

- 手动录入；
- 常见食物搜索；
- 商品条码查询；
- Apple Vision 本机营养标签 OCR。

如果要在自己的开发机预置桥接地址，只能从
`Config/BridgeConfigLocal.example.plist` 复制出
`WeightCoach/BridgeConfigLocal.plist`。后者包含个人地址，已被 `.gitignore` 排除，
绝不能提交：

```bash
git check-ignore WeightCoach/BridgeConfigLocal.plist
```

命令应输出该文件路径；提交前还应确认 `git status` 没有出现它。

## 6. 首次启动

fresh clone 首次启动会进入 onboarding，由使用者明确填写自己的身高、性别、出生年份、
当前体重、目标体重和目标日期；未完成前不会进入主界面。身体成分档案从空值开始，
不会自动灌入仓库作者的 DEXA 或肌肉数据。

语言可在 App 设置中选择跟随系统、简体中文、繁体中文或英文。随后按需授权
HealthKit、相机和通知。授权弹窗由 iOS 管理，应以真机上的实际结果为准。

## 7. 构建与快速检查

以下命令来自仓库根目录的 `AGENTS.md`，该文件是后续更新的唯一准则。

在仓库根目录执行完整模拟器构建：

```bash
xcodebuild -project WeightCoach.xcodeproj -scheme WeightCoach \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  build CODE_SIGNING_ALLOWED=NO
```

在 `WeightCoach/` 源码目录执行快速类型检查：

```bash
xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios17.0-simulator \
  WeightCoachApp.swift Models/*.swift Health/*.swift Engine/*.swift Services/*.swift Views/*.swift Support/*.swift
```

`AGENTS.md` 当前没有单独规定 XCTest 的 CLI 命令；需要跑单元测试时可先在 Xcode
使用 **Product → Test**，若仓库以后补充标准命令，则以更新后的 `AGENTS.md` 为准。

## 8. 隐私与分享边界

- 公开仓库从已审查的代码快照建立单一根提交，不包含原私有开发仓库的历史。
- 当前源码不包含作者个人 DEXA、肌肉或减重目标默认值；fresh clone 会在进入主界面
  前要求新用户自行填写基础资料和目标。
- Demo Mode 中的身体、饮食和运动数据均为虚构测试数据。
- 不要提交 `BridgeConfigLocal.plist`、API Key、访问令牌、个人服务 URL、健康数据导出
  或真机日志。
