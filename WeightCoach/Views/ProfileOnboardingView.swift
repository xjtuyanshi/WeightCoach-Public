import SwiftUI

/// 新安装的最小个人资料向导。
///
/// 旧版本已经保存过 ProfileStore 标量字段的设备会被视为已完成，避免升级后
/// 打断现有用户；只有真正的新安装会看到此页。
struct ProfileOnboardingView: View {
    private enum SexSelection: String, CaseIterable, Identifiable {
        case male
        case female

        var id: String { rawValue }
    }

    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.locale) private var locale

    @State private var heightText = ""
    @State private var currentWeightText = ""
    @State private var goalWeightText = ""
    @State private var birthYear = Calendar.current.component(.year, from: .now) - 30
    @State private var sex: SexSelection?
    @State private var deficitStrategy: DeficitStrategy = .deadlinePaced
    @State private var goalEndDate =
        Calendar.current.date(byAdding: .day, value: 90, to: .now) ?? .now

    private var heightCm: Double? { Self.decimalValue(heightText) }
    private var currentWeightKg: Double? { Self.decimalValue(currentWeightText) }
    private var goalWeightKg: Double? { Self.decimalValue(goalWeightText) }
    private var earliestGoalDate: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    }
    private var latestGoalDate: Date {
        Calendar.current.date(byAdding: .year, value: 2, to: .now) ?? .distantFuture
    }

    private var canContinue: Bool {
        guard
            let heightCm,
            let currentWeightKg,
            let goalWeightKg,
            sex != nil
        else {
            return false
        }

        let currentYear = Calendar.current.component(.year, from: .now)
        return (120...230).contains(heightCm)
            && (30...300).contains(currentWeightKg)
            && (30..<currentWeightKg).contains(goalWeightKg)
            && ((currentYear - 100)...(currentYear - 13)).contains(birthYear)
            && goalEndDate > Calendar.current.startOfDay(for: .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("先建立你的个人资料", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.title3.bold())
                        Text("这些资料只保存在你的设备，用于计算热量和营养目标。Apple 健康中的最新数据仍会优先使用。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("身体资料") {
                    HStack {
                        Text("身高")
                        Spacer()
                        TextField("厘米", text: $heightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("cm")
                            .foregroundStyle(.secondary)
                    }

                    Picker("生理性别", selection: $sex) {
                        Text("请选择").tag(SexSelection?.none)
                        Text("男").tag(SexSelection?.some(.male))
                        Text("女").tag(SexSelection?.some(.female))
                    }

                    Picker("出生年份", selection: $birthYear) {
                        let currentYear = Calendar.current.component(.year, from: .now)
                        ForEach((currentYear - 100...currentYear - 13).reversed(), id: \.self) {
                            Text(String($0)).tag($0)
                        }
                    }
                }

                Section("减重目标") {
                    HStack {
                        Text("当前体重")
                        Spacer()
                        TextField("千克", text: $currentWeightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("kg")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("目标体重")
                        Spacer()
                        TextField("千克", text: $goalWeightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("kg")
                            .foregroundStyle(.secondary)
                    }

                    Picker("减脂方式", selection: $deficitStrategy) {
                        ForEach(DeficitStrategy.allCases) { strategy in
                            Text(interfaceLocalized(strategy.label, locale: locale))
                                .tag(strategy)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityIdentifier("onboarding.deficit-strategy")

                    if deficitStrategy == .rapidFatLoss {
                        DatePicker(
                            "参考目标日期",
                            selection: $goalEndDate,
                            in: earliestGoalDate...latestGoalDate,
                            displayedComponents: .date
                        )
                        .accessibilityIdentifier("onboarding.goal-end-date")
                    } else {
                        DatePicker(
                            "目标日期",
                            selection: $goalEndDate,
                            in: earliestGoalDate...latestGoalDate,
                            displayedComponents: .date
                        )
                        .accessibilityIdentifier("onboarding.goal-end-date")
                    }

                    Text(interfaceLocalized(
                        deficitStrategy == .rapidFatLoss
                            ? "此模式每天保持 750 千卡计划缺口；目标日期仅供进度参考，今日热量目标仍受最低摄入量下限约束。"
                            : "每日计划缺口会按剩余体重和目标日期动态调整。",
                        locale: locale
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                if !canContinue {
                    Section {
                        Text("请完整填写有效资料；目标体重需要低于当前体重。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("欢迎使用减重助手")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button("开始使用") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(!canContinue)
                .padding()
                .background(.bar)
            }
        }
        .interactiveDismissDisabled()
    }

    private func save() {
        guard
            let heightCm,
            let currentWeightKg,
            let goalWeightKg,
            let sex
        else {
            return
        }

        profile.heightCm = heightCm
        profile.birthYear = birthYear
        profile.isMale = sex == .male
        profile.goalStartDate = .now
        profile.goalEndDate = goalEndDate
        profile.goalStartWeight = currentWeightKg
        profile.goalWeight = goalWeightKg
        profile.deficitStrategy = deficitStrategy
        profile.completeOnboarding()
    }

    private static func decimalValue(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }
}
