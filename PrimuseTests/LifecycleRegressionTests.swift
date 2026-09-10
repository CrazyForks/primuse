import Foundation
import PrimuseKit
import XCTest
@testable import Primuse

final class LifecycleRegressionTests: XCTestCase {
    #if os(iOS)
    @MainActor
    func testBackgroundPlaybackPreservesPendingSceneSettlement() async {
        let coordinator = BackgroundLibraryMaintenanceCoordinator(isApplicationInBackground: { true })
        let settled = expectation(description: "Background publications and persistence are released")
        coordinator.scheduleSceneSettle(after: .milliseconds(20)) {
            settled.fulfill()
        }

        coordinator.cancelMaintenance()

        await fulfillment(of: [settled], timeout: 1)
        coordinator.cancel()
    }

    @MainActor
    func testReturningToForegroundCancelsPendingSceneSettlement() async throws {
        let coordinator = BackgroundLibraryMaintenanceCoordinator(isApplicationInBackground: { true })
        var settlementCount = 0
        coordinator.scheduleSceneSettle(after: .milliseconds(20)) {
            settlementCount += 1
        }

        coordinator.cancel()
        try await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(settlementCount, 0)
    }

    @MainActor
    func testSceneSettlementRechecksCurrentApplicationState() async throws {
        var isBackground = true
        let coordinator = BackgroundLibraryMaintenanceCoordinator(isApplicationInBackground: { isBackground })
        var settlementCount = 0
        coordinator.scheduleSceneSettle(after: .milliseconds(20)) {
            settlementCount += 1
        }

        isBackground = false
        try await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(settlementCount, 0)
        coordinator.cancel()
    }
    #endif

    @MainActor
    func testSceneTransitionGateReopensWhenReturningToForeground() {
        let scraper = MusicScraperService(sourceManager: SourceManager(sourcesProvider: { [] }))
        let library = MusicLibrary(storageDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("PrimuseLifecycleTests-\(UUID().uuidString)", isDirectory: true))

        XCTAssertFalse(scraper.isGatedForSceneTransition)
        // A cold launch never saw a transition, so nothing may be resumed.
        scraper.resumeAfterSceneTransition(in: library)
        XCTAssertFalse(scraper.isGatedForSceneTransition)

        scraper.pauseForSceneTransition()
        XCTAssertTrue(scraper.isGatedForSceneTransition)
        scraper.pauseForSceneTransition()
        XCTAssertTrue(scraper.isGatedForSceneTransition)

        scraper.resumeAfterSceneTransition(in: library)
        XCTAssertFalse(scraper.isGatedForSceneTransition)
        XCTAssertFalse(scraper.isScraping)
    }

    @MainActor
    func testInvalidRangeResponseIsRetriedWithoutEndpointProbe() {
        let error = MetadataRangeReadError.invalidRangeResponse
        XCTAssertTrue(MetadataBackfillService.isTransientBackfillError(error))
        XCTAssertFalse(MetadataBackfillService.isSourceUnavailableBackfillError(error))
        XCTAssertFalse(MetadataBackfillService.needsSourceEndpointProbe(error))
        // A plain connection failure still asks the endpoint before parking a source.
        XCTAssertTrue(MetadataBackfillService.needsSourceEndpointProbe(SourceError.connectionFailed("offline")))
        XCTAssertFalse(MetadataRangeReadError.invalidRangeResponse.localizedDescription.isEmpty)
    }

    func testCancellingCacheWaiterReturnsWithoutCancellingSharedTransfer() async {
        let gate = AsyncStream<Void>.makeStream()
        let transfer = Task {
            for await _ in gate.stream { break }
        }
        let cancelledWaiterReturned = expectation(description: "Cancelled requester returns before transfer finishes")
        let cancelledWaiter = Task {
            await BackgroundAudioCacheTaskWaiter.wait(for: transfer)
            cancelledWaiterReturned.fulfill()
        }
        let remainingWaiter = Task {
            await BackgroundAudioCacheTaskWaiter.wait(for: transfer)
        }

        await Task.yield()
        cancelledWaiter.cancel()
        await fulfillment(of: [cancelledWaiterReturned], timeout: 1)
        XCTAssertFalse(transfer.isCancelled)
        XCTAssertFalse(remainingWaiter.isCancelled)

        gate.continuation.finish()
        await remainingWaiter.value
        await cancelledWaiter.value
    }

    func testAlreadyCancelledCacheWaiterDoesNotCancelSharedTransfer() async {
        let gate = AsyncStream<Void>.makeStream()
        let transfer = Task {
            for await _ in gate.stream { break }
        }
        let returned = expectation(description: "Already cancelled requester returns immediately")
        let waiter = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await BackgroundAudioCacheTaskWaiter.wait(for: transfer)
            returned.fulfill()
        }

        await fulfillment(of: [returned], timeout: 1)
        XCTAssertFalse(transfer.isCancelled)
        gate.continuation.finish()
        await transfer.value
        await waiter.value
    }

    // MARK: - BGProcessing drain

    /// iOS expires the BGProcessing task while scans are still running: the
    /// task must be completed exactly once, the running work cancelled, and a
    /// replacement request submitted exactly once so the remaining work still
    /// gets a later wake.
    @MainActor
    func testBackgroundDrainExpirationDuringScanWaitCancelsWorkAndRenewsRequest() async {
        let completion = TestBackgroundTaskCompletion()
        let recorder = BackgroundDrainRecorder()
        let box = BackgroundDrainBox()
        var dependencies = BackgroundProcessingDrain.Dependencies()
        dependencies.isPlaybackActive = { false }
        dependencies.isApplicationActive = { false }
        dependencies.hasResumableScanWork = { true }
        dependencies.resumeScans = { recorder.record("resumeScans") }
        dependencies.waitForScans = {
            recorder.record("waitForScans")
            box.drain?.expire()
        }
        dependencies.cancelScans = { recorder.record("cancelScans") }
        dependencies.hasPendingScrape = { true }
        dependencies.resumeScrape = { recorder.record("resumeScrape") }
        dependencies.cancelScrape = { recorder.record("cancelScrape") }
        dependencies.backfillHasPendingWork = { true }
        dependencies.startBackfill = { recorder.record("startBackfill") }
        dependencies.expireBackfill = { recorder.record("expireBackfill") }
        dependencies.scheduleNextRequest = { recorder.record("scheduleNextRequest") }

        let drain = BackgroundProcessingDrain(completion: completion, dependencies: dependencies)
        box.drain = drain
        await drain.run()
        // `expire()` completes the task synchronously and hands the teardown
        // to the main actor; yielding lets that already-enqueued job run.
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(completion.completionResults, [false])
        XCTAssertEqual(recorder.count(of: "cancelScans"), 1)
        XCTAssertEqual(recorder.count(of: "cancelScrape"), 1)
        XCTAssertEqual(recorder.count(of: "expireBackfill"), 1)
        XCTAssertEqual(recorder.count(of: "scheduleNextRequest"), 1)
        // The expired drain must not start any further stage.
        XCTAssertEqual(recorder.count(of: "resumeScrape"), 0)
        XCTAssertEqual(recorder.count(of: "startBackfill"), 0)
    }

    /// An expiration that arrives after the app has returned to the foreground
    /// must not cancel the newer foreground scan, but still has to renew.
    @MainActor
    func testBackgroundDrainExpirationSkipsCancellationWhileApplicationIsActive() async {
        let completion = TestBackgroundTaskCompletion()
        let recorder = BackgroundDrainRecorder()
        var dependencies = BackgroundProcessingDrain.Dependencies()
        dependencies.isApplicationActive = { true }
        dependencies.cancelScans = { recorder.record("cancelScans") }
        dependencies.cancelScrape = { recorder.record("cancelScrape") }
        dependencies.expireBackfill = { recorder.record("expireBackfill") }
        dependencies.scheduleNextRequest = { recorder.record("scheduleNextRequest") }

        let drain = BackgroundProcessingDrain(completion: completion, dependencies: dependencies)
        XCTAssertTrue(completion.complete(success: false))
        drain.finishExpiration()

        XCTAssertEqual(recorder.count(of: "cancelScans"), 0)
        XCTAssertEqual(recorder.count(of: "cancelScrape"), 0)
        XCTAssertEqual(recorder.count(of: "expireBackfill"), 1)
        XCTAssertEqual(recorder.count(of: "scheduleNextRequest"), 1)
    }

    /// Scans keep running on the reduced playback profile while audio plays,
    /// so the BGProcessing task is routinely expired mid-scan. That expiration
    /// must not cancel them: the audio session keeps the process alive and the
    /// per-scan assertion is re-acquired once playback stops. Scraping stays
    /// cancelled and the request is still renewed exactly once.
    @MainActor
    func testBackgroundDrainExpirationDuringPlaybackKeepsScansRunning() async {
        let completion = TestBackgroundTaskCompletion()
        let recorder = BackgroundDrainRecorder()
        let box = BackgroundDrainBox()
        var dependencies = BackgroundProcessingDrain.Dependencies()
        dependencies.isPlaybackActive = { true }
        dependencies.isApplicationActive = { false }
        dependencies.hasResumableScanWork = { true }
        dependencies.resumeScans = { recorder.record("resumeScans") }
        dependencies.waitForScans = {
            recorder.record("waitForScans")
            box.drain?.expire()
        }
        dependencies.cancelScans = { recorder.record("cancelScans") }
        dependencies.cancelScrape = { recorder.record("cancelScrape") }
        dependencies.backfillHasPendingWork = { true }
        dependencies.startBackfill = { recorder.record("startBackfill") }
        dependencies.expireBackfill = { recorder.record("expireBackfill") }
        dependencies.setBackgroundPlaybackActive = {
            recorder.record("setBackgroundPlaybackActive(\($0))")
        }
        dependencies.scheduleNextRequest = { recorder.record("scheduleNextRequest") }

        let drain = BackgroundProcessingDrain(completion: completion, dependencies: dependencies)
        box.drain = drain
        await drain.run()
        // `expire()` completes the task synchronously and hands the teardown
        // to the main actor; yielding lets that already-enqueued job run.
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(completion.completionResults, [false])
        XCTAssertEqual(recorder.count(of: "setBackgroundPlaybackActive(true)"), 1)
        XCTAssertEqual(recorder.count(of: "cancelScans"), 0)
        XCTAssertEqual(recorder.count(of: "cancelScrape"), 1)
        XCTAssertEqual(recorder.count(of: "expireBackfill"), 1)
        XCTAssertEqual(recorder.count(of: "scheduleNextRequest"), 1)
        XCTAssertEqual(recorder.count(of: "startBackfill"), 0)
    }

    /// Nothing pending: the drain still completes once and renews once (the
    /// renewal call cancels the stale request when there is no work left).
    @MainActor
    func testBackgroundDrainWithoutPendingWorkCompletesAndSchedulesOnce() async {
        let completion = TestBackgroundTaskCompletion()
        let recorder = BackgroundDrainRecorder()
        var dependencies = BackgroundProcessingDrain.Dependencies()
        dependencies.hasResumableScanWork = { false }
        dependencies.hasPendingScrape = { false }
        dependencies.backfillHasPendingWork = { false }
        dependencies.resumeScans = { recorder.record("resumeScans") }
        dependencies.resumeScrape = { recorder.record("resumeScrape") }
        dependencies.startBackfill = { recorder.record("startBackfill") }
        dependencies.scheduleNextRequest = { recorder.record("scheduleNextRequest") }

        let drain = BackgroundProcessingDrain(completion: completion, dependencies: dependencies)
        await drain.run()

        XCTAssertEqual(completion.completionResults, [true])
        XCTAssertEqual(recorder.count(of: "scheduleNextRequest"), 1)
        XCTAssertEqual(recorder.count(of: "resumeScans"), 0)
        XCTAssertEqual(recorder.count(of: "resumeScrape"), 0)
        XCTAssertEqual(recorder.count(of: "startBackfill"), 0)
    }

    /// Playback can start from the lock screen while the drain waits. The
    /// remaining stages then run on the playback profile: scans continue,
    /// scraping stays postponed.
    @MainActor
    func testBackgroundDrainSwitchesToPlaybackPathWithoutResumingScraping() async {
        let completion = TestBackgroundTaskCompletion()
        let recorder = BackgroundDrainRecorder()
        recorder.hasScanWork = true
        var dependencies = BackgroundProcessingDrain.Dependencies()
        dependencies.isPlaybackActive = { recorder.playbackIsActive }
        dependencies.hasResumableScanWork = { recorder.hasScanWork }
        dependencies.resumeScans = {
            recorder.record("resumeScans")
            recorder.hasScanWork = false
        }
        dependencies.waitForScans = {
            recorder.record("waitForScans")
            recorder.playbackIsActive = true
        }
        dependencies.hasPendingScrape = { true }
        dependencies.resumeScrape = { recorder.record("resumeScrape") }
        dependencies.backfillHasPendingWork = { true }
        dependencies.startBackfill = { recorder.record("startBackfill") }
        dependencies.setBackfillMode = { recorder.backfillModes.append($0) }
        dependencies.setBackgroundPlaybackActive = { recorder.playbackProfiles.append($0) }
        dependencies.scheduleNextRequest = { recorder.record("scheduleNextRequest") }

        let drain = BackgroundProcessingDrain(completion: completion, dependencies: dependencies)
        await drain.run()

        XCTAssertEqual(recorder.count(of: "resumeScrape"), 0)
        XCTAssertEqual(recorder.count(of: "resumeScans"), 1)
        XCTAssertEqual(recorder.count(of: "startBackfill"), 1)
        XCTAssertEqual(recorder.backfillModes, [.background, .backgroundDuringPlayback])
        XCTAssertEqual(recorder.playbackProfiles, [false, true])
        XCTAssertEqual(completion.completionResults, [true])
        XCTAssertEqual(recorder.count(of: "scheduleNextRequest"), 1)
    }

    /// The undisturbed sequence: scans, then scraping, then backfill, then a
    /// single renewal and a single completion.
    @MainActor
    func testBackgroundDrainNormalCompletionRunsEveryStageOnce() async {
        let completion = TestBackgroundTaskCompletion()
        let recorder = BackgroundDrainRecorder()
        var dependencies = BackgroundProcessingDrain.Dependencies()
        dependencies.hasResumableScanWork = { true }
        dependencies.hasPendingScrape = { true }
        dependencies.backfillHasPendingWork = { true }
        dependencies.prepareNonPlaybackWork = { recorder.record("prepare") }
        dependencies.resumeScans = { recorder.record("resumeScans") }
        dependencies.startPeriodicQuickSync = { recorder.record("periodicQuickSync") }
        dependencies.waitForScans = { recorder.record("waitForScans") }
        dependencies.resumeScrape = { recorder.record("resumeScrape") }
        dependencies.waitForScrape = { recorder.record("waitForScrape") }
        dependencies.startBackfill = { recorder.record("startBackfill") }
        dependencies.waitBackfillIdle = { recorder.record("waitBackfillIdle") }
        dependencies.setBackfillMode = { recorder.backfillModes.append($0) }
        dependencies.setBackgroundPlaybackActive = { recorder.playbackProfiles.append($0) }
        dependencies.scheduleNextRequest = { recorder.record("scheduleNextRequest") }

        let drain = BackgroundProcessingDrain(completion: completion, dependencies: dependencies)
        await drain.run()

        XCTAssertEqual(recorder.events, [
            "prepare",
            "resumeScans",
            "periodicQuickSync",
            "waitForScans",
            "resumeScrape",
            "waitForScrape",
            "startBackfill",
            "waitBackfillIdle",
            "scheduleNextRequest"
        ])
        XCTAssertEqual(recorder.backfillModes, [.background])
        XCTAssertEqual(recorder.playbackProfiles, [false])
        XCTAssertEqual(completion.completionResults, [true])
    }

    /// A late expiration for a task that already finished changes nothing —
    /// no second completion, no second request, no cancellation.
    @MainActor
    func testBackgroundDrainExpirationAfterNormalCompletionIsANoOp() async {
        let completion = TestBackgroundTaskCompletion()
        let recorder = BackgroundDrainRecorder()
        var dependencies = BackgroundProcessingDrain.Dependencies()
        dependencies.isApplicationActive = { false }
        dependencies.cancelScans = { recorder.record("cancelScans") }
        dependencies.cancelScrape = { recorder.record("cancelScrape") }
        dependencies.expireBackfill = { recorder.record("expireBackfill") }
        dependencies.scheduleNextRequest = { recorder.record("scheduleNextRequest") }

        let drain = BackgroundProcessingDrain(completion: completion, dependencies: dependencies)
        await drain.run()
        drain.expire()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(completion.completionResults, [true])
        XCTAssertEqual(recorder.count(of: "scheduleNextRequest"), 1)
        XCTAssertEqual(recorder.count(of: "cancelScans"), 0)
        XCTAssertEqual(recorder.count(of: "cancelScrape"), 0)
        XCTAssertEqual(recorder.count(of: "expireBackfill"), 0)
    }

    // MARK: - Bounded scanning during background playback

    func testScanExecutionProfileKeepsForegroundCadenceAndBoundsPlayback() {
        XCTAssertEqual(ScanExecutionProfilePolicy.flushBatchSize(for: .standard), 200)
        XCTAssertEqual(ScanExecutionProfilePolicy.flushInterval(for: .standard), 1.5)
        XCTAssertEqual(ScanExecutionProfilePolicy.progressPublishInterval(for: .standard), 0.75)
        XCTAssertEqual(ScanExecutionProfilePolicy.flushBatchSize(for: .backgroundPlayback), 400)
        XCTAssertEqual(ScanExecutionProfilePolicy.flushInterval(for: .backgroundPlayback), 5)
        XCTAssertEqual(ScanExecutionProfilePolicy.progressPublishInterval(for: .backgroundPlayback), 5)
        // Background playback must always commit less often than the foreground.
        XCTAssertGreaterThan(
            ScanExecutionProfilePolicy.flushBatchSize(for: .backgroundPlayback),
            ScanExecutionProfilePolicy.flushBatchSize(for: .standard)
        )
        XCTAssertGreaterThan(
            ScanExecutionProfilePolicy.flushInterval(for: .backgroundPlayback),
            ScanExecutionProfilePolicy.flushInterval(for: .standard)
        )
        XCTAssertGreaterThan(
            ScanExecutionProfilePolicy.progressPublishInterval(for: .backgroundPlayback),
            ScanExecutionProfilePolicy.progressPublishInterval(for: .standard)
        )
    }

    func testScanExecutionProfilePriorityLeavesForegroundUnchanged() {
        XCTAssertEqual(
            ScanExecutionProfilePolicy.taskPriority(for: .standard, context: .userInitiatedForeground),
            .userInitiated
        )
        XCTAssertEqual(
            ScanExecutionProfilePolicy.taskPriority(for: .standard, context: .foregroundResume),
            .utility
        )
        XCTAssertEqual(
            ScanExecutionProfilePolicy.taskPriority(for: .standard, context: .background),
            .utility
        )
        // Audio always outranks scanning while the app runs on playback time.
        XCTAssertEqual(
            ScanExecutionProfilePolicy.taskPriority(for: .backgroundPlayback, context: .background),
            .background
        )
        XCTAssertEqual(
            ScanExecutionProfilePolicy.taskPriority(for: .backgroundPlayback, context: .userInitiatedForeground),
            .background
        )
    }

    // MARK: - Manual/automatic backfill budget ownership

    /// A registered manual batch owns the shared worker budget only while it
    /// can run. Backgrounded, its own limits closure yields zero workers, so
    /// the automatic budget must apply instead of starving both queues.
    func testManualBatchOwnsAutomaticBudgetOnlyWhileApplicationIsActive() {
        XCTAssertTrue(MetadataBackfillService.manualBatchOwnsAutomaticBudget(
            hasRegisteredManualBatch: true, applicationIsActive: true
        ))
        XCTAssertFalse(MetadataBackfillService.manualBatchOwnsAutomaticBudget(
            hasRegisteredManualBatch: true, applicationIsActive: false
        ))
        XCTAssertFalse(MetadataBackfillService.manualBatchOwnsAutomaticBudget(
            hasRegisteredManualBatch: false, applicationIsActive: true
        ))
        XCTAssertFalse(MetadataBackfillService.manualBatchOwnsAutomaticBudget(
            hasRegisteredManualBatch: false, applicationIsActive: false
        ))
    }

    /// A batch that cannot run still keeps the slots its already-dispatched
    /// reads occupy, so the automatic queue only takes what is left over and
    /// the two queues together stay inside the device worker ceiling.
    func testAutomaticWorkerCountSubtractsManualInFlightWhileBatchCannotRun() {
        XCTAssertEqual(MetadataBackfillService.automaticWorkerCount(
            budgetWorkerCount: 4, hasRegisteredManualBatch: true,
            applicationIsActive: true, manualInFlightCount: 2
        ), 0)
        XCTAssertEqual(MetadataBackfillService.automaticWorkerCount(
            budgetWorkerCount: 4, hasRegisteredManualBatch: true,
            applicationIsActive: false, manualInFlightCount: 3
        ), 1)
        XCTAssertEqual(MetadataBackfillService.automaticWorkerCount(
            budgetWorkerCount: 4, hasRegisteredManualBatch: true,
            applicationIsActive: false, manualInFlightCount: 6
        ), 0)
        XCTAssertEqual(MetadataBackfillService.automaticWorkerCount(
            budgetWorkerCount: 4, hasRegisteredManualBatch: false,
            applicationIsActive: false, manualInFlightCount: 3
        ), 4)
    }
}

/// Records the drain's injected calls in order. `@MainActor` makes it usable
/// from the drain's main-actor `@Sendable` dependency closures.
@MainActor
private final class BackgroundDrainRecorder {
    private(set) var events: [String] = []
    var backfillModes: [MetadataBackfillExecutionMode] = []
    var playbackProfiles: [Bool] = []
    var playbackIsActive = false
    var hasScanWork = false

    func record(_ event: String) {
        events.append(event)
    }

    func count(of event: String) -> Int {
        events.filter { $0 == event }.count
    }
}

/// Lets a dependency closure reach the drain that owns it, so a test can
/// expire the task from inside one of its awaits.
@MainActor
private final class BackgroundDrainBox {
    var drain: BackgroundProcessingDrain?
}

/// Stand-in for the `BGTask`-backed completion, recording every accepted
/// completion so "exactly once" can be asserted.
private final class TestBackgroundTaskCompletion: BackgroundTaskCompleting, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCompletions: [Bool] = []

    var isCompleted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !recordedCompletions.isEmpty
    }

    var completionResults: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCompletions
    }

    @discardableResult
    func complete(success: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard recordedCompletions.isEmpty else { return false }
        recordedCompletions.append(success)
        return true
    }
}
