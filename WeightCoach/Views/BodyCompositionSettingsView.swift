import SwiftUI

struct BodyCompositionSettingsView: View {
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    Label("Apple 健康 → 本地记录 → 校准体脂", systemImage: "arrow.down.circle")
                        .font(.subheadline.bold())
                    Text("只有前两者都没有有效体脂时，才使用校准体脂计算 BMR。历史 DEXA 和其他肌肉口径都不会进入预算计算。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    LabeledContent(
                        "当前校准兜底",
                        value: BodyCompositionPresentation.primaryValueText(
                            profile.bodyComposition.calibratedBodyFatPercent,
                            locale: locale
                        )
                    )
                } header: {
                    Text("体脂数据优先级")
                }

                measurementSection(
                    title: "当前校准",
                    fields: [.calibratedBodyFat, .fatMass, .fatFreeMass]
                )
                measurementSection(
                    title: "不同测量口径",
                    fields: [
                        .dexaLeanSoftTissue,
                        .appendicularLeanMass,
                        .fitdaysMuscleMass,
                        .skeletalMuscleMass,
                        .smi,
                    ]
                )
                measurementSection(
                    title: "历史 DEXA",
                    fields: [
                        .historicalBodyFat,
                        .historicalFatMass,
                        .historicalLeanSoftTissue,
                        .historicalTotalMass,
                    ]
                )

                Section {
                    NavigationLink {
                        DailyIntakeReferenceEditor(
                            value: referenceDailyIntakeBinding
                        )
                    } label: {
                        LabeledContent(
                            "日均摄入参考",
                            value: referenceDailyIntakeText
                        )
                    }
                    .id("body-composition-reference")
                    Text("这是个人参考，不会替代今日预算，也不会改变 TDEE 替代模型、动态缺口或安全下限。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("热量参考")
                }
            }
            .task {
                guard DemoMode.demoBodyCompositionBottomEnabled else { return }
                try? await Task.sleep(for: .milliseconds(500))
                proxy.scrollTo("body-composition-reference", anchor: .center)
            }
        }
        .navigationTitle("身体成分与校准")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func measurementSection(
        title: String,
        fields: [BodyCompositionField]
    ) -> some View {
        Section {
            ForEach(fields) { field in
                NavigationLink {
                    BodyCompositionMeasurementEditor(
                        field: field,
                        measurement: measurementBinding(for: field)
                    )
                } label: {
                    BodyCompositionMeasurementRow(
                        field: field,
                        measurement: profile.bodyComposition[keyPath: field.keyPath]
                    )
                }
            }
        } header: {
            Text(interfaceLocalized(title, locale: locale))
        }
    }

    private func measurementBinding(
        for field: BodyCompositionField
    ) -> Binding<BodyCompositionMeasurement> {
        Binding {
            profile.bodyComposition[keyPath: field.keyPath]
        } set: { measurement in
            var updated = profile.bodyComposition
            updated[keyPath: field.keyPath] = measurement
            profile.bodyComposition = updated
        }
    }

    private var referenceDailyIntakeBinding: Binding<Double?> {
        Binding {
            profile.bodyComposition.referenceDailyIntakeKcal
        } set: { value in
            var updated = profile.bodyComposition
            updated.referenceDailyIntakeKcal = value
            profile.bodyComposition = updated
        }
    }

    private var referenceDailyIntakeText: String {
        guard let value = profile.bodyComposition.referenceDailyIntakeKcal else {
            return interfaceLocalized("未填写", locale: locale)
        }
        return "\(BodyCompositionPresentation.numberText(value)) \(interfaceLocalized("千卡/天", locale: locale))"
    }
}

private struct BodyCompositionMeasurementRow: View {
    let field: BodyCompositionField
    let measurement: BodyCompositionMeasurement
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(interfaceLocalized(field.title, locale: locale))
                Spacer()
                Text(
                    localizedPrimaryValue
                )
                .foregroundStyle(.secondary)
            }
            Text(
                "\(interfaceLocalized("范围", locale: locale))：\(interfaceLocalized(BodyCompositionPresentation.rangeText(measurement), locale: locale))"
            )
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(
                "\(interfaceLocalized("来源", locale: locale))：\(BodyCompositionPresentation.sourceText(measurement, locale: locale))"
                    + " · \(interfaceLocalized("日期", locale: locale))：\(BodyCompositionPresentation.dateText(measurement, locale: locale))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(interfaceLocalized(field.definition, locale: locale))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var localizedPrimaryValue: String {
        BodyCompositionPresentation.primaryValueText(
            measurement,
            approximate: field.isApproximate,
            locale: locale
        )
    }
}

private struct BodyCompositionMeasurementEditor: View {
    let field: BodyCompositionField
    @Binding var measurement: BodyCompositionMeasurement

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var draft: BodyCompositionMeasurementDraft

    init(
        field: BodyCompositionField,
        measurement: Binding<BodyCompositionMeasurement>
    ) {
        self.field = field
        _measurement = measurement
        _draft = State(
            initialValue: BodyCompositionMeasurementDraft(
                measurement: measurement.wrappedValue
            )
        )
    }

    private var validationMessage: String? {
        draft.validationMessage(
            unit: measurement.unit,
            locale: locale
        )
    }

    var body: some View {
        Form {
            Section {
                Text(interfaceLocalized(field.definition, locale: locale))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LabeledContent("单位", value: measurement.unit.symbol)
                if field.isApproximate {
                    Label("此项按用户提供信息显示为约值", systemImage: "approximately.equal")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("口径说明")
            }

            Section {
                numericField("精确值", text: $draft.valueText)
                numericField("范围下限", text: $draft.lowerBoundText)
                numericField("范围上限", text: $draft.upperBoundText)
            } header: {
                Text("数值")
            } footer: {
                Text("只有范围时可将精确值留空；App 不会自动取中点。")
            }

            Section {
                HStack {
                    Text("来源")
                    Spacer()
                    TextField("未提供", text: $draft.sourceText)
                        .multilineTextAlignment(.trailing)
                }
                Toggle("有测量日期", isOn: $draft.includesDate)
                if draft.includesDate {
                    DatePicker(
                        "测量日期",
                        selection: $draft.measuredAt,
                        displayedComponents: .date
                    )
                } else {
                    Text("日期未提供；打开编辑页不会自动填成今天。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("来源与日期")
            }

            Section {
                TextField("口径、约值或其他说明", text: $draft.noteText, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("备注")
            }

            if let validationMessage {
                Section {
                    Label(
                        validationMessage,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button("清空此项", role: .destructive) {
                    draft.clear()
                }
            } footer: {
                Text("清空后会保持为空，不会在下次启动重新灌入默认值。")
            }
        }
        .navigationTitle(interfaceLocalized(field.title, locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    save()
                }
                .disabled(validationMessage != nil)
            }
        }
    }

    @ViewBuilder
    private func numericField(
        _ label: String,
        text: Binding<String>
    ) -> some View {
        HStack {
            Text(interfaceLocalized(label, locale: locale))
            Spacer()
            TextField("未填写", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 130)
            Text(measurement.unit.symbol)
                .foregroundStyle(.secondary)
        }
    }

    private func save() {
        guard let updated = try? draft.validatedMeasurement(unit: measurement.unit) else {
            return
        }
        measurement = updated
        dismiss()
    }
}

private struct DailyIntakeReferenceEditor: View {
    @Binding var value: Double?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var draft: DailyIntakeReferenceDraft

    init(value: Binding<Double?>) {
        _value = value
        _draft = State(initialValue: DailyIntakeReferenceDraft(value: value.wrappedValue))
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("日均参考")
                    Spacer()
                    TextField("未填写", text: $draft.valueText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 130)
                    Text("千卡")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("仅用于显示个人参考；不进入 BMR、TDEE、动态缺口或今日预算。")
            }

            if let validationMessage = draft.validationMessage(locale: locale) {
                Section {
                    Label(
                        validationMessage,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("日均摄入参考")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    guard let updated = try? draft.validatedValue() else { return }
                    value = updated
                    dismiss()
                }
                .disabled(draft.validationMessage(locale: locale) != nil)
            }
        }
    }
}

enum BodyCompositionField: String, CaseIterable, Identifiable {
    case calibratedBodyFat
    case fatMass
    case fatFreeMass
    case dexaLeanSoftTissue
    case appendicularLeanMass
    case fitdaysMuscleMass
    case skeletalMuscleMass
    case smi
    case historicalBodyFat
    case historicalFatMass
    case historicalLeanSoftTissue
    case historicalTotalMass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calibratedBodyFat: "校准体脂率"
        case .fatMass: "校准脂肪量"
        case .fatFreeMass: "完整去脂体重"
        case .dexaLeanSoftTissue: "DEXA 瘦软组织"
        case .appendicularLeanMass: "四肢瘦体重"
        case .fitdaysMuscleMass: "Fitdays 肌肉量"
        case .skeletalMuscleMass: "骨骼肌量"
        case .smi: "SMI"
        case .historicalBodyFat: "历史体脂率"
        case .historicalFatMass: "历史脂肪量"
        case .historicalLeanSoftTissue: "历史瘦软组织"
        case .historicalTotalMass: "历史总重"
        }
    }

    var definition: String {
        switch self {
        case .calibratedBodyFat:
            "综合校准体脂；仅在健康与本地体脂都缺失时作为 BMR 兜底。"
        case .fatMass:
            "身体中脂肪组织的质量。"
        case .fatFreeMass:
            "全部非脂肪质量，包含骨矿物；不等同于肌肉量。"
        case .dexaLeanSoftTissue:
            "DEXA lean soft tissue，排除脂肪与骨矿物。"
        case .appendicularLeanMass:
            "四肢 lean mass，是 DEXA 瘦软组织的子集。"
        case .fitdaysMuscleMass:
            "Fitdays 设备定义的肌肉量，不能与 DEXA 口径互换。"
        case .skeletalMuscleMass:
            "设备估算的骨骼肌量，不等同于完整去脂体重。"
        case .smi:
            "骨骼肌指数，独立单位为 kg/m²。"
        case .historicalBodyFat:
            "历史 DEXA 体脂率，只作历史对照。"
        case .historicalFatMass:
            "历史 DEXA 脂肪量。"
        case .historicalLeanSoftTissue:
            "历史 DEXA lean soft tissue，不含骨矿物。"
        case .historicalTotalMass:
            "历史 DEXA 总重约值；不会由其他字段相加推算。"
        }
    }

    var keyPath: WritableKeyPath<BodyCompositionProfile, BodyCompositionMeasurement> {
        switch self {
        case .calibratedBodyFat:
            \.calibratedBodyFatPercent
        case .fatMass:
            \.fatMassKg
        case .fatFreeMass:
            \.fatFreeMassKg
        case .dexaLeanSoftTissue:
            \.dexaLeanSoftTissueKg
        case .appendicularLeanMass:
            \.appendicularLeanMassKg
        case .fitdaysMuscleMass:
            \.fitdaysMuscleMassKg
        case .skeletalMuscleMass:
            \.skeletalMuscleMassKg
        case .smi:
            \.smiKgPerSquareMeter
        case .historicalBodyFat:
            \.historicalDEXA.bodyFatPercent
        case .historicalFatMass:
            \.historicalDEXA.fatMassKg
        case .historicalLeanSoftTissue:
            \.historicalDEXA.leanSoftTissueKg
        case .historicalTotalMass:
            \.historicalDEXA.totalMassKg
        }
    }

    var isApproximate: Bool {
        self == .historicalTotalMass
    }
}
