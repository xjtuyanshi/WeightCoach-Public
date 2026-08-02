import SwiftUI
import SwiftData

struct FoodLogView: View {
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var reminders: ReminderScheduler
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var health
    @Environment(\.locale) private var locale
    @Query(sort: \FoodEntry.date, order: .reverse) private var allFoods: [FoodEntry]

    @State private var selectedDate = Date()
    @State private var showManualAdd = false
    @State private var showAIScan = false
    @State private var showSentenceBackfill = false
    @State private var showBarcodeScan = false
    @State private var isRepeatingFood = false
    @State private var undoEntry: FoodEntry?
    @State private var repeatMessage: String?
    @State private var actionError: String?
    @State private var isUndoingRepeat = false
    @State private var retryingHealthSyncEntries: Set<ObjectIdentifier> = []

    private var dayFoods: [FoodEntry] {
        allFoods.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private var dayTotal: Double {
        dayFoods.reduce(0) { $0 + $1.calories }
    }

    /// 记录用的时间：选中今天用当前时刻，选中过去的日期用当天中午
    private var entryDate: Date {
        let now = Date.now
        let boundedDate = min(selectedDate, now)
        if Calendar.current.isDateInToday(boundedDate) { return now }
        return Calendar.current.date(
            bySettingHour: 12,
            minute: 0,
            second: 0,
            of: boundedDate
        ) ?? boundedDate
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker(
                        "日期",
                        selection: $selectedDate,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                    HStack {
                        Text("当日合计")
                        Spacer()
                        Text(interfaceCalorieText(dayTotal.kcalText, locale: locale))
                            .bold()
                            .foregroundStyle(Color.accentColor)
                    }
                }

                ForEach(MealType.allCases) { meal in
                    let foods = dayFoods.filter { $0.mealType == meal }
                    if !foods.isEmpty {
                        Section {
                            ForEach(foods) { food in
                                FoodRow(food: food)
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            repeatFood(food)
                                        } label: {
                                            Label("再记", systemImage: "plus.circle")
                                        }
                                        .tint(.green)
                                        .disabled(isRepeatingFood || isUndoingRepeat)
                                        if food.healthKitSyncStatus.needsAttention {
                                            Button {
                                                retryHealthSync(food)
                                            } label: {
                                                Label(
                                                    "重试健康同步",
                                                    systemImage: "heart.text.square"
                                                )
                                            }
                                            .tint(.orange)
                                            .disabled(
                                                retryingHealthSyncEntries.contains(
                                                    ObjectIdentifier(food)
                                                )
                                            )
                                        }
                                    }
                            }
                            .onDelete { offsets in
                                deleteFoods(at: offsets, from: foods)
                            }
                        } header: {
                            HStack {
                                Label(
                                    interfaceLocalized(meal.label, locale: locale),
                                    systemImage: meal.systemImage
                                )
                                Spacer()
                                Text(interfaceCalorieText(
                                    foods.reduce(0) { $0 + $1.calories }.kcalText,
                                    locale: locale
                                ))
                            }
                        }
                    }
                }

                if dayFoods.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "还没有记录",
                            systemImage: "fork.knife.circle",
                            description: Text("点右上角记录你吃的东西")
                        )
                    }
                }
            }
            .navigationTitle("饮食记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showAIScan = true
                        } label: {
                            Label("拍照识别", systemImage: "camera.viewfinder")
                        }
                        Button {
                            showSentenceBackfill = true
                        } label: {
                            Label("一句话补记", systemImage: "text.bubble.fill")
                        }
                        Button {
                            showBarcodeScan = true
                        } label: {
                            Label("扫码", systemImage: "barcode.viewfinder")
                        }
                        Button {
                            showManualAdd = true
                        } label: {
                            Label("手动", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Label("记录", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showManualAdd) {
                CommonFoodSearchView(defaultDate: entryDate)
            }
            .sheet(isPresented: $showSentenceBackfill) {
                SentenceFoodBackfillView(defaultDate: entryDate)
            }
            .sheet(isPresented: $showAIScan) { AIFoodScanView(defaultDate: entryDate) }
            .sheet(isPresented: $showBarcodeScan) { BarcodeScanView(defaultDate: entryDate) }
            .safeAreaInset(edge: .bottom) {
                if let repeatMessage {
                    repeatToast(repeatMessage)
                        .padding(.bottom, 6)
                }
            }
            .alert(
                "操作失败",
                isPresented: Binding(
                    get: { actionError != nil },
                    set: { if !$0 { actionError = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                if let actionError {
                    Text(interfaceLocalized(actionError, locale: locale))
                } else {
                    Text("请稍后重试")
                }
            }
        }
    }

    private func repeatToast(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            if undoEntry != nil {
                Button {
                    undoQuickRepeat()
                } label: {
                    if isUndoingRepeat {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("撤销")
                    }
                }
                .font(.subheadline.bold())
                .disabled(isUndoingRepeat)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 6, y: 2)
        .padding(.horizontal)
    }

    private func repeatFood(_ food: FoodEntry) {
        guard !isRepeatingFood, !isUndoingRepeat else { return }
        isRepeatingFood = true
        repeatMessage = nil
        undoEntry = nil
        let date = entryDate
        let draft = FoodEntryDraft(
            repeating: food,
            date: date,
            mealType: MealType.suggested(for: date)
        )

        Task { @MainActor in
            do {
                let saved = try await FoodEntryWriter.save(
                    drafts: [draft],
                    context: modelContext,
                    health: health,
                    reminders: reminders
                )
                undoEntry = saved.first
                repeatMessage =
                    "\(interfaceLocalized("已记录", locale: locale)) \(food.name)"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                actionError = error.localizedDescription
            }
            isRepeatingFood = false
        }
    }

    private func undoQuickRepeat() {
        guard let entry = undoEntry, !isUndoingRepeat else { return }
        isUndoingRepeat = true
        Task { @MainActor in
            do {
                try await FoodEntryWriter.delete(
                    entry,
                    context: modelContext,
                    health: health
                )
                undoEntry = nil
                repeatMessage = interfaceLocalized("已撤销", locale: locale)
                await reminders.reconcile(
                    context: modelContext,
                    profile: profile,
                    latestHealthWeightDate: health.latestWeightDate
                )
            } catch {
                actionError = error.localizedDescription
            }
            isUndoingRepeat = false
        }
    }

    private func deleteFoods(at offsets: IndexSet, from foods: [FoodEntry]) {
        let entries = offsets.map { foods[$0] }
        Task { @MainActor in
            for entry in entries {
                do {
                    try await FoodEntryWriter.delete(
                        entry,
                        context: modelContext,
                        health: health
                    )
                } catch {
                    actionError = error.localizedDescription
                    await reminders.reconcile(
                        context: modelContext,
                        profile: profile,
                        latestHealthWeightDate: health.latestWeightDate
                    )
                    return
                }
            }
            await reminders.reconcile(
                context: modelContext,
                profile: profile,
                latestHealthWeightDate: health.latestWeightDate
            )
        }
    }

    private func retryHealthSync(_ entry: FoodEntry) {
        let identifier = ObjectIdentifier(entry)
        guard !retryingHealthSyncEntries.contains(identifier) else { return }
        retryingHealthSyncEntries.insert(identifier)
        repeatMessage = nil
        Task { @MainActor in
            defer { retryingHealthSyncEntries.remove(identifier) }
            do {
                try await FoodEntryWriter.retryHealthSync(
                    entry,
                    context: modelContext,
                    health: health
                )
                repeatMessage = interfaceLocalized("已同步到 Apple 健康", locale: locale)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
}

struct FoodRow: View {
    let food: FoodEntry
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 10) {
            if let data = food.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let portion = food.portionText, !portion.isEmpty {
                        Text(portion)
                    }
                    Text(interfaceLocalized(food.source.label, locale: locale))
                        .padding(.horizontal, 4)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(interfaceCalorieText(food.calories.kcalText, locale: locale))
                    .font(.subheadline.bold())
                if let p = food.protein {
                    Text(
                        "\(interfaceLocalized("蛋白", locale: locale)) \(Int(p.rounded()))g"
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let caffeine = food.caffeineMg {
                    Text(
                        "\(interfaceLocalized("咖啡因", locale: locale)) \(Int(caffeine.rounded()))mg"
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                switch food.healthKitSyncStatus {
                case .pending:
                    Label("Apple 健康同步中", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                case .failed, .uncertain:
                    Label(
                        "已保存到 App · 健康同步失败",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(.orange)
                case .notRequested, .synced:
                    EmptyView()
                }
            }
        }
    }
}
