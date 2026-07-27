import Foundation
import SwiftData

struct FoodEntryDraft {
    var name: String
    var calories: Double
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var portionText: String?
    var mealType: MealType
    var source: FoodSource
    var date: Date
    var barcode: String?
    var foodProductID: UUID?
    var amountValue: Double?
    var amountUnit: FoodQuantityUnit?
    var calculationVersion: Int?
    var fiber: Double?
    var sugar: Double?
    var sodiumMg: Double?
    var caffeineMg: Double?
    var calorieLowerBound: Double?
    var calorieUpperBound: Double?
    var imageData: Data?

    init(
        name: String,
        calories: Double,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        portionText: String? = nil,
        mealType: MealType,
        source: FoodSource,
        date: Date = .now,
        barcode: String? = nil,
        foodProductID: UUID? = nil,
        amountValue: Double? = nil,
        amountUnit: FoodQuantityUnit? = nil,
        calculationVersion: Int? = nil,
        fiber: Double? = nil,
        sugar: Double? = nil,
        sodiumMg: Double? = nil,
        caffeineMg: Double? = nil,
        calorieLowerBound: Double? = nil,
        calorieUpperBound: Double? = nil,
        imageData: Data? = nil
    ) {
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.portionText = portionText
        self.mealType = mealType
        self.source = source
        self.date = date
        self.barcode = barcode
        self.foodProductID = foodProductID
        self.amountValue = amountValue
        self.amountUnit = amountUnit
        self.calculationVersion = calculationVersion
        self.fiber = fiber
        self.sugar = sugar
        self.sodiumMg = sodiumMg
        self.caffeineMg = caffeineMg
        self.calorieLowerBound = calorieLowerBound
        self.calorieUpperBound = calorieUpperBound
        self.imageData = imageData
    }

    /// 再记一次只复制摄入快照；不复制图片，也不会复制原 HealthKit UUID。
    init(repeating entry: FoodEntry, date: Date, mealType: MealType) {
        self.init(
            name: entry.name,
            calories: entry.calories,
            protein: entry.protein,
            carbs: entry.carbs,
            fat: entry.fat,
            portionText: entry.portionText,
            mealType: mealType,
            source: .quickRepeat,
            date: date,
            barcode: entry.barcode,
            foodProductID: entry.foodProductID,
            amountValue: entry.amountValue,
            amountUnit: entry.amountUnit,
            calculationVersion: entry.calculationVersion,
            fiber: entry.fiber,
            sugar: entry.sugar,
            sodiumMg: entry.sodiumMg,
            caffeineMg: entry.caffeineMg,
            calorieLowerBound: entry.calorieLowerBound,
            calorieUpperBound: entry.calorieUpperBound
        )
    }

    func makeEntry() -> FoodEntry {
        FoodEntry(
            name: name,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            portionText: portionText,
            mealType: mealType,
            source: source,
            date: date,
            barcode: barcode,
            foodProductID: foodProductID,
            amountValue: amountValue,
            amountUnit: amountUnit,
            calculationVersion: calculationVersion,
            fiber: fiber,
            sugar: sugar,
            sodiumMg: sodiumMg,
            caffeineMg: caffeineMg,
            calorieLowerBound: calorieLowerBound,
            calorieUpperBound: calorieUpperBound,
            imageData: imageData
        )
    }
}

@MainActor
enum FoodEntryWriter {
    private struct PendingHealthWrite {
        let token: UUID
        let task: Task<Void, Never>
    }

    private actor EntryOperationCompletion {
        private var isFinished = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            guard !isFinished else { return }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        func finish() {
            guard !isFinished else { return }
            isFinished = true
            let pendingWaiters = waiters
            waiters.removeAll()
            pendingWaiters.forEach { $0.resume() }
        }
    }

    private struct PendingEntryOperation {
        let token: UUID
        let completion: EntryOperationCompletion
    }

    private static var pendingHealthWrites: [UUID: PendingHealthWrite] = [:]
    private static var pendingEntryOperations: [
        ObjectIdentifier: PendingEntryOperation
    ] = [:]

    enum DeletionError: LocalizedError {
        case healthKit(String)
        case local(String, healthSampleWasDeleted: Bool)

        var errorDescription: String? {
            message(language: AppLanguage.sharedSelection())
        }

        func message(language: AppLanguage) -> String {
            switch self {
            case .healthKit(let message):
                return Self.withDetail(
                    message,
                    summaryKey: "food.health.delete.failed",
                    language: language
                )
            case .local(let message, let healthSampleWasDeleted):
                return Self.withDetail(
                    message,
                    summaryKey: healthSampleWasDeleted
                        ? "food.local.delete.remoteDeleted"
                        : "food.local.delete.failed",
                    language: language
                )
            }
        }

        private static func withDetail(
            _ detail: String,
            summaryKey: String,
            language: AppLanguage
        ) -> String {
            let summary = language.localizedString(summaryKey)
            let trimmed = detail.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return trimmed.isEmpty ? summary : "\(summary)\n\(trimmed)"
        }
    }

    enum HealthSyncError: LocalizedError {
        case unavailable
        case cleanup(String)
        case write(String)
        case local(String)
        case entryDeleted

        var errorDescription: String? {
            message(language: AppLanguage.sharedSelection())
        }

        func message(language: AppLanguage) -> String {
            switch self {
            case .unavailable:
                return language.localizedString(
                    "food.health.sync.unavailable"
                )
            case .cleanup(let message):
                return Self.withDetail(
                    message,
                    summaryKey: "food.health.sync.cleanup.failed",
                    language: language
                )
            case .write(let message):
                return Self.withDetail(
                    message,
                    summaryKey: "food.health.sync.write.failed",
                    language: language
                )
            case .local(let message):
                return Self.withDetail(
                    message,
                    summaryKey: "food.health.sync.local.failed",
                    language: language
                )
            case .entryDeleted:
                return language.localizedString(
                    "food.health.sync.entryDeleted"
                )
            }
        }

        private static func withDetail(
            _ detail: String,
            summaryKey: String,
            language: AppLanguage
        ) -> String {
            let summary = language.localizedString(summaryKey)
            let trimmed = detail.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return trimmed.isEmpty ? summary : "\(summary)\n\(trimmed)"
        }
    }

    /// 样本 UUID 与饮食记录一次落盘，再批量写 HealthKit。
    /// 即使 App 在远端写入前退出，也只会留下一个指向“不存在样本”的安全 UUID，不会产生无法追踪的远端孤儿。
    static func save(
        drafts: [FoodEntryDraft],
        context: ModelContext,
        health: any DietaryEnergyHealthManaging,
        reminders: ReminderScheduler,
        writeToHealthKit: Bool = true
    ) async throws -> [FoodEntry] {
        guard !drafts.isEmpty else { return [] }

        let entries = drafts.map { $0.makeEntry() }
        let healthBatch: PreparedDietaryEnergyBatch?
        if writeToHealthKit && !DemoMode.isActive {
            let writes = drafts.map {
                DietaryEnergyWrite(kcal: $0.calories, name: $0.name, date: $0.date)
            }
            let batch = health.prepareDietaryEnergy(writes)
            healthBatch = batch
            for (entry, sampleUUID) in zip(entries, batch.sampleUUIDs) {
                entry.healthKitSampleUUID = sampleUUID
                entry.healthKitSyncStatus = sampleUUID == nil ? .failed : .pending
            }
        } else {
            healthBatch = nil
            entries.forEach { $0.healthKitSyncStatus = .notRequested }
        }

        entries.forEach(context.insert)
        do {
            try context.save()
        } catch {
            // 同一事务中可能还包含商品 useCount/首选份量更新；统一回滚，避免半成功状态。
            context.rollback()
            throw error
        }

        for date in Set(drafts.map(\.date)) {
            reminders.cancel(.food, on: date)
        }

        guard let healthBatch else { return entries }

        // 本地记录已经可见时，用户可能立刻删除/撤销。先注册同一批远端写入，
        // delete 会按 UUID 等待它结束，再执行远端删除，避免 write/delete 交错产生孤儿样本。
        let sampleUUIDs = healthBatch.sampleUUIDs.compactMap { $0 }
        guard !sampleUUIDs.isEmpty else { return entries }
        let token = UUID()
        let writeTask = Task { @MainActor in
            do {
                try await health.saveDietaryEnergy(healthBatch)
                for entry in entries where entry.healthKitSampleUUID != nil {
                    entry.healthKitSyncStatus = .synced
                }
            } catch {
                // 保留预先持久化的 UUID：HealthKit 批量写入如果出现不确定结果，
                // 后续删除仍能按每个 UUID 做幂等清理；从未写入的 UUID 查询 0 条也按成功处理。
                for entry in entries where entry.healthKitSampleUUID != nil {
                    entry.healthKitSyncStatus = .uncertain
                }
            }
            try? context.save()
        }
        let pendingWrite = PendingHealthWrite(token: token, task: writeTask)
        for sampleUUID in sampleUUIDs {
            pendingHealthWrites[sampleUUID] = pendingWrite
        }

        await writeTask.value
        for sampleUUID in sampleUUIDs
        where pendingHealthWrites[sampleUUID]?.token == token {
            pendingHealthWrites.removeValue(forKey: sampleUUID)
        }
        return entries
    }

    /// 对失败或结果不确定的单条饮食做幂等重试。
    ///
    /// 先按旧 UUID 清理可能已经写入的样本，再创建带新 UUID 的样本并先落盘，
    /// 因此重试不会在 Apple 健康中叠加重复热量。
    static func retryHealthSync(
        _ entry: FoodEntry,
        context: ModelContext,
        health: any DietaryEnergyHealthManaging
    ) async throws {
        try await withSerializedEntryOperation(for: entry) {
            try await retryHealthSyncWithoutSerialization(
                entry,
                context: context,
                health: health
            )
        }
    }

    private static func retryHealthSyncWithoutSerialization(
        _ entry: FoodEntry,
        context: ModelContext,
        health: any DietaryEnergyHealthManaging
    ) async throws {
        guard !entry.isDeleted, entry.modelContext === context else {
            throw HealthSyncError.entryDeleted
        }

        if let oldSampleUUID = entry.healthKitSampleUUID {
            await waitForPendingHealthWrite(sampleUUID: oldSampleUUID)
            do {
                try await health.deleteDietaryEnergy(sampleUUID: oldSampleUUID)
            } catch {
                throw HealthSyncError.cleanup(error.localizedDescription)
            }
        }

        let batch = health.prepareDietaryEnergy(
            [
                DietaryEnergyWrite(
                    kcal: entry.calories,
                    name: entry.name,
                    date: entry.date
                )
            ]
        )
        guard let newSampleUUID = batch.sampleUUIDs.first ?? nil else {
            entry.healthKitSampleUUID = nil
            entry.healthKitSyncStatus = .failed
            do {
                try context.save()
            } catch {
                context.rollback()
                throw HealthSyncError.local(error.localizedDescription)
            }
            throw HealthSyncError.unavailable
        }

        entry.healthKitSampleUUID = newSampleUUID
        entry.healthKitSyncStatus = .pending
        do {
            try context.save()
        } catch {
            context.rollback()
            throw HealthSyncError.local(error.localizedDescription)
        }

        let token = UUID()
        let writeTask = Task { @MainActor in
            do {
                try await health.saveDietaryEnergy(batch)
                entry.healthKitSyncStatus = .synced
            } catch {
                entry.healthKitSyncStatus = .uncertain
            }
            try? context.save()
        }
        pendingHealthWrites[newSampleUUID] = PendingHealthWrite(
            token: token,
            task: writeTask
        )

        await writeTask.value
        if pendingHealthWrites[newSampleUUID]?.token == token {
            pendingHealthWrites.removeValue(forKey: newSampleUUID)
        }
        guard entry.healthKitSyncStatus == .synced else {
            throw HealthSyncError.write("")
        }
    }

    /// HealthKit 优先删除；失败时绝不删除本地。远端成功而本地失败时回滚本地删除，并清掉失效 UUID。
    static func delete(
        _ entry: FoodEntry,
        context: ModelContext,
        health: any DietaryEnergyHealthManaging
    ) async throws {
        try await withSerializedEntryOperation(for: entry) {
            try await deleteWithoutSerialization(
                entry,
                context: context,
                health: health
            )
        }
    }

    private static func deleteWithoutSerialization(
        _ entry: FoodEntry,
        context: ModelContext,
        health: any DietaryEnergyHealthManaging
    ) async throws {
        guard !entry.isDeleted, entry.modelContext === context else {
            return
        }

        let sampleUUID = entry.healthKitSampleUUID
        if let sampleUUID {
            await waitForPendingHealthWrite(sampleUUID: sampleUUID)
            do {
                try await health.deleteDietaryEnergy(sampleUUID: sampleUUID)
            } catch {
                throw DeletionError.healthKit(error.localizedDescription)
            }
        }

        context.delete(entry)
        do {
            try context.save()
        } catch {
            context.rollback()
            if sampleUUID != nil {
                entry.healthKitSampleUUID = nil
                entry.healthKitSyncStatus = .notRequested
                try? context.save()
            }
            throw DeletionError.local(
                error.localizedDescription,
                healthSampleWasDeleted: sampleUUID != nil
            )
        }
    }

    private static func waitForPendingHealthWrite(sampleUUID: UUID) async {
        guard let pendingWrite = pendingHealthWrites[sampleUUID] else { return }
        await pendingWrite.task.value
        if pendingHealthWrites[sampleUUID]?.token == pendingWrite.token {
            pendingHealthWrites.removeValue(forKey: sampleUUID)
        }
    }

    /// Swift concurrency 在 `await` 期间会让出 MainActor；同一条记录的重试与删除
    /// 必须显式排队，否则删除可能夹在“清理旧 UUID”和“写入新 UUID”之间，留下
    /// 无本地记录可追踪的 HealthKit 样本。
    private static func withSerializedEntryOperation<Result>(
        for entry: FoodEntry,
        operation: @MainActor () async throws -> Result
    ) async throws -> Result {
        let key = ObjectIdentifier(entry)
        let predecessor = pendingEntryOperations[key]?.completion
        let token = UUID()
        let completion = EntryOperationCompletion()
        pendingEntryOperations[key] = PendingEntryOperation(
            token: token,
            completion: completion
        )

        if let predecessor {
            await predecessor.wait()
        }

        do {
            let result = try await operation()
            await completion.finish()
            if pendingEntryOperations[key]?.token == token {
                pendingEntryOperations.removeValue(forKey: key)
            }
            return result
        } catch {
            await completion.finish()
            if pendingEntryOperations[key]?.token == token {
                pendingEntryOperations.removeValue(forKey: key)
            }
            throw error
        }
    }
}
