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
}
