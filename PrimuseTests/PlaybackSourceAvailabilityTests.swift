import Foundation
import PrimuseKit
import XCTest
@testable import Primuse

final class PlaybackSourceAvailabilityTests: XCTestCase {
    private actor ProbeLog {
        var hosts: [String] = []
        func record(_ host: String) { hosts.append(host) }
    }

    @MainActor
    func testSourceOutageIsCachedAndAnExplicitRetryCanRecover() async {
        let source = MusicSource(
            id: "playback-outage-\(UUID().uuidString)",
            name: "Playback Test",
            type: .navidrome,
            host: "nas.invalid",
            port: 4533
        )
        let manager = SourceManager(sourcesProvider: { [source] })
        let calls = ProbeLog()
        let unavailable = await manager.playbackSourceEndpointsAreUnavailable(
            sourceID: source.id,
            probe: { endpoint in
                await calls.record(endpoint.host)
                throw URLError(.cannotConnectToHost)
            }
        )
        XCTAssertTrue(unavailable)
        XCTAssertTrue(manager.isSourceKnownUnavailableForPlayback(source.id))
        let repeated = await manager.playbackSourceEndpointsAreUnavailable(
            sourceID: source.id,
            probe: { endpoint in await calls.record(endpoint.host) }
        )
        XCTAssertTrue(repeated)
        let beforeRetry = await calls.hosts
        XCTAssertEqual(beforeRetry.count, 1)

        let afterRetry = await manager.playbackSourceEndpointsAreUnavailable(
            sourceID: source.id,
            refresh: true,
            probe: { endpoint in await calls.record(endpoint.host) }
        )
        XCTAssertFalse(afterRetry)
        XCTAssertFalse(manager.isSourceKnownUnavailableForPlayback(source.id))
        let afterRetryCalls = await calls.hosts
        XCTAssertEqual(afterRetryCalls.count, 2)
    }

    @MainActor
    func testWorkingPublicRouteKeepsSongsEligibleWhenLANIsUnreachable() async {
        var source = MusicSource(
            id: "playback-routes-\(UUID().uuidString)",
            name: "Playback Test",
            type: .navidrome
        )
        source.connectionConfiguration = SourceConnectionConfiguration(
            localEndpoint: SourceConnectionEndpoint(host: "192.168.40.5", port: 4533, useSsl: false),
            publicEndpoint: SourceConnectionEndpoint(host: "public.invalid", port: 443, useSsl: true)
        )
        let fixture = source
        let manager = SourceManager(sourcesProvider: { [fixture] })
        let unavailable = await manager.playbackSourceEndpointsAreUnavailable(
            sourceID: source.id,
            probe: { endpoint in
                if endpoint.host == "192.168.40.5" { throw URLError(.timedOut) }
            }
        )
        XCTAssertFalse(unavailable)
        XCTAssertFalse(manager.isSourceKnownUnavailableForPlayback(source.id))
    }

    @MainActor
    func testCancelledProbeDoesNotQuarantineSongs() async {
        let source = MusicSource(
            id: "playback-cancel-\(UUID().uuidString)",
            name: "Playback Test",
            type: .smb,
            host: "nas.invalid",
            port: 445
        )
        let manager = SourceManager(sourcesProvider: { [source] })
        let unavailable = await manager.playbackSourceEndpointsAreUnavailable(
            sourceID: source.id,
            probe: { _ in throw CancellationError() }
        )
        XCTAssertFalse(unavailable)
        XCTAssertFalse(manager.isSourceKnownUnavailableForPlayback(source.id))
    }
}
