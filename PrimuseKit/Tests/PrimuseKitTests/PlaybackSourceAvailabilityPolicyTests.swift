import Testing
@testable import PrimuseKit

@Suite struct PlaybackSourceAvailabilityPolicyTests {
    @Test func mixedQueueSkipsEveryUnavailableSourceEntryButKeepsOfflineCopies() {
        let sources = ["wan", "lan", "wan", "lan", "lan"]
        let cached = [false, false, false, false, true]
        let isAvailable: (Int) -> Bool = { index in
            PlaybackSourceAvailabilityPolicy.allowsPlayback(
                isSourceEnabled: true,
                isSourceUnreachable: sources[index] == "lan",
                hasUsableLocalAudio: cached[index]
            )
        }
        #expect(QueueTraversalPolicy.nextAvailableIndex(
            queueCount: sources.count, after: 0, wraps: false,
            isAvailable: isAvailable
        ) == 2)
        #expect(QueueTraversalPolicy.nextAvailableIndex(
            queueCount: sources.count, after: 2, wraps: false,
            isAvailable: isAvailable
        ) == 4)
        let shuffleOrder = [0, 3, 1, 4, 2]
        #expect(QueueTraversalPolicy.nextAvailableTraversalPosition(
            in: shuffleOrder, queueCount: sources.count, after: 0,
            isAvailable: isAvailable
        ) == 3)
    }

    @Test func allUnavailableQueueHasNoSuccessorEvenWithRepeatAll() {
        #expect(QueueTraversalPolicy.nextAvailableIndex(
            queueCount: 500, after: 218, wraps: true,
            isAvailable: { _ in
                PlaybackSourceAvailabilityPolicy.allowsPlayback(
                    isSourceEnabled: true,
                    isSourceUnreachable: true,
                    hasUsableLocalAudio: false
                )
            }
        ) == nil)
        #expect(!PlaybackSourceAvailabilityPolicy.allowsPlayback(
            isSourceEnabled: false,
            isSourceUnreachable: true,
            hasUsableLocalAudio: true
        ))
    }

    @Test func newNetworkAndSourceConfigurationDiscardOldOutageEvidence() {
        var policy = PlaybackSourceAvailabilityPolicy()
        policy.record(isUnreachable: true, sourceID: "nas", networkGeneration: 3,
                      sourceGeneration: 4, now: 100)
        #expect(policy.cachedUnavailability(sourceID: "nas", networkGeneration: 3,
                                           sourceGeneration: 4, now: 101) == true)
        #expect(policy.cachedUnavailability(sourceID: "nas", networkGeneration: 4,
                                           sourceGeneration: 4, now: 101) == nil)
        #expect(policy.cachedUnavailability(sourceID: "nas", networkGeneration: 3,
                                           sourceGeneration: 5, now: 101) == nil)
        #expect(policy.cachedUnavailability(sourceID: "other", networkGeneration: 3,
                                           sourceGeneration: 4, now: 101) == nil)
    }

    @Test func serverRecoveryBecomesEligibleAfterExpiryOrExplicitReconnect() {
        var policy = PlaybackSourceAvailabilityPolicy()
        policy.record(isUnreachable: true, sourceID: "nas", networkGeneration: 1,
                      sourceGeneration: 0, now: 0)
        #expect(policy.cachedUnavailability(sourceID: "nas", networkGeneration: 1,
                                           sourceGeneration: 0, now: 60) == nil)
        policy.invalidate(sourceID: "nas")
        #expect(policy.cachedUnavailability(sourceID: "nas", networkGeneration: 1,
                                           sourceGeneration: 0, now: 1) == nil)
        policy.record(isUnreachable: false, sourceID: "nas", networkGeneration: 1,
                      sourceGeneration: 0, now: 1)
        #expect(policy.cachedUnavailability(sourceID: "nas", networkGeneration: 1,
                                           sourceGeneration: 0, now: 2) == false)
        #expect(policy.cachedUnavailability(sourceID: "nas", networkGeneration: 1,
                                           sourceGeneration: 0, now: 16) == nil)
    }
}
