import Foundation
import Testing
@testable import PrimuseKit

@Suite("Adaptive metadata reading")
struct MetadataReadSchedulerTests {
    @Test func preferencesMigrateWithoutOverridingExplicitSelection() {
        #expect(MetadataReadingMode.resolve(storedValue: nil, legacyFastEnabled: false) == .automatic)
        #expect(MetadataReadingMode.resolve(storedValue: nil, legacyFastEnabled: true) == .fast)
        #expect(MetadataReadingMode.resolve(storedValue: "energySaving", legacyFastEnabled: true) == .energySaving)
    }

    @Test func foregroundEntrypointsShareTheSelectedBudget() {
        for preference in MetadataReadingMode.allCases {
            let scan = MetadataBackfillExecutionPolicy.limits(for: .foregroundAfterSourceScan, preference: preference)
            #expect(scan == MetadataBackfillExecutionPolicy.limits(for: .userInitiated, preference: preference))
            #expect(scan == MetadataBackfillExecutionPolicy.limits(for: .standard, preference: preference))
        }
    }

    @Test func speedNeverOverridesThermalOrPlaybackProtection() {
        for preference in MetadataReadingMode.allCases {
            let paused = MetadataBackfillExecutionPolicy.limits(
                for: .userInitiated, preference: preference,
                environment: .init(thermalState: .critical)
            )
            #expect(paused.workerCount == 0)
            let hot = MetadataBackfillExecutionPolicy.limits(
                for: .foregroundAfterSourceScan, preference: preference,
                environment: .init(thermalState: .serious)
            )
            #expect(hot.workerCount == 1)
            #expect(hot.interRequestDelay >= 1.5)
            let playback = MetadataBackfillExecutionPolicy.limits(
                for: .userInitiated, preference: preference,
                environment: .init(playbackActive: true)
            )
            #expect(playback.workerCount == 1)
            let lowPower = MetadataBackfillExecutionPolicy.limits(
                for: .userInitiated, preference: preference,
                environment: .init(lowPowerMode: true)
            )
            #expect(lowPower.workerCount == 1)
            #expect(lowPower.interRequestDelay > 0)
            let background = MetadataBackfillExecutionPolicy.limits(for: .background, preference: preference)
            #expect(background.snapshotLimit == 24 && background.snapshotPassLimit == 1)
        }
    }

    @Test @MainActor func liveResizeAndThermalPausePreserveExactlyOnceReads() async throws {
        let scheduler = MetadataReadScheduler<Int, Int>()
        var workers = 1
        var started: [Int] = []
        var completed: [Int] = []
        var gates: [Int: CheckedContinuation<Int, Never>] = [:]
        let task = Task {
            await scheduler.run(
                items: Array(0..<6),
                limits: { .init(workerCount: workers, snapshotLimit: 6, interRequestDelay: 0, flushInterval: 5) },
                read: { item in
                    started.append(item)
                    return await withCheckedContinuation { gates[item] = $0 }
                },
                completed: { item, _ in completed.append(item) }
            )
        }
        defer {
            task.cancel()
            for (item, gate) in gates { gate.resume(returning: item) }
        }
        try await waitUntil { started.count == 1 }
        workers = 3
        scheduler.configurationChanged()
        try await waitUntil { started.count == 3 }
        workers = 1
        scheduler.configurationChanged()
        for item in [0, 1] { gates.removeValue(forKey: item)?.resume(returning: item) }
        try await waitUntil { completed.count == 2 }
        #expect(started == [0, 1, 2])
        gates.removeValue(forKey: 2)?.resume(returning: 2)
        try await waitUntil { started.count == 4 }
        workers = 0
        scheduler.configurationChanged()
        gates.removeValue(forKey: 3)?.resume(returning: 3)
        try await waitUntil { completed.count == 4 }
        #expect(started.count == 4)
        workers = 2
        scheduler.configurationChanged()
        try await waitUntil { started.count == 6 }
        for item in [4, 5] { gates.removeValue(forKey: item)?.resume(returning: item) }
        await task.value
        #expect(completed.sorted() == Array(0..<6))
    }

    @Test @MainActor func cancellingPausedQueueDoesNotReadOrHang() async {
        let scheduler = MetadataReadScheduler<Int, Int>()
        var reads = 0
        let task = Task {
            await scheduler.run(
                items: [1, 2],
                limits: { .init(workerCount: 0, snapshotLimit: 2, interRequestDelay: 0, flushInterval: 5) },
                read: { item in reads += 1; return item },
                completed: { _, _ in }
            )
        }
        await Task.yield()
        task.cancel()
        await task.value
        #expect(reads == 0)
    }

    @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(condition())
    }
}
