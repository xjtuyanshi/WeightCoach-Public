import SwiftUI
import SwiftData

@main
struct WeightCoachApp: App {
    @StateObject private var profile = ProfileStore()
    @StateObject private var reminders = ReminderScheduler()
    @StateObject private var language = LanguageStore()
    @State private var health = HealthKitManager()

    init() {
        LegacyCredentialCleaner.removeDeprecatedClaudeKeyIfNeeded()
        BridgeConfiguration.restoreBundledConfigurationIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(profile)
                .environmentObject(reminders)
                .environmentObject(language)
                .environment(health)
                .environment(\.locale, language.locale)
        }
        .modelContainer(
            for: [
                FoodEntry.self,
                WeightEntry.self,
                FoodProduct.self,
                ExerciseEntry.self,
            ]
        )
    }
}
