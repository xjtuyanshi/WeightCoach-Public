import WidgetKit
import SwiftUI

private enum WidgetLanguage: String {
    case system
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"

    var locale: Locale {
        self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }

    func resolved(systemLocale: Locale = .autoupdatingCurrent) -> WidgetLanguage {
        guard self == .system else { return self }
        let identifier = systemLocale.identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        if identifier.hasPrefix("zh") {
            let isTraditional =
                identifier.contains("hant")
                || identifier.contains("-tw")
                || identifier.contains("-hk")
                || identifier.contains("-mo")
            return isTraditional ? .traditionalChinese : .simplifiedChinese
        }
        return identifier.hasPrefix("en") ? .english : .simplifiedChinese
    }
}

private enum WidgetLocalization {
    static func string(
        _ key: String,
        language: WidgetLanguage,
        bundle: Bundle = .main
    ) -> String {
        let localization = language.resolved().rawValue
        guard
            let path = bundle.path(forResource: localization, ofType: "lproj"),
            let localizedBundle = Bundle(path: path)
        else {
            return bundle.localizedString(forKey: key, value: key, table: nil)
        }
        return localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }
}

struct WidgetBudgetSnapshot: Codable {
    let schemaVersion: Int
    let dayStart: Date
    let updatedAt: Date
    let budgetKcal: Double
    let consumedKcal: Double

    static let preview = WidgetBudgetSnapshot(
        schemaVersion: 1,
        dayStart: Calendar.current.startOfDay(for: .now),
        updatedAt: .now,
        budgetKcal: 1_631,
        consumedKcal: 1_162
    )

    var remainingKcal: Double { budgetKcal - consumedKcal }

    var progress: Double {
        guard budgetKcal > 0 else { return 0 }
        return min(max(consumedKcal / budgetKcal, 0), 1)
    }
}

private enum WidgetBudgetStorage {
    static let appGroupIdentifier = "group.com.lukegogogo.WeightCoach"
    static let storageKey = "widget.todayBudget.snapshot"
    static let languageStorageKey = "app.language.selection"
    static let widgetKind = "WeightCoachTodayBudget"

    static func load() -> WidgetBudgetSnapshot? {
        guard
            let defaults = UserDefaults(suiteName: appGroupIdentifier),
            let data = defaults.data(forKey: storageKey),
            let snapshot = try? PropertyListDecoder().decode(WidgetBudgetSnapshot.self, from: data),
            snapshot.schemaVersion == 1
        else {
            return nil
        }
        return snapshot
    }

    static func loadLanguage() -> WidgetLanguage {
        guard
            let defaults = UserDefaults(suiteName: appGroupIdentifier),
            let rawValue = defaults.string(forKey: languageStorageKey),
            let language = WidgetLanguage(rawValue: rawValue)
        else {
            return .system
        }
        return language
    }
}

struct BudgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetBudgetSnapshot?
    fileprivate let language: WidgetLanguage
}

struct BudgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BudgetEntry {
        BudgetEntry(
            date: .now,
            snapshot: .preview,
            language: WidgetBudgetStorage.loadLanguage()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BudgetEntry) -> Void) {
        completion(
            BudgetEntry(
                date: .now,
                snapshot: context.isPreview ? .preview : WidgetBudgetStorage.load(),
                language: WidgetBudgetStorage.loadLanguage()
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BudgetEntry>) -> Void) {
        let now = Date()
        let nextMidnight = Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: now)
        ) ?? now.addingTimeInterval(86_400)
        let snapshot = WidgetBudgetStorage.load()
        let entries = [
            BudgetEntry(
                date: now,
                snapshot: snapshot,
                language: WidgetBudgetStorage.loadLanguage()
            ),
            BudgetEntry(
                date: nextMidnight,
                snapshot: snapshot,
                language: WidgetBudgetStorage.loadLanguage()
            ),
        ]
        let timeline = Timeline(
            entries: entries,
            policy: .after(nextMidnight.addingTimeInterval(15 * 60))
        )
        completion(timeline)
    }
}

struct WeightCoachWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BudgetEntry

    private var currentSnapshot: WidgetBudgetSnapshot? {
        guard
            let snapshot = entry.snapshot,
            Calendar.current.isDate(snapshot.dayStart, inSameDayAs: entry.date)
        else {
            return nil
        }
        return snapshot
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularAccessory
            case .accessoryRectangular:
                rectangularAccessory
            default:
                smallWidget
            }
        }
        .environment(\.locale, entry.language.locale)
        .containerBackground(for: .widget) {
            if family == .systemSmall {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.55, blue: 0.32),
                        Color(red: 0.04, green: 0.38, blue: 0.23),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private var smallWidget: some View {
        if let snapshot = currentSnapshot {
            VStack(spacing: 10) {
                Text(
                    WidgetLocalization.string(
                        snapshot.remainingKcal < 0
                            ? "widget.overBudget"
                            : "widget.remaining",
                        language: entry.language
                    )
                )
                    .font(.subheadline.weight(.semibold))

                BudgetProgressRing(snapshot: snapshot, lineWidth: 9) {
                    VStack(spacing: 0) {
                        Text("\(Int(abs(snapshot.remainingKcal).rounded()))")
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.65)
                        Text(
                            WidgetLocalization.string(
                                "widget.kcal",
                                language: entry.language
                            )
                        )
                            .font(.caption2)
                    }
                }
                .frame(width: 91, height: 91)
            }
            .foregroundStyle(.white)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "scalemass")
                    .font(.title2)
                Text(
                    WidgetLocalization.string(
                        "widget.openApp",
                        language: entry.language
                    )
                )
                    .font(.headline)
                Text(
                    WidgetLocalization.string(
                        "widget.updateToday",
                        language: entry.language
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var circularAccessory: some View {
        if let snapshot = currentSnapshot {
            BudgetProgressRing(snapshot: snapshot, lineWidth: 5) {
                VStack(spacing: -2) {
                    Text("\(Int(abs(snapshot.remainingKcal).rounded()))")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                    Text(
                        WidgetLocalization.string(
                            "widget.kcal",
                            language: entry.language
                        )
                    )
                        .font(.system(size: 7, weight: .medium))
                }
            }
            .privacySensitive()
        } else {
            Image(systemName: "arrow.clockwise")
                .font(.title3)
        }
    }

    @ViewBuilder
    private var rectangularAccessory: some View {
        if let snapshot = currentSnapshot {
            HStack(spacing: 8) {
                BudgetProgressRing(snapshot: snapshot, lineWidth: 4) {
                    Image(systemName: snapshot.remainingKcal < 0 ? "exclamationmark" : "fork.knife")
                        .font(.caption.bold())
                }
                .frame(width: 39, height: 39)

                VStack(alignment: .leading, spacing: 1) {
                    Text(
                        WidgetLocalization.string(
                            snapshot.remainingKcal < 0
                                ? "widget.overBudget"
                                : "widget.remaining",
                            language: entry.language
                        )
                    )
                        .font(.caption)
                    Text(
                        "\(Int(abs(snapshot.remainingKcal).rounded())) "
                            + WidgetLocalization.string(
                                "widget.kcal",
                                language: entry.language
                            )
                    )
                        .font(.headline)
                }
            }
            .privacySensitive()
        } else {
            Label(
                WidgetLocalization.string(
                    "widget.openToUpdate",
                    language: entry.language
                ),
                systemImage: "arrow.clockwise"
            )
                .font(.caption)
        }
    }
}

private struct BudgetProgressRing<Content: View>: View {
    let snapshot: WidgetBudgetSnapshot
    let lineWidth: CGFloat
    @ViewBuilder let content: Content

    init(
        snapshot: WidgetBudgetSnapshot,
        lineWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.snapshot = snapshot
        self.lineWidth = lineWidth
        self.content = content()
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.primary.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: snapshot.progress)
                .stroke(
                    snapshot.remainingKcal < 0 ? Color.red : Color.primary,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            content
        }
    }
}

struct WeightCoachWidget: Widget {
    let kind = WidgetBudgetStorage.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BudgetProvider()) { entry in
            WeightCoachWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(
            WidgetLocalization.string(
                "widget.configuration.name",
                language: WidgetBudgetStorage.loadLanguage()
            )
        )
        .description(
            WidgetLocalization.string(
                "widget.configuration.description",
                language: WidgetBudgetStorage.loadLanguage()
            )
        )
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

#Preview(as: .systemSmall) {
    WeightCoachWidget()
} timeline: {
    BudgetEntry(date: .now, snapshot: .preview, language: .simplifiedChinese)
}

#Preview(as: .accessoryRectangular) {
    WeightCoachWidget()
} timeline: {
    BudgetEntry(date: .now, snapshot: .preview, language: .simplifiedChinese)
}
