# 減重助手：繁體中文快速開始

這是可自行修改與建置的 iPhone App 原始碼，不是可直接點選安裝的 App Store 或 TestFlight 連結。
你可以設定自己的身體資料與目標；不會自動套用作者的個人資料。

## 先知道哪些功能不需要 AI 服務

- 常見食物搜尋、輸入重量或標準份量後換算熱量與營養。
- 從任意日期的飲食歷史再次新增，支援 `0.75`、`3/4` 等自訂比例。
- 常吃食物一鍵記錄與復原。
- 商品條碼查詢、本機營養標示 OCR、手動飲食及運動補記。
- 熱量、營養素與體重趨勢；Apple 健康資料需在自己的 iPhone 授權。

不需要 AI 橋接不代表所有功能都離線：未快取的商品條碼查詢仍需要網路。
拍照／帳單辨識與一句話補記，需要你自己的 Mac、登入狀態和私有 AI 橋接；未設定時仍可用上述功能。

## 取得及安裝

1. 準備 Mac、Xcode 與自己的 Apple 開發者簽名身分。
2. 取得原始碼：

   ```bash
   git clone https://github.com/xjtuyanshi/WeightCoach-Public.git
   cd WeightCoach-Public
   open WeightCoach.xcodeproj
   ```

3. 按照[完整設定指南](COLLEAGUE_SETUP.md#3-改成自己的签名与标识)，設定自己的 App 與 Widget Team、Bundle ID 和 App Group。不要沿用作者的私有識別資料。
4. 先在模擬器建置；連接 iPhone 後，選擇自己的裝置並執行。不要把模擬器演示結果當作真實健康資料或 AI 結果。
5. 首次開啟時填寫自己的身高、性別、出生年份、目前體重與目標。公開版預設按目標日期調整缺口，其他方式需自行選擇。
6. 到 App 的「設定 → 語言」選擇「繁體中文」，並依需求授權 Apple 健康、相機與通知。

若某項 capability 無法簽名，以自己帳號在 Xcode 中顯示的錯誤為準；不要為了通過建置直接移除 HealthKit 或改掉 App Group。

## 要使用 AI 辨識

依照[私有 AI 橋接指南](BRIDGE_SETUP.md)部署自己控制的服務。App 只填自己的 HTTPS 位址，
包含安裝器顯示的連接埠（預設 `8443`）。不要填 API Key、密碼或存取權杖，也不要共用別人的帳號或私有服務。

辨識結果是估算，仍需核對食物、份量與餐次後再儲存。

## 後續更新，不要先刪除 App

保留自己的 Team、Bundle ID 與 App Group，先備份資料，再從 Xcode 覆蓋安裝。
有自行修改程式的人，先在自己的分支保存修改，再合併公開版更新；不要強制重設分支。
完整步驟見[更新與簽名到期](COLLEAGUE_SETUP.md#9-更新已有安装与签名到期)。

Personal Team 的簽名描述檔會在簽發七天後到期，可能需要重新建置與安裝；這不是 App 內的訂閱。
詳見 [Apple 官方說明](https://developer.apple.com/help/account/basics/about-your-developer-account)。

## 驗證與限制

既有功能的測試與實際模擬器操作記錄見[驗收說明](QA_2026-09-09.md)。
自己的相機、HealthKit、AI 服務、通知與背景執行仍需在自己的裝置驗證。
本專案採用 [MIT License](../LICENSE)，營養與運動數值僅供估算參考。
