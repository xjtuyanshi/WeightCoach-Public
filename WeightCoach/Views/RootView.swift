import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var reminders: ReminderScheduler
    @EnvironmentObject private var language: LanguageStore
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \FoodEntry.date, order: .reverse) private var allFoods: [FoodEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var localWeights: [WeightEntry]
    @Query(sort: \ExerciseEntry.startDate, order: .reverse) private var allExercises: [ExerciseEntry]
    @State private var selectedTab = DemoMode.initialTab
    @State private var showDemoBarcode = false
    @State private var showDemoCapture = false

    private struct WidgetRefreshKey: Hashable {
        let dayStart: Date
        let budgetKcal: Int
        let consumedKcal: Int
    }

    private var todayFoods: [FoodEntry] {
        allFoods.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var todayMetrics: TodayBudgetMetrics {
        TodayBudgetMetrics.calculate(
            profile: profile,
            health: health,
            todayFoods: todayFoods,
            localWeights: localWeights,
            exercises: allExercises
        )
    }

    private var widgetRefreshKey: WidgetRefreshKey {
        WidgetRefreshKey(
            dayStart: Calendar.current.startOfDay(for: .now),
            budgetKcal: Int(todayMetrics.budget.rounded()),
            consumedKcal: Int(todayMetrics.consumed.rounded())
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label(
                        language.localizedString("tab.today"),
                        systemImage: "gauge.with.dots.needle.50percent"
                    )
                }
                .tag(0)
            FoodLogView()
                .tabItem {
                    Label(language.localizedString("tab.food"), systemImage: "fork.knife")
                }
                .tag(1)
            ExerciseLogView()
                .tabItem {
                    Label(language.localizedString("tab.exercise"), systemImage: "figure.run")
                }
                .tag(2)
            WeightView()
                .tabItem {
                    Label(
                        language.localizedString("tab.weight"),
                        systemImage: "chart.line.downtrend.xyaxis"
                    )
                }
                .tag(3)
            SettingsView()
                .tabItem {
                    Label(language.localizedString("tab.settings"), systemImage: "gearshape")
                }
                .tag(4)
        }
        .task {
            if DemoMode.isActive {
                DemoMode.seedIfNeeded(context: modelContext)
                health.todayWorkoutCoverageAvailable = true
                if DemoMode.demoMissingActivityEnergyEnabled {
                    health.todaySteps = 9_500
                    health.todayActiveEnergyKcal = 0
                    health.todayActiveEnergyIntervals = []
                    health.lastActivityRefreshDate = .now
                    health.activityDataErrorDescription = nil
                }
                if DemoMode.demoThirdPartyExerciseEnabled {
                    let now = Date.now
                    let workoutStart = now.addingTimeInterval(-3_900)
                    let workoutEnd = now.addingTimeInterval(300)
                    let duplicatedEnergy = HealthActiveEnergyInterval(
                        startDate: workoutStart,
                        endDate: now,
                        kcal: 450
                    )
                    // 450 kcal 代表 Apple 活动圆环的权威日总；重复区间模拟
                    // Watch 与第三方跑步 App 同时写入相同活动能量。
                    health.todayActiveEnergyKcal = 450
                    health.todayActiveEnergyIntervals = [duplicatedEnergy, duplicatedEnergy]
                        .compactMap { $0 }
                    health.todayWorkoutIntervals = [
                        HealthWorkoutInterval(
                            startDate: workoutStart,
                            endDate: workoutEnd,
                            activityType: .running,
                            hasActiveEnergy: true
                        ),
                    ]
                    health.lastActivityRefreshDate = now
                    health.activityDataErrorDescription = nil
                }
                showDemoBarcode = DemoMode.demoBarcodeCode != nil
                    || DemoMode.demoNutritionLabelEnabled
                showDemoCapture = DemoMode.demoCaptureEnabled
            } else {
                await health.requestAuthorization()
            }
            await reminders.reconcile(
                context: modelContext,
                profile: profile,
                latestHealthWeightDate: health.latestWeightDate,
                language: language.selection
            )
        }
        .task(id: widgetRefreshKey) {
            WidgetBudgetPublisher.publish(metrics: todayMetrics)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { @MainActor in
                if !DemoMode.isActive {
                    await health.refreshAll()
                }
                await reminders.reconcile(
                    context: modelContext,
                    profile: profile,
                    latestHealthWeightDate: health.latestWeightDate,
                    language: language.selection
                )
            }
        }
        .onChange(of: health.latestWeightDate) { _, latestWeightDate in
            Task { @MainActor in
                await reminders.reconcile(
                    context: modelContext,
                    profile: profile,
                    latestHealthWeightDate: latestWeightDate,
                    language: language.selection
                )
            }
        }
        .sheet(isPresented: $showDemoBarcode) {
            BarcodeScanView(defaultDate: .now)
        }
        .sheet(isPresented: $showDemoCapture) {
            AIFoodScanView(defaultDate: .now)
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { !profile.isOnboardingComplete && !DemoMode.isActive },
                set: { _ in }
            )
        ) {
            ProfileOnboardingView()
                .environmentObject(profile)
                .interactiveDismissDisabled()
        }
    }
}
