import XCTest
import HealthKit
import SwiftData
@testable import WeightCoach

private actor TestAsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var hasStarted = false

    func wait() async {
        hasStarted = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor TestHealthEvents {
    private(set) var deletedSampleUUIDs: [UUID] = []

    func recordDelete(_ sampleUUID: UUID) {
        deletedSampleUUIDs.append(sampleUUID)
    }
}

private final class ControlledDietaryEnergyHealth: DietaryEnergyHealthManaging {
    enum StubError: Error {
        case saveFailed
    }

    let saveGate = TestAsyncGate()
    let events = TestHealthEvents()
    let shouldFailSave: Bool

    init(shouldFailSave: Bool = false) {
        self.shouldFailSave = shouldFailSave
    }

    func prepareDietaryEnergy(_ writes: [DietaryEnergyWrite]) -> PreparedDietaryEnergyBatch {
        let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)!
        let samples = writes.map { write -> HKQuantitySample? in
            guard write.kcal.isFinite, write.kcal > 0 else { return nil }
            return HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: write.kcal),
                start: write.date,
                end: write.date
            )
        }
        return PreparedDietaryEnergyBatch(samplesByIndex: samples)
    }

    func saveDietaryEnergy(_ batch: PreparedDietaryEnergyBatch) async throws {
        await saveGate.wait()
        if shouldFailSave {
            throw StubError.saveFailed
        }
    }

    func deleteDietaryEnergy(sampleUUID: UUID) async throws {
        await events.recordDelete(sampleUUID)
    }
}

private final class RetryableDietaryEnergyHealth: DietaryEnergyHealthManaging {
    enum StubError: Error {
        case firstSaveFailed
    }

    private(set) var saveAttemptCount = 0
    private(set) var deletedSampleUUIDs: [UUID] = []

    func prepareDietaryEnergy(_ writes: [DietaryEnergyWrite]) -> PreparedDietaryEnergyBatch {
        let type = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)!
        return PreparedDietaryEnergyBatch(
            samplesByIndex: writes.map { write in
                HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: write.kcal),
                    start: write.date,
                    end: write.date
                )
            }
        )
    }

    func saveDietaryEnergy(_ batch: PreparedDietaryEnergyBatch) async throws {
        saveAttemptCount += 1
        if saveAttemptCount == 1 {
            throw StubError.firstSaveFailed
        }
    }

    func deleteDietaryEnergy(sampleUUID: UUID) async throws {
        deletedSampleUUIDs.append(sampleUUID)
    }
}

private actor TestCompletionFlag {
    private(set) var isComplete = false

    func markComplete() {
        isComplete = true
    }
}

private actor RetryDeleteRaceState {
    private(set) var deletedSampleUUIDs: [UUID] = []
    private(set) var savedSampleUUIDs: [UUID] = []

    func recordDelete(_ sampleUUID: UUID) -> Int {
        deletedSampleUUIDs.append(sampleUUID)
        return deletedSampleUUIDs.count
    }

    func recordSave(_ sampleUUIDs: [UUID]) {
        savedSampleUUIDs.append(contentsOf: sampleUUIDs)
    }
}

private final class RetryDeleteRaceHealth: DietaryEnergyHealthManaging {
    let firstDeleteGate = TestAsyncGate()
    let state = RetryDeleteRaceState()

    func prepareDietaryEnergy(
        _ writes: [DietaryEnergyWrite]
    ) -> PreparedDietaryEnergyBatch {
        let type = HKQuantityType.quantityType(
            forIdentifier: .dietaryEnergyConsumed
        )!
        return PreparedDietaryEnergyBatch(
            samplesByIndex: writes.map { write in
                HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(
                        unit: .kilocalorie(),
                        doubleValue: write.kcal
                    ),
                    start: write.date,
                    end: write.date
                )
            }
        )
    }

    func saveDietaryEnergy(
        _ batch: PreparedDietaryEnergyBatch
    ) async throws {
        await state.recordSave(batch.sampleUUIDs.compactMap { $0 })
    }

    func deleteDietaryEnergy(sampleUUID: UUID) async throws {
        let deleteIndex = await state.recordDelete(sampleUUID)
        if deleteIndex == 1 {
            await firstDeleteGate.wait()
        }
    }
}

private final class FailingDeleteDietaryEnergyHealth:
    DietaryEnergyHealthManaging
{
    enum StubError: LocalizedError {
        case deleteFailed

        var errorDescription: String? { "synthetic delete failure" }
    }

    private(set) var prepareCallCount = 0
    private(set) var saveCallCount = 0

    func prepareDietaryEnergy(
        _ writes: [DietaryEnergyWrite]
    ) -> PreparedDietaryEnergyBatch {
        prepareCallCount += 1
        return PreparedDietaryEnergyBatch(
            samplesByIndex: Array(repeating: nil, count: writes.count)
        )
    }

    func saveDietaryEnergy(
        _ batch: PreparedDietaryEnergyBatch
    ) async throws {
        saveCallCount += 1
    }

    func deleteDietaryEnergy(sampleUUID: UUID) async throws {
        throw StubError.deleteFailed
    }
}

@MainActor
final class FoodEntryWriterTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: FoodEntry.self,
            WeightEntry.self,
            FoodProduct.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    func testRepeatDraftCopiesSnapshotButNotHealthUUIDOrImage() throws {
        let productID = UUID()
        let original = FoodEntry(
            name: "蛋白棒",
            calories: 190,
            protein: 21,
            carbs: 22,
            fat: 7,
            portionText: "1 份",
            mealType: .snack,
            source: .barcode,
            barcode: "096619365475",
            healthKitSampleUUID: UUID(),
            foodProductID: productID,
            amountValue: 1,
            amountUnit: .servings,
            calculationVersion: 1,
            fiber: 10,
            sugar: 2,
            sodiumMg: 220,
            caffeineMg: 80,
            calorieLowerBound: 180,
            calorieUpperBound: 210,
            imageData: Data([1, 2, 3])
        )
        let repeatedDate = Date(timeIntervalSince1970: 123_456)
        let draft = FoodEntryDraft(
            repeating: original,
            date: repeatedDate,
            mealType: .breakfast
        )
        let repeated = draft.makeEntry()

        XCTAssertEqual(repeated.name, original.name)
        XCTAssertEqual(repeated.foodProductID, productID)
        XCTAssertEqual(repeated.amountUnit, .servings)
        XCTAssertEqual(repeated.fiber, 10)
        XCTAssertEqual(repeated.caffeineMg, 80)
        XCTAssertEqual(repeated.calorieLowerBound, 180)
        XCTAssertEqual(repeated.calorieUpperBound, 210)
        XCTAssertEqual(repeated.date, repeatedDate)
        XCTAssertEqual(repeated.mealType, .breakfast)
        XCTAssertEqual(repeated.source, .quickRepeat)
        XCTAssertNil(repeated.healthKitSampleUUID)
        XCTAssertNil(repeated.imageData)
    }

    func testScaledHistoryRepeatScalesEveryKnownValueAndKeepsSnapshotIdentity() throws {
        let productID = UUID()
        let original = FoodEntry(
            name: "虾仁炒饭",
            calories: 640,
            protein: 32,
            carbs: 80,
            fat: 20,
            portionText: "1 盘",
            mealType: .dinner,
            source: .ai,
            barcode: "12345678",
            healthKitSampleUUID: UUID(),
            foodProductID: productID,
            amountValue: 1,
            amountUnit: .servings,
            calculationVersion: 3,
            fiber: 8,
            sugar: 12,
            sodiumMg: 1_200,
            caffeineMg: 40,
            calorieLowerBound: 560,
            calorieUpperBound: 720,
            imageData: Data([9, 8, 7])
        )
        let date = Date(timeIntervalSince1970: 456_789)

        let draft = try XCTUnwrap(
            FoodEntryDraft(
                scaledRepeatOf: original,
                multiplier: 0.75,
                portionText: "1 盘 × ¾",
                date: date,
                mealType: .lunch
            )
        )
        let repeated = draft.makeEntry()

        XCTAssertEqual(repeated.name, "虾仁炒饭")
        XCTAssertEqual(repeated.calories, 480, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(repeated.protein), 24, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(repeated.carbs), 60, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(repeated.fat), 15, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(repeated.fiber), 6, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(repeated.sugar), 9, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(repeated.sodiumMg), 900, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(repeated.caffeineMg), 30, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(repeated.calorieLowerBound), 420, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(repeated.calorieUpperBound), 540, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(repeated.amountValue), 0.75, accuracy: 0.001)
        XCTAssertEqual(repeated.amountUnit, .servings)
        XCTAssertEqual(repeated.portionText, "1 盘 × ¾")
        XCTAssertEqual(repeated.foodProductID, productID)
        XCTAssertEqual(repeated.barcode, "12345678")
        XCTAssertEqual(repeated.calculationVersion, 3)
        XCTAssertEqual(repeated.date, date)
        XCTAssertEqual(repeated.mealType, .lunch)
        XCTAssertEqual(repeated.source, .quickRepeat)
        XCTAssertNil(repeated.healthKitSampleUUID)
        XCTAssertNil(repeated.imageData)
    }

    func testScaledHistoryRepeatKeepsMissingNutritionMissing() throws {
        let original = FoodEntry(
            name: "未知点心",
            calories: 100,
            mealType: .snack,
            source: .manual
        )

        let draft = try XCTUnwrap(
            FoodEntryDraft(
                scaledRepeatOf: original,
                multiplier: 1.3,
                portionText: "历史份量 × 1.3",
                date: .now,
                mealType: .snack
            )
        )
        let repeated = draft.makeEntry()

        XCTAssertEqual(repeated.calories, 130, accuracy: 0.001)
        XCTAssertNil(repeated.protein)
        XCTAssertNil(repeated.carbs)
        XCTAssertNil(repeated.fat)
        XCTAssertNil(repeated.fiber)
        XCTAssertNil(repeated.sugar)
        XCTAssertNil(repeated.sodiumMg)
        XCTAssertNil(repeated.caffeineMg)
        XCTAssertNil(repeated.amountValue)
    }

    func testScaledHistoryRepeatRejectsNonPositiveAndNonFiniteMultipliers() {
        let original = FoodEntry(
            name: "香蕉",
            calories: 105,
            mealType: .snack,
            source: .manual
        )

        XCTAssertNil(FoodEntryDraft(
            scaledRepeatOf: original,
            multiplier: 0,
            portionText: nil,
            date: .now,
            mealType: .snack
        ))
        XCTAssertNil(FoodEntryDraft(
            scaledRepeatOf: original,
            multiplier: -.infinity,
            portionText: nil,
            date: .now,
            mealType: .snack
        ))
        XCTAssertNil(FoodEntryDraft(
            scaledRepeatOf: original,
            multiplier: PortionRatioEngine.suggestedMaximum + 0.01,
            portionText: nil,
            date: .now,
            mealType: .snack
        ))

        original.calories = .nan
        XCTAssertNil(FoodEntryDraft(
            scaledRepeatOf: original,
            multiplier: 0.75,
            portionText: nil,
            date: .now,
            mealType: .snack
        ))

        original.calories = Double.greatestFiniteMagnitude
        XCTAssertNil(FoodEntryDraft(
            scaledRepeatOf: original,
            multiplier: PortionRatioEngine.suggestedMaximum,
            portionText: nil,
            date: .now,
            mealType: .snack
        ))
    }

    func testScaledHistoryRepeatDropsInvalidOptionalNutritionAndItsAmountUnit() throws {
        let original = FoodEntry(
            name: "异常历史数据",
            calories: 100,
            protein: -2,
            carbs: .nan,
            fat: .infinity,
            mealType: .snack,
            source: .manual,
            amountValue: -1,
            amountUnit: .servings,
            caffeineMg: -50
        )

        let repeated = try XCTUnwrap(FoodEntryDraft(
            scaledRepeatOf: original,
            multiplier: 0.75,
            portionText: nil,
            date: .now,
            mealType: .snack
        )).makeEntry()

        XCTAssertNil(repeated.protein)
        XCTAssertNil(repeated.carbs)
        XCTAssertNil(repeated.fat)
        XCTAssertNil(repeated.caffeineMg)
        XCTAssertNil(repeated.amountValue)
        XCTAssertNil(repeated.amountUnit)
    }

    func testWriterPersistsMultipleEntriesBeforeHealthSync() async throws {
        let context = try makeContext()
        let reminders = ReminderScheduler()
        let health = HealthKitManager()
        let drafts = [
            FoodEntryDraft(
                name: "米饭",
                calories: 232,
                protein: 5,
                mealType: .lunch,
                source: .manual
            ),
            FoodEntryDraft(
                name: "鸡胸肉",
                calories: 248,
                protein: 47,
                mealType: .lunch,
                source: .manual
            ),
        ]

        let saved = try await FoodEntryWriter.save(
            drafts: drafts,
            context: context,
            health: health,
            reminders: reminders,
            writeToHealthKit: false
        )

        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntry>()), 2)
        XCTAssertEqual(saved.reduce(0) { $0 + $1.calories }, 480)
        XCTAssertTrue(saved.allSatisfy { $0.healthKitSampleUUID == nil })
        XCTAssertTrue(saved.allSatisfy { $0.healthKitSyncStatus == .notRequested })
    }

    func testDeleteRemovesLocalEntryWithoutHealthSample() async throws {
        let context = try makeContext()
        let entry = FoodEntry(
            name: "苹果",
            calories: 95,
            mealType: .snack,
            source: .manual
        )
        context.insert(entry)
        try context.save()

        try await FoodEntryWriter.delete(
            entry,
            context: context,
            health: HealthKitManager()
        )

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntry>()), 0)
    }

    func testHealthDeleteFailureKeepsLocalEntryAndUsesLocalizedSummary() async throws {
        let context = try makeContext()
        let health = FailingDeleteDietaryEnergyHealth()
        let sampleUUID = UUID()
        let entry = FoodEntry(
            name: "保留本地",
            calories: 220,
            mealType: .lunch,
            source: .manual,
            healthKitSampleUUID: sampleUUID,
            healthKitSyncStatus: .synced
        )
        context.insert(entry)
        try context.save()

        do {
            try await FoodEntryWriter.delete(
                entry,
                context: context,
                health: health
            )
            XCTFail("远端删除失败时不应删除本地记录")
        } catch let error as FoodEntryWriter.DeletionError {
            XCTAssertTrue(
                error.message(language: .english)
                    .contains("local food entry was kept")
            )
            XCTAssertTrue(
                error.message(language: .traditionalChinese)
                    .contains("本機飲食記錄已保留")
            )
        }

        let stored = try XCTUnwrap(
            try context.fetch(FetchDescriptor<FoodEntry>()).first
        )
        XCTAssertEqual(stored.healthKitSampleUUID, sampleUUID)
        XCTAssertEqual(stored.healthKitSyncStatus, .synced)
    }

    func testRetryCleanupFailureNeverPreparesOrWritesANewSample() async throws {
        let context = try makeContext()
        let health = FailingDeleteDietaryEnergyHealth()
        let entry = FoodEntry(
            name: "停止重试",
            calories: 180,
            mealType: .snack,
            source: .manual,
            healthKitSampleUUID: UUID(),
            healthKitSyncStatus: .uncertain
        )
        context.insert(entry)
        try context.save()

        do {
            try await FoodEntryWriter.retryHealthSync(
                entry,
                context: context,
                health: health
            )
            XCTFail("旧样本未清理时不应继续写入")
        } catch let error as FoodEntryWriter.HealthSyncError {
            XCTAssertTrue(
                error.message(language: .english)
                    .contains("prevent duplicates")
            )
        }

        XCTAssertEqual(health.prepareCallCount, 0)
        XCTAssertEqual(health.saveCallCount, 0)
        XCTAssertNotNil(entry.healthKitSampleUUID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntry>()), 1)
    }

    func testPreparedHealthBatchKeepsInputOrdering() {
        let health = HealthKitManager()
        let batch = health.prepareDietaryEnergy(
            [
                DietaryEnergyWrite(kcal: 100, name: "A", date: .now),
                DietaryEnergyWrite(kcal: 0, name: "B", date: .now),
                DietaryEnergyWrite(kcal: 200, name: "C", date: .now),
            ]
        )

        XCTAssertEqual(batch.sampleUUIDs.count, 3)
        XCTAssertNil(batch.sampleUUIDs[1])
        if health.isAvailable {
            XCTAssertNotNil(batch.sampleUUIDs[0])
            XCTAssertNotNil(batch.sampleUUIDs[2])
        }
    }

    func testDeleteWaitsForPendingHealthWrite() async throws {
        let context = try makeContext()
        let reminders = ReminderScheduler()
        let health = ControlledDietaryEnergyHealth()
        let saveTask = Task<Void, Error> {
            _ = try await FoodEntryWriter.save(
                drafts: [
                    FoodEntryDraft(
                        name: "酸奶",
                        calories: 150,
                        mealType: .snack,
                        source: .manual
                    )
                ],
                context: context,
                health: health,
                reminders: reminders
            )
        }

        while !(await health.saveGate.hasStarted) {
            await Task.yield()
        }
        let visibleEntries = try context.fetch(FetchDescriptor<FoodEntry>())
        let entry = try XCTUnwrap(visibleEntries.first)
        let completion = TestCompletionFlag()
        let deleteTask = Task {
            try await FoodEntryWriter.delete(
                entry,
                context: context,
                health: health
            )
            await completion.markComplete()
        }

        for _ in 0..<20 {
            await Task.yield()
        }
        let deleteFinishedBeforeWrite = await completion.isComplete
        let remoteDeletesBeforeWrite = await health.events.deletedSampleUUIDs
        XCTAssertFalse(deleteFinishedBeforeWrite)
        XCTAssertTrue(remoteDeletesBeforeWrite.isEmpty)

        await health.saveGate.release()
        try await saveTask.value
        try await deleteTask.value

        let remoteDeletesAfterWrite = await health.events.deletedSampleUUIDs
        XCTAssertEqual(remoteDeletesAfterWrite, [try XCTUnwrap(entry.healthKitSampleUUID)])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntry>()), 0)
    }

    func testSaveReturnsAfterLocalCommitWithoutWaitingForHealthKit() async throws {
        let context = try makeContext()
        let reminders = ReminderScheduler()
        let health = ControlledDietaryEnergyHealth()
        let completion = TestCompletionFlag()
        let saveTask = Task<Void, Error> {
            _ = try await FoodEntryWriter.save(
                drafts: [
                    FoodEntryDraft(
                        name: "快捷保存",
                        calories: 160,
                        mealType: .snack,
                        source: .quickRepeat
                    )
                ],
                context: context,
                health: health,
                reminders: reminders
            )
            await completion.markComplete()
        }

        while !(await health.saveGate.hasStarted) {
            await Task.yield()
        }
        var saveCompleted = await completion.isComplete
        for _ in 0..<20 where !saveCompleted {
            await Task.yield()
            saveCompleted = await completion.isComplete
        }

        XCTAssertTrue(saveCompleted)
        try await saveTask.value
        let entries = try context.fetch(FetchDescriptor<FoodEntry>())
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntry>()), 1)
        XCTAssertEqual(entry.name, "快捷保存")
        XCTAssertEqual(entry.healthKitSyncStatus, .pending)

        await health.saveGate.release()
        await FoodEntryWriter.waitForPendingHealthWrites(for: entries)
        XCTAssertEqual(entry.healthKitSyncStatus, .synced)
    }

    func testFailedHealthWriteRetainsUUIDForIdempotentDelete() async throws {
        let context = try makeContext()
        let reminders = ReminderScheduler()
        let health = ControlledDietaryEnergyHealth(shouldFailSave: true)
        let saveTask = Task<Void, Error> {
            _ = try await FoodEntryWriter.save(
                drafts: [
                    FoodEntryDraft(
                        name: "牛奶",
                        calories: 120,
                        mealType: .breakfast,
                        source: .manual
                    )
                ],
                context: context,
                health: health,
                reminders: reminders
            )
        }

        while !(await health.saveGate.hasStarted) {
            await Task.yield()
        }
        await health.saveGate.release()
        try await saveTask.value
        let entry = try XCTUnwrap(
            try context.fetch(FetchDescriptor<FoodEntry>()).first
        )
        await FoodEntryWriter.waitForPendingHealthWrites(for: [entry])
        let sampleUUID = try XCTUnwrap(entry.healthKitSampleUUID)
        XCTAssertEqual(entry.healthKitSyncStatus, .uncertain)

        try await FoodEntryWriter.delete(
            entry,
            context: context,
            health: health
        )

        let deletedSampleUUIDs = await health.events.deletedSampleUUIDs
        XCTAssertEqual(deletedSampleUUIDs, [sampleUUID])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntry>()), 0)
    }

    func testFailedHealthWriteCanRetryWithoutCreatingDuplicateSample() async throws {
        let context = try makeContext()
        let reminders = ReminderScheduler()
        let health = RetryableDietaryEnergyHealth()

        let entries = try await FoodEntryWriter.save(
            drafts: [
                FoodEntryDraft(
                    name: "虾仁",
                    calories: 180,
                    mealType: .lunch,
                    source: .manual
                )
            ],
            context: context,
            health: health,
            reminders: reminders
        )
        let entry = try XCTUnwrap(entries.first)
        await FoodEntryWriter.waitForPendingHealthWrites(for: entries)
        let firstUUID = try XCTUnwrap(entry.healthKitSampleUUID)

        XCTAssertEqual(entry.healthKitSyncStatus, .uncertain)
        XCTAssertEqual(health.saveAttemptCount, 1)

        try await FoodEntryWriter.retryHealthSync(
            entry,
            context: context,
            health: health
        )

        XCTAssertEqual(health.deletedSampleUUIDs, [firstUUID])
        XCTAssertEqual(health.saveAttemptCount, 2)
        XCTAssertNotEqual(entry.healthKitSampleUUID, firstUUID)
        XCTAssertEqual(entry.healthKitSyncStatus, .synced)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntry>()), 1)
    }

    func testDeleteWaitsForRetryAndRemovesTheNewHealthSample() async throws {
        let context = try makeContext()
        let health = RetryDeleteRaceHealth()
        let originalUUID = UUID()
        let entry = FoodEntry(
            name: "并发测试",
            calories: 260,
            mealType: .dinner,
            source: .manual,
            healthKitSampleUUID: originalUUID,
            healthKitSyncStatus: .uncertain
        )
        context.insert(entry)
        try context.save()

        let retryTask = Task {
            try await FoodEntryWriter.retryHealthSync(
                entry,
                context: context,
                health: health
            )
        }
        while !(await health.firstDeleteGate.hasStarted) {
            await Task.yield()
        }

        let deleteCompletion = TestCompletionFlag()
        let deleteTask = Task {
            try await FoodEntryWriter.delete(
                entry,
                context: context,
                health: health
            )
            await deleteCompletion.markComplete()
        }

        for _ in 0..<20 {
            await Task.yield()
        }
        let deleteFinishedBeforeRetry = await deleteCompletion.isComplete
        let deletesBeforeRetry = await health.state.deletedSampleUUIDs
        XCTAssertFalse(deleteFinishedBeforeRetry)
        XCTAssertEqual(deletesBeforeRetry, [originalUUID])

        await health.firstDeleteGate.release()
        try await retryTask.value
        try await deleteTask.value

        let deletedSampleUUIDs = await health.state.deletedSampleUUIDs
        let savedSampleUUIDs = await health.state.savedSampleUUIDs
        XCTAssertEqual(savedSampleUUIDs.count, 1)
        XCTAssertEqual(
            deletedSampleUUIDs,
            [originalUUID, try XCTUnwrap(savedSampleUUIDs.first)]
        )
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntry>()), 0)
    }

    func testRetryQueuedAfterDeleteDoesNotCreateAnOrphanHealthSample() async throws {
        let context = try makeContext()
        let health = RetryDeleteRaceHealth()
        let originalUUID = UUID()
        let entry = FoodEntry(
            name: "删除优先",
            calories: 180,
            mealType: .snack,
            source: .manual,
            healthKitSampleUUID: originalUUID,
            healthKitSyncStatus: .uncertain
        )
        context.insert(entry)
        try context.save()

        let deleteTask = Task {
            try await FoodEntryWriter.delete(
                entry,
                context: context,
                health: health
            )
        }
        while !(await health.firstDeleteGate.hasStarted) {
            await Task.yield()
        }
        let retryTask = Task {
            try await FoodEntryWriter.retryHealthSync(
                entry,
                context: context,
                health: health
            )
        }

        await health.firstDeleteGate.release()
        try await deleteTask.value

        do {
            try await retryTask.value
            XCTFail("本地记录删除后不应继续创建新的 HealthKit 样本")
        } catch {
            XCTAssertTrue(error is FoodEntryWriter.HealthSyncError)
        }

        let deletedSampleUUIDs = await health.state.deletedSampleUUIDs
        let savedSampleUUIDs = await health.state.savedSampleUUIDs
        XCTAssertEqual(deletedSampleUUIDs, [originalUUID])
        XCTAssertTrue(savedSampleUUIDs.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntry>()), 0)
    }

    func testLegacyStatusInfersSyncedOnlyWhenUUIDExists() {
        let localOnly = FoodEntry(
            name: "苹果",
            calories: 95,
            mealType: .snack,
            source: .manual
        )
        let legacySynced = FoodEntry(
            name: "米饭",
            calories: 200,
            mealType: .lunch,
            source: .manual,
            healthKitSampleUUID: UUID()
        )

        XCTAssertEqual(localOnly.healthKitSyncStatus, .notRequested)
        XCTAssertEqual(legacySynced.healthKitSyncStatus, .synced)
    }

    func testSyncedStatusWithoutUUIDRecoversAsLocalOnly() {
        let entry = FoodEntry(
            name: "远端已删除",
            calories: 100,
            mealType: .snack,
            source: .manual,
            healthKitSampleUUID: nil,
            healthKitSyncStatus: .synced
        )

        XCTAssertEqual(entry.healthKitSyncStatus, .notRequested)
        XCTAssertFalse(entry.healthKitSyncStatus.needsAttention)
    }

    func testInterruptedPendingStatusRemainsRetryableAfterRelaunch() {
        let entry = FoodEntry(
            name: "西兰花",
            calories: 60,
            mealType: .dinner,
            source: .manual,
            healthKitSampleUUID: UUID(),
            healthKitSyncStatus: .pending
        )

        XCTAssertEqual(entry.healthKitSyncStatus, .pending)
        XCTAssertTrue(entry.healthKitSyncStatus.needsAttention)
    }
}
