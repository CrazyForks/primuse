public struct PlaybackSourceAvailabilityPolicy: Sendable {
    private struct Entry: Sendable {
        let isUnreachable: Bool
        let networkGeneration: UInt64
        let sourceGeneration: Int
        let expiresAt: Double
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    public func cachedUnavailability(
        sourceID: String,
        networkGeneration: UInt64,
        sourceGeneration: Int,
        now: Double
    ) -> Bool? {
        guard let entry = entries[sourceID],
              entry.networkGeneration == networkGeneration,
              entry.sourceGeneration == sourceGeneration,
              now < entry.expiresAt else { return nil }
        return entry.isUnreachable
    }

    /// Probe results belong to a device network path and source configuration,
    /// never to the durable library. A server can recover without either one
    /// changing, so failures also expire and explicit reconnects can clear them.
    public mutating func record(
        isUnreachable: Bool,
        sourceID: String,
        networkGeneration: UInt64,
        sourceGeneration: Int,
        now: Double
    ) {
        entries[sourceID] = Entry(
            isUnreachable: isUnreachable,
            networkGeneration: networkGeneration,
            sourceGeneration: sourceGeneration,
            expiresAt: now + (isUnreachable ? 60 : 15)
        )
    }

    public mutating func invalidate(sourceID: String) {
        entries.removeValue(forKey: sourceID)
    }

    public static func allowsPlayback(
        isSourceEnabled: Bool,
        isSourceUnreachable: Bool,
        hasUsableLocalAudio: Bool
    ) -> Bool {
        isSourceEnabled && (!isSourceUnreachable || hasUsableLocalAudio)
    }
}
