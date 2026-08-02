# 私有 AI 识别桥接配置

WeightCoach 不包含公共 AI 服务，也不在 iPhone App 内保存 OpenAI、Claude
或其他云服务 API Key。未配置桥接时，拍照 AI 识别和一句话补记会明确显示不可用，
但手动录入、常见食物、条码和营养标签流程仍可使用。

## 每位使用者必须配置自己的桥接

同事 clone 仓库后不会连接仓库作者的 Mac，也不会使用仓库作者的 ChatGPT 订阅。
如需拍照 AI 识别或一句话补记，每位使用者应：

1. 在自己的 Mac 上部署 `MacMiniBridge/`，并使用自己的 ChatGPT 登录和自己的
   私有网络访问控制。
2. 确保桥接通过有效的 `https://` 地址访问。
3. 在 App 的“设置 → AI 识别”中填写该 HTTPS 地址并保存。
4. 使用“重新检测”确认桥接在线，再上传照片或饮食文字。

设置页只保存桥接 URL；URL 不是凭据，可以保存在 UserDefaults。不要把 API Key、
访问令牌、密码或带 `user:password@host` 的地址填入该字段。App 会拒绝 HTTP、
带用户名/密码、查询参数或片段的地址。

## 开发机本地预置（可选）

为了在自己的开发机上构建时自动预置地址，可以复制：

```text
Config/BridgeConfigLocal.example.plist
```

到：

```text
WeightCoach/BridgeConfigLocal.plist
```

然后把其中 `BridgeBaseURL` 改为自己的 HTTPS 桥接地址。真实文件已被 `.gitignore`
排除，不能提交；示例文件不包含任何真实设备地址。Xcode 的 synchronized folder
会把该本地 plist 收入当前构建。App 中显式保存的地址优先于本地 plist；在设置中
“清除并禁用”后，本地 plist 也不会被使用，除非重新填写地址或清除 App 数据。

## 分发边界

- Git 仓库只分发客户端和桥接代码，不分发任何人的 ChatGPT 会话、订阅或凭据。
- 不要向公网开放无身份验证的桥接。
- 不要共享作者的 Tailscale 账户或私人桥接地址。
- `BridgeConfigLocal.plist`、API Key、访问令牌和服务日志都不应进入 Git。
- 当前版本尚未实现桥接设备身份指纹/ownerHint 的首次绑定确认；在改变桥端协议前，
  应单独设计兼容升级和真实设备迁移测试。
