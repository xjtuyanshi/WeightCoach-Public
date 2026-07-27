import SwiftUI

struct CaffeineSummaryCard: View {
    let metrics: TodayCaffeineMetrics

    @State private var showExplanation = false
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("咖啡因", systemImage: "cup.and.saucer.fill")
                    .font(.headline)
                Spacer()
                Button {
                    showExplanation = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("咖啡因说明")
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(metrics.hasKnownData ? metrics.knownTotalMg.milligramText : "—")
                    .font(.system(.title2, design: .rounded).bold())
                Text("mg · 今日已知")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if metrics.unknownLikelyCaffeinatedCount > 0 {
                Label(unknownCaffeineText, systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.orange)
            } else {
                Text("仅统计已记录数值；留空不会被误算成 0。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("400 mg 是 FDA 对多数健康成人的每日参考上限，不是你的个人目标。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showExplanation) {
            NavigationStack {
                List {
                    Section("怎么统计") {
                        Text("只累加每条饮食记录里明确填写或由可靠品牌配方给出的咖啡因。普通照片看不出浓缩份数时，系统会保留为未知。")
                    }
                    Section("400 mg 参考") {
                        Text("FDA 表示，对多数健康成人而言，每天 400 mg 通常不会带来负面影响；敏感程度会因人、药物和健康状况而异。")
                        Text("孕期、哺乳期、心律问题或医生有特别要求时，请遵循专业建议。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("咖啡因说明")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showExplanation = false }
                    }
                }
            }
        }
    }

    private var unknownCaffeineText: String {
        let count = metrics.unknownLikelyCaffeinatedCount
        switch AppLanguage.system.resolvedLanguage(systemLocale: locale) {
        case .english:
            return "\(count) more entries may contain caffeine, but the amount is unknown"
        case .traditionalChinese:
            return "另有 \(count) 筆可能含咖啡因，但數值未知"
        case .simplifiedChinese, .system:
            return "另有 \(count) 条可能含咖啡因，但数值未知"
        }
    }
}

private extension Double {
    var milligramText: String {
        guard isFinite else { return "—" }
        return String(Int(rounded()))
    }
}
