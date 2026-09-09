import Foundation
import SwiftData

enum ExerciseActivityType: String, CaseIterable, Identifiable, Codable, Sendable {
    case basketball
    case running
    case walking
    case strengthTraining

    var id: String { rawValue }

    var label: String {
        switch self {
        case .basketball: return "篮球"
        case .running: return "跑步"
        case .walking: return "走路"
        case .strengthTraining: return "力量训练"
        }
    }

    var systemImage: String {
        switch self {
        case .basketball: return "basketball"
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .strengthTraining: return "dumbbell.fill"
        }
    }

    var durationGuidance: String {
        switch self {
        case .basketball:
            return "篮球只填写真正上场活动的时间，不包含坐场边、长时间休息或聊天。"
        case .running:
            return "跑步填写实际跑动时间，排除长时间停下休息的部分。"
        case .walking:
            return "走路填写实际步行时间，并按大部分路程的速度选择强度。"
        case .strengthTraining:
            return "力量训练可包含正常组间休息，但请排除长时间停顿或聊天。"
        }
    }
}

/// 运动强度快照所对应的 2024 Adult Compendium 条目。
///
/// MET 与 Compendium code 会在保存时复制进 `ExerciseEntry`，以后即使预设更新，
/// 历史记录仍能按当时采用的算法复核。
enum ExerciseIntensity: String, CaseIterable, Identifiable, Codable, Sendable {
    case basketballShooting
    case basketballGeneral
    case basketballGame
    case runningSlow
    case runningModerate
    case runningFast
    case walkingSlow
    case walkingModerate
    case walkingBrisk
    case strengthGeneral
    case strengthCompound
    case strengthVigorous

    var id: String { rawValue }

    var activityType: ExerciseActivityType {
        switch self {
        case .basketballShooting, .basketballGeneral, .basketballGame:
            return .basketball
        case .runningSlow, .runningModerate, .runningFast:
            return .running
        case .walkingSlow, .walkingModerate, .walkingBrisk:
            return .walking
        case .strengthGeneral, .strengthCompound, .strengthVigorous:
            return .strengthTraining
        }
    }

    var label: String {
        switch self {
        case .basketballShooting: return "投篮练习"
        case .basketballGeneral: return "一般强度"
        case .basketballGame: return "比赛强度"
        case .runningSlow: return "慢跑"
        case .runningModerate: return "中速跑"
        case .runningFast: return "快速跑"
        case .walkingSlow: return "慢走"
        case .walkingModerate: return "正常走"
        case .walkingBrisk: return "快走"
        case .strengthGeneral: return "常规力量"
        case .strengthCompound: return "复合动作"
        case .strengthVigorous: return "高强度举重"
        }
    }

    var detail: String {
        switch self {
        case .basketballShooting: return "投篮、罚球等练习"
        case .basketballGeneral: return "一般球局，包含走动和短暂停顿"
        case .basketballGame: return "持续对抗或全场比赛"
        case .runningSlow: return "约 4.0–4.2 mph（约 13 分/英里）"
        case .runningModerate: return "约 5.0–5.2 mph（约 12 分/英里）"
        case .runningFast: return "约 7.0 mph（约 8.5 分/英里）"
        case .walkingSlow: return "约 2.0–2.4 mph，轻松慢走"
        case .walkingModerate: return "约 2.8–3.4 mph，正常步速"
        case .walkingBrisk: return "约 3.5–3.9 mph，以锻炼为目的的快走"
        case .strengthGeneral: return "多种动作，每组约 8–15 次，使用不同阻力"
        case .strengthCompound: return "深蹲、硬拉等复合动作，慢速或爆发发力"
        case .strengthVigorous: return "大重量、力量举或健美训练，高强度"
        }
    }

    var metValue: Double {
        switch self {
        case .basketballShooting: return 5.0
        case .basketballGeneral: return 6.0
        case .basketballGame: return 8.0
        case .runningSlow: return 6.5
        case .runningModerate: return 8.5
        case .runningFast: return 11.0
        case .walkingSlow: return 2.8
        case .walkingModerate: return 3.8
        case .walkingBrisk: return 4.8
        case .strengthGeneral: return 3.5
        case .strengthCompound: return 5.0
        case .strengthVigorous: return 6.0
        }
    }

    var compendiumCode: String {
        switch self {
        case .basketballShooting: return "15070"
        case .basketballGeneral: return "15050"
        case .basketballGame: return "15040"
        case .runningSlow: return "12028"
        case .runningModerate: return "12030"
        case .runningFast: return "12070"
        case .walkingSlow: return "17152"
        case .walkingModerate: return "17190"
        case .walkingBrisk: return "17200"
        case .strengthGeneral: return "02054"
        case .strengthCompound: return "02052"
        case .strengthVigorous: return "02050"
        }
    }

    static func presets(for activityType: ExerciseActivityType) -> [ExerciseIntensity] {
        allCases.filter { $0.activityType == activityType }
    }

    static func defaultIntensity(for activityType: ExerciseActivityType) -> ExerciseIntensity {
        switch activityType {
        case .basketball: return .basketballGeneral
        case .running: return .runningModerate
        case .walking: return .walkingModerate
        case .strengthTraining: return .strengthGeneral
        }
    }
}

@Model
final class ExerciseEntry {
    var startDate: Date
    var durationMinutes: Double
    var activityTypeRaw: String
    var intensityRaw: String
    var name: String
    var compendiumCode: String
    var metSnapshot: Double
    var weightKgSnapshot: Double
    var estimatedActiveEnergyKcal: Double
    var calculationVersion: Int

    init(
        startDate: Date = .now,
        durationMinutes: Double,
        activityType: ExerciseActivityType,
        intensity: ExerciseIntensity,
        name: String? = nil,
        compendiumCode: String,
        metSnapshot: Double,
        weightKgSnapshot: Double,
        estimatedActiveEnergyKcal: Double,
        calculationVersion: Int = ExerciseEnergyEngine.calculationVersion
    ) {
        self.startDate = startDate
        self.durationMinutes = durationMinutes
        self.activityTypeRaw = activityType.rawValue
        self.intensityRaw = intensity.rawValue
        self.name = name ?? "\(activityType.label) · \(intensity.label)"
        self.compendiumCode = compendiumCode
        self.metSnapshot = metSnapshot
        self.weightKgSnapshot = weightKgSnapshot
        self.estimatedActiveEnergyKcal = estimatedActiveEnergyKcal
        self.calculationVersion = calculationVersion
    }

    var activityType: ExerciseActivityType? {
        ExerciseActivityType(rawValue: activityTypeRaw)
    }

    var intensity: ExerciseIntensity? {
        ExerciseIntensity(rawValue: intensityRaw)
    }

    /// Returns a localized title for names generated by the app while leaving
    /// user-provided names byte-for-byte unchanged.
    ///
    /// Older records persist the Simplified Chinese generated title in `name`.
    /// Comparing it with the activity/intensity snapshot lets the display layer
    /// localize those records without changing the SwiftData schema or history.
    func displayName(locale: Locale) -> String {
        guard
            let activityType,
            let intensity,
            name == "\(activityType.label) · \(intensity.label)"
        else {
            return name
        }

        let activityLabel = interfaceLocalized(activityType.label, locale: locale)
        let intensityLabel = interfaceLocalized(intensity.label, locale: locale)
        return "\(activityLabel) · \(intensityLabel)"
    }

    var endDate: Date {
        guard durationMinutes.isFinite, durationMinutes > 0 else { return startDate }
        let endDate = startDate.addingTimeInterval(durationMinutes * 60)
        return endDate.timeIntervalSinceReferenceDate.isFinite ? endDate : startDate
    }

    var energyInterval: ExerciseEnergyInterval {
        ExerciseEnergyInterval(
            startDate: startDate,
            endDate: endDate,
            estimatedActiveEnergyKcal: estimatedActiveEnergyKcal,
            activityType: activityType
        )
    }

    static func estimated(
        startDate: Date = .now,
        durationMinutes: Double,
        intensity: ExerciseIntensity,
        weightKg: Double,
        name: String? = nil
    ) -> ExerciseEntry? {
        guard let energy = ExerciseEnergyEngine.estimateActiveEnergyKcal(
            intensity: intensity,
            weightKg: weightKg,
            durationMinutes: durationMinutes
        ) else {
            return nil
        }

        return ExerciseEntry(
            startDate: startDate,
            durationMinutes: durationMinutes,
            activityType: intensity.activityType,
            intensity: intensity,
            name: name,
            compendiumCode: intensity.compendiumCode,
            metSnapshot: intensity.metValue,
            weightKgSnapshot: weightKg,
            estimatedActiveEnergyKcal: energy
        )
    }
}
