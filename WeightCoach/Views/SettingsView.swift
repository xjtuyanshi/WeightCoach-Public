import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var reminders: ReminderScheduler
    @EnvironmentObject private var language: LanguageStore
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var modelContext

    @State private var isUpdatingReminders = false
    @State private var showNotificationSettingsAlert = false
    @State private var recognitionStatus: RecognitionBridgeStatus = .checking
    @State private var bridgeURLText = ""
    @State private var bridgeConfigurationMessage: String?
    @State private var bridgeStatusRequestID = UUID()
    @State private var showDemoBodyComposition = false

    private let activityOptions: [(label: String, factor: Double)] = [
        ("久坐（几乎不运动）", 1.2),
        ("轻度活动（每周运动 1-3 次）", 1.375),
        ("中度活动（每周运动 3-5 次）", 1.55),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(
                        language.localizedString("language.picker"),
                        selection: $language.selection
                    ) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(
                                language.localizedString(
                                    option.displayNameLocalizationKey
                                )
                            )
                            .tag(option)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text(language.localizedString("language.section"))
                } footer: {
                    Text(language.localizedString("language.footer"))
                }

                Section {
                    HStack {
                        Text("身高")
                        Spacer()
                        TextField("cm", value: $profile.heightCm, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("cm").foregroundStyle(.secondary)
                    }
                    Picker("出生年份", selection: $profile.birthYear) {
                        ForEach((1940...2015).reversed(), id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    Picker("性别", selection: $profile.isMale) {
                        Text("男").tag(true)
                        Text("女").tag(false)
                    }
                    Button {
                        syncFromHealth()
                    } label: {
                        Label("从 Apple 健康同步身高/年龄/性别", systemImage: "arrow.triangle.2.circlepath")
                    }
                } header: {
                    Text("个人资料")
                } footer: {
                    Text("Apple 健康有数据时优先使用健康数据；这里的值仅作兜底。")
                }

                Section {
                    NavigationLink {
                        BodyCompositionSettingsView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("身体成分与校准")
                            Text(
                                interfaceLocalized(
                                    "校准体脂",
                                    locale: language.locale
                                )
                                    + " "
                                    + BodyCompositionPresentation.primaryValueText(
                                        profile.bodyComposition.calibratedBodyFatPercent,
                                        locale: language.locale
                                    )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("身体成分")
                } footer: {
                    Text("严格区分完整去脂体重、DEXA 瘦软组织、四肢瘦体重、Fitdays 肌肉量、骨骼肌和 SMI。")
                }

                Section {
                    HStack {
                        Text("起始体重")
                        Spacer()
                        TextField("kg", value: $profile.goalStartWeight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("kg").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("目标体重")
                        Spacer()
                        TextField("kg", value: $profile.goalWeight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("kg").foregroundStyle(.secondary)
                    }
                    Picker("减脂方式", selection: $profile.deficitStrategy) {
                        ForEach(DeficitStrategy.allCases) { strategy in
                            Text(interfaceLocalized(
                                strategy.label,
                                locale: language.locale
                            ))
                            .tag(strategy)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityIdentifier("settings.deficit-strategy")
                    .accessibilityValue(interfaceLocalized(
                        profile.deficitStrategy.label,
                        locale: language.locale
                    ))
                    .accessibilityHint("选择固定 750 千卡缺口，或按目标日期动态调整。")
                    DatePicker("开始日期", selection: $profile.goalStartDate, displayedComponents: .date)
                    if profile.deficitStrategy == .rapidFatLoss {
                        DatePicker(
                            "参考目标日期",
                            selection: $profile.goalEndDate,
                            displayedComponents: .date
                        )
                        .accessibilityIdentifier("settings.goal-end-date")
                    } else {
                        DatePicker(
                            "目标日期",
                            selection: $profile.goalEndDate,
                            displayedComponents: .date
                        )
                        .accessibilityIdentifier("settings.goal-end-date")
                    }
                } header: {
                    Text("减重目标")
                } footer: {
                    let totalKg = max(0, profile.goalStartWeight - profile.goalWeight)
                    let perWeek = profile.totalDays > 0 ? totalKg / Double(profile.totalDays) * 7 : 0
                    Text(goalPlanText(
                        strategy: profile.deficitStrategy,
                        totalDays: profile.totalDays,
                        totalKg: totalKg,
                        perWeek: perWeek
                    ))
                }

                Section {
                    Toggle("计入 Apple 健康活动能量", isOn: $profile.includeActiveEnergy)
                    if !profile.includeActiveEnergy {
                        Picker("基础活动水平", selection: $profile.activityFactor) {
                            ForEach(activityOptions, id: \.factor) { option in
                                Text(interfaceLocalized(
                                    option.label,
                                    locale: language.locale
                                ))
                                .tag(option.factor)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                } header: {
                    Text("消耗计算")
                } footer: {
                    Text(interfaceLocalized(
                        profile.includeActiveEnergy
                            ? "当前模式：总消耗 = 基础代谢 × 1.1（食物热效应）+ 手表实测的全天活动能量。活动系数不参与计算，避免把日常活动算两遍。当天预算会随活动量实时增长。"
                            : "当前模式：总消耗 = 基础代谢 × 活动系数（粗略估算）。有 Apple Watch 时建议打开上方开关，用实测值更准。",
                        locale: language.locale
                    ))
                }

                Section {
                    Toggle(
                        "训练日燃料调整",
                        isOn: $profile.trainingFuelAdjustmentEnabled
                    )
                    if profile.trainingFuelAdjustmentEnabled {
                        Picker("今天", selection: macroDayStyleBinding) {
                            ForEach(MacroDayStyle.allCases, id: \.self) { style in
                                Text(interfaceLocalized(
                                    style.label,
                                    locale: language.locale
                                ))
                                .tag(style)
                            }
                        }
                    }
                } header: {
                    Text("营养目标")
                } footer: {
                    Text(interfaceLocalized(
                        profile.trainingFuelAdjustmentEnabled
                            ? "训练日会在同样的热量预算内适当提高碳水、降低脂肪；蛋白质和每日总热量不变。这只是燃料安排，不代表减脂会更快。"
                            : "默认使用稳定的保肌营养目标。需要时可开启训练日燃料调整；不会自动猜测训练日。",
                        locale: language.locale
                    ))
                }

                Section {
                    Toggle(
                        "20:30 饮食记录提醒",
                        isOn: reminderBinding(for: .food)
                    )
                    Toggle(
                        "8:00 称重提醒",
                        isOn: reminderBinding(for: .weight)
                    )
                } header: {
                    Text("每日提醒")
                } footer: {
                    Text("只有当天还没有对应记录时才会提醒。首次开启会申请系统通知权限。")
                }
                .disabled(isUpdatingReminders)

                Section {
                    LabeledContent(
                        "识别方式",
                        value: interfaceLocalized(
                            "Mac mini + ChatGPT 订阅",
                            locale: language.locale
                        )
                    )
                    TextField(
                        "https://你的私有桥接地址",
                        text: $bridgeURLText
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .accessibilityLabel("私有 AI 识别桥接 HTTPS 地址")

                    HStack {
                        Button("保存并检测") {
                            saveBridgeConfiguration()
                        }
                        .disabled(
                            bridgeURLText
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        )

                        Spacer()

                        Button("清除并禁用", role: .destructive) {
                            clearBridgeConfiguration()
                        }
                    }
                    // Form/List 会把同一行的 automatic Button 都提升为整行操作，
                    // 导致点击“保存”时同时执行“清除”。borderless 保持两个操作独立。
                    .buttonStyle(.borderless)

                    if let bridgeConfigurationMessage {
                        Text(interfaceLocalized(
                            bridgeConfigurationMessage,
                            locale: language.locale
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    switch recognitionStatus {
                    case .notConfigured:
                        Label(
                            "尚未配置；照片和文字不会上传，手动记录仍可使用",
                            systemImage: "lock.shield"
                        )
                        .foregroundStyle(.secondary)
                    case .checking:
                        Label("正在检查 Mac mini…", systemImage: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                    case .online(let model):
                        Label("识别服务在线", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        LabeledContent("识别模型", value: model)
                    case .offline(let message):
                        Label("Mac mini 暂时离线", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(interfaceLocalized(message, locale: language.locale))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await refreshRecognitionStatus() }
                    } label: {
                        Label("重新检测", systemImage: "arrow.clockwise")
                    }
                } header: {
                    Text("AI 识别")
                } footer: {
                    Text("每位使用者必须填写自己的 HTTPS 私有桥接地址。这里仅保存 URL，绝不能填写 API Key、密码或访问令牌。未配置时照片和文字都不会上传；桥接不持久化临时输入，结果和份量仍需确认。")
                }

                Section {
                    LabeledContent(
                        "Apple 健康",
                        value: interfaceLocalized(
                            health.isAvailable ? "此设备支持" : "此设备不支持",
                            locale: language.locale
                        )
                    )
                    if health.authorizationErrorDescription != nil {
                        Label(
                            "最近一次授权请求失败，请检查系统设置。",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    LabeledContent(
                        "最近体重",
                        value: health.latestWeightKg.map { "\($0.kgText) kg" }
                            ?? interfaceLocalized("未读取到", locale: language.locale)
                    )
                    LabeledContent(
                        "今日活动能量",
                        value: health.todayActiveEnergyIntervals.isEmpty
                            ? interfaceLocalized("未读取到", locale: language.locale)
                            : interfaceCalorieText(
                                health.todayActiveEnergyKcal.kcalText,
                                locale: language.locale
                            )
                    )
                    LabeledContent(
                        "今日步数",
                        value: interfaceStepText(
                            health.todaySteps,
                            locale: language.locale
                        )
                    )
                    if health.activityDataErrorDescription != nil {
                        Label(
                            "Apple 健康活动数据读取失败，请重新请求授权后重试。",
                            systemImage: "exclamationmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    Button {
                        Task { @MainActor in
                            await health.requestAuthorization()
                            await reconcileReminders()
                        }
                    } label: {
                        Label("请求健康数据授权", systemImage: "heart.text.square")
                    }
                } header: {
                    Text("Apple 健康")
                }

                Section {
                    Text("本 App 的热量估算仅供参考，不构成医疗建议。如有健康问题请咨询医生或注册营养师。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
            .navigationDestination(isPresented: $showDemoBodyComposition) {
                BodyCompositionSettingsView()
            }
            .task {
                guard DemoMode.demoBodyCompositionEnabled else { return }
                showDemoBodyComposition = true
            }
            .task {
                guard profile.foodReminderEnabled || profile.weightReminderEnabled else { return }
                guard !(await reminders.authorizationIsGranted()) else { return }
                profile.foodReminderEnabled = false
                profile.weightReminderEnabled = false
                await reminders.reconcile(
                    context: modelContext,
                    profile: profile,
                    latestHealthWeightDate: health.latestWeightDate,
                    language: language.selection
                )
            }
            .task {
                loadBridgeConfiguration()
                await refreshRecognitionStatus()
            }
            .onChange(of: language.selection) { _, newLanguage in
                Task { @MainActor in
                    await reminders.reconcile(
                        context: modelContext,
                        profile: profile,
                        latestHealthWeightDate: health.latestWeightDate,
                        language: newLanguage
                    )
                }
            }
            .alert("通知权限未开启", isPresented: $showNotificationSettingsAlert) {
                Button("取消", role: .cancel) {}
                Button("前往系统设置") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            } message: {
                Text("请在系统设置中允许「减重助手」发送通知后，再开启每日提醒。")
            }
        }
    }

    private func goalPlanText(
        strategy: DeficitStrategy,
        totalDays: Int,
        totalKg: Double,
        perWeek: Double
    ) -> String {
        if strategy == .rapidFatLoss {
            let targetDeficit = Int(CalorieEngine.rapidFatLossDailyDeficit)
            let weeklyKg = CalorieEngine.rapidFatLossDailyDeficit
                * 7
                / CalorieEngine.kcalPerKg
            switch AppLanguage.system.resolvedLanguage(
                systemLocale: language.locale
            ) {
            case .english:
                return String(
                    format: "Fast loss keeps a %d kcal daily target deficit even when you are ahead of schedule—about %.2f kg per week in the simple planning model. The calorie floor still applies; the goal date is for progress reference only.",
                    targetDeficit,
                    weeklyKg
                )
            case .traditionalChinese:
                return String(
                    format: "盡快減脂會固定每天 %d 大卡的目標缺口，不會因進度領先而降低；依簡單模型約每週 %.2f kg。今日熱量目標仍受最低攝取量下限約束，目標日期僅供進度參考。",
                    targetDeficit,
                    weeklyKg
                )
            case .simplifiedChinese, .system:
                return String(
                    format: "尽快减脂会固定每天 %d 千卡的目标缺口，不会因进度领先而降低；按简单模型约每周 %.2f kg。今日热量目标仍受最低摄入量下限约束，目标日期仅供进度参考。",
                    targetDeficit,
                    weeklyKg
                )
            }
        }

        switch AppLanguage.system.resolvedLanguage(
            systemLocale: language.locale
        ) {
        case .english:
            return String(
                format: "Deadline pacing plans %.1f kg in %d days, about %.2f kg per week. The daily target deficit adjusts between 250 and 1,000 kcal; the calorie floor still applies.",
                totalKg,
                totalDays,
                perWeek
            )
        case .traditionalChinese:
            return String(
                format: "按日期達標會規劃 %d 天減 %.1f kg，約每週 %.2f kg；每日目標缺口會在 250～1,000 大卡之間動態調整，且今日熱量目標仍受最低攝取量下限約束。",
                totalDays,
                totalKg,
                perWeek
            )
        case .simplifiedChinese, .system:
            return String(
                format: "按日期达标会规划 %d 天减 %.1f kg，约每周 %.2f kg；每日目标缺口会在 250～1,000 千卡之间动态调整，且今日热量目标仍受最低摄入量下限约束。",
                totalDays,
                totalKg,
                perWeek
            )
        }
    }

    private func reminderBinding(for kind: ReminderKind) -> Binding<Bool> {
        Binding {
            switch kind {
            case .food: return profile.foodReminderEnabled
            case .weight: return profile.weightReminderEnabled
            }
        } set: { enabled in
            updateReminder(kind, enabled: enabled)
        }
    }

    private var macroDayStyleBinding: Binding<MacroDayStyle> {
        Binding {
            profile.macroDayStyle()
        } set: { style in
            profile.setMacroDayStyle(style)
        }
    }

    private func updateReminder(_ kind: ReminderKind, enabled: Bool) {
        guard !isUpdatingReminders else { return }
        isUpdatingReminders = true
        Task { @MainActor in
            if enabled {
                let granted = await reminders.requestAuthorizationIfNeeded()
                if granted {
                    setReminderPreference(kind, enabled: true)
                    await reminders.reconcile(
                        context: modelContext,
                        profile: profile,
                        latestHealthWeightDate: health.latestWeightDate,
                        language: language.selection
                    )
                } else {
                    setReminderPreference(kind, enabled: false)
                    showNotificationSettingsAlert = true
                }
            } else {
                setReminderPreference(kind, enabled: false)
                await reminders.removePending(for: kind)
            }
            isUpdatingReminders = false
        }
    }

    private func setReminderPreference(_ kind: ReminderKind, enabled: Bool) {
        switch kind {
        case .food: profile.foodReminderEnabled = enabled
        case .weight: profile.weightReminderEnabled = enabled
        }
    }

    @MainActor
    private func reconcileReminders() async {
        await reminders.reconcile(
            context: modelContext,
            profile: profile,
            latestHealthWeightDate: health.latestWeightDate,
            language: language.selection
        )
    }

    private func syncFromHealth() {
        Task { @MainActor in
            await health.refreshAll()
            if let h = health.heightCm, h > 100 { profile.heightCm = h }
            if let age = health.ageYears {
                profile.birthYear = Calendar.current.component(.year, from: .now) - age
            }
            if let male = health.isMale { profile.isMale = male }
            await reconcileReminders()
        }
    }

    @MainActor
    private func refreshRecognitionStatus() async {
        let requestID = UUID()
        bridgeStatusRequestID = requestID
        guard let resolution = BridgeConfiguration.current() else {
            recognitionStatus = .notConfigured
            return
        }
        recognitionStatus = .checking
        do {
            let health = try await MacMiniFoodRecognitionProvider(
                baseURL: resolution.baseURL
            ).checkHealth()
            try Task.checkCancellation()
            guard bridgeStatusRequestID == requestID,
                  BridgeConfiguration.current()?.baseURL == resolution.baseURL else {
                return
            }
            recognitionStatus = .online(model: health.model)
        } catch is CancellationError {
            return
        } catch {
            guard bridgeStatusRequestID == requestID else { return }
            recognitionStatus = .offline(message: error.localizedDescription)
        }
    }

    private func loadBridgeConfiguration() {
        bridgeURLText = BridgeConfiguration.current()?
            .baseURL.absoluteString ?? ""
    }

    private func saveBridgeConfiguration() {
        do {
            let url = try BridgeConfiguration.save(bridgeURLText)
            bridgeURLText = url.absoluteString
            bridgeConfigurationMessage = "地址已保存在本机；正在检测连接。"
            Task { await refreshRecognitionStatus() }
        } catch {
            bridgeConfigurationMessage = error.localizedDescription
            if BridgeConfiguration.current() == nil {
                recognitionStatus = .notConfigured
            }
        }
    }

    private func clearBridgeConfiguration() {
        BridgeConfiguration.clear()
        bridgeStatusRequestID = UUID()
        bridgeURLText = ""
        bridgeConfigurationMessage = "已清除并禁用 AI 桥接；照片和文字不会上传。"
        recognitionStatus = .notConfigured
    }
}

private enum RecognitionBridgeStatus {
    case notConfigured
    case checking
    case online(model: String)
    case offline(message: String)
}
