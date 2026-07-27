# WeightCoach Mac mini 私有识别桥

这个服务把 iPhone 处理后的餐盘、品牌订单或餐厅账单 JPEG 交给 Mac mini 上已登录 ChatGPT 的 Codex CLI，再由 ChatGPT/OpenAI 云端模型完成识别。它不使用 OpenAI API Key，也不会让 iPhone 跳转到 ChatGPT；它是「Mac mini 私有入口 + ChatGPT 云端识别」，不是本地离线模型。

## 安全边界

- Python 服务只监听 `127.0.0.1:8765`。
- 只通过 Tailscale Serve 暴露 tailnet 内的 HTTPS 地址，不开启 Funnel。
- 每个请求必须带由 Tailscale Serve 注入的所属账户身份；服务只接受安装时检测到的账户。
- 接口只接受固定版本的 JPEG 识别请求，不接受提示词、路径或命令。
- Codex 使用 `--ephemeral`、`--ignore-user-config`、`--ignore-rules` 和只读沙箱，并显式禁用 shell、浏览器、插件、多代理等全部非必要工具。
- 子进程只继承 HOME、用户、临时目录和语言等白名单环境；不会继承 API Key 或其他无关环境变量，只使用 Mac mini 已有的 ChatGPT 登录。
- 临时照片位于权限受限的系统临时目录，请求结束后自动删除；日志不记录图片或识别内容。
- 一次只处理一张照片，避免订阅额度和机器资源被并发请求占满。

## 识别结果

- 同一接口支持餐盘照片、能够看清品牌/杯型/定制项的点单截图，以及没有食物实物入镜的餐厅账单或收据。
- 响应必须包含 `input_kind`，并区分 `food_photo`、`receipt_or_menu` 与 `non_food`。当前 App 会据此提供「整单 / 1/2」等实际摄入比例入口，同时避免把账单照片当作餐盘缩略图保存；缺少该字段的旧桥会被安全拒绝，必须先升级。
- 账单会按可见行项目与打印数量返回整单估算；价格、税、小费等不会参与营养计算。完全相同的重复行可以合并，但数量必须相加。最多返回 24 项，避免较长账单被静默截掉。
- 每项食物或饮品会返回中心热量估算，并可附带可空的热量上下限与咖啡因毫克数；旧版 App 会忽略这些新增字段，协议版本仍为 `1`。
- 热量范围必须成对出现，并包含中心估算；桥接会拒绝不完整、倒置或不包含中心值的范围。
- 品牌点单页面显示的通常是标准配方营养值，未必随糖浆、奶类或加料实时更新。识别结果会把标准值与定制差额合并计算一次，并在备注里标明推算依据。

## 安装

前提：Mac mini 已安装并登录 ChatGPT 与 Tailscale，且两台设备在同一个 tailnet。

```bash
cd "/path/to/WeightCoach"
./MacMiniBridge/install.sh
```

安装器会先运行 Python 单元测试，再复制最小运行文件到：

```text
~/Library/Application Support/WeightCoachBridge
```

随后创建用户级 LaunchAgent，使桥接在登录后自动运行，并建立 Tailscale 私有 HTTPS
入口。安装完成时会打印本人的私有地址；把它填入 App 的“设置 → AI 拍照识别”。
仓库与 fresh install 均不包含作者地址，也不会默认连接其他人的 Mac 或消耗其他人的
ChatGPT 订阅。开发机若要在构建时本地预置地址，请按
[`docs/BRIDGE_SETUP.md`](../docs/BRIDGE_SETUP.md) 创建 git ignored 配置。

## 验证与排错

```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale serve status
launchctl print gui/$UID/com.lukegogogo.weightcoach.bridge
tail -f "$HOME/Library/Logs/WeightCoachBridge/bridge-error.log"
```

App 的「设置 → AI 拍照识别」会显示在线状态。开发验收可用
`-demoData -demoCapture -demoRealRecognition`，它会把演示餐盘真正发送到 Mac mini；不带 `-demoRealRecognition` 时仍使用固定 Demo Provider，不能作为端到端证据。

## 已知限制

这是给个人使用的 ChatGPT 订阅自动化桥接，不是官方推理 API 的稳定性承诺。照片会由 Mac mini 发给 ChatGPT/OpenAI 云端；`--ephemeral` 表示不保存 Codex 任务会话，不代表图片从未发送到云端。Mac mini 必须开机并保持 ChatGPT/Tailscale 登录；订阅速率限制、ChatGPT App 更新或内置 Codex 路径变化都可能使服务暂时不可用。单张照片无法准确测量重量或隐藏烹调油，所以 App 始终要求确认份量和热量。
