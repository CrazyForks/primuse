import Foundation
import Testing
@testable import PrimuseKit

struct HomeListeningRankingTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ day: Int, month: Int = 9, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func song(_ id: String, artist: String = "Artist", album: String = "Album", path: String? = nil, source: String = "nas") -> Song {
        Song(id: id, title: id, albumTitle: album, artistName: artist, fileFormat: .mp3,
             filePath: path ?? "/Music/Pop/\(id).mp3", sourceID: source)
    }

    private func event(_ song: String, day: Int, month: Int = 9, seconds: Double = 180) -> HomeListeningEvent {
        HomeListeningEvent(songID: song, playedAt: date(day, month: month), listenedSeconds: seconds)
    }

    @Test func periodsUseCalendarBoundariesAndExcludeFutureEvents() {
        let events = [event("a", day: 30, month: 8), event("a", day: 31, month: 8), event("a", day: 1), event("a", day: 6)]
        let songs = ["a": song("a")]
        let week = HomeListeningRanking.ranks(events: events, songs: songs, folders: nil, period: .week, category: .songs, now: date(5), calendar: calendar)
        let month = HomeListeningRanking.ranks(events: events, songs: songs, folders: nil, period: .month, category: .songs, now: date(5), calendar: calendar)
        #expect(week.first?.playCount == 2)
        #expect(month.first?.playCount == 1)
    }

    @Test func comparisonsUsePreviousPeriodWithoutInventingRankForNewEntries() {
        let events = [event("a", day: 28, month: 8), event("a", day: 29, month: 8), event("b", day: 30, month: 8),
                      event("b", day: 1), event("b", day: 2), event("b", day: 3), event("c", day: 4), event("a", day: 4)]
        let songs = Dictionary(uniqueKeysWithValues: ["a", "b", "c"].map { ($0, song($0)) })
        let ranks = HomeListeningRanking.ranks(events: events, songs: songs, folders: nil, period: .week, category: .songs, now: date(5), calendar: calendar)
        #expect(ranks.first?.title == "b")
        #expect(ranks.first?.positionsGained == 1)
        #expect(ranks.first { $0.title == "c" }?.positionsGained == nil)
        let all = HomeListeningRanking.ranks(events: events, songs: songs, folders: nil, period: .all, category: .songs, now: date(5), calendar: calendar)
        #expect(all.allSatisfy { $0.positionsGained == nil })
    }

    @Test func tiesAreStableRegardlessOfInputOrderAndAlbumKeysDoNotCollide() {
        let songs = ["a": song("a", artist: "b|c", album: "a"), "b": song("b", artist: "c", album: "a|b")]
        let events = [event("b", day: 1), event("a", day: 2)]
        let first = HomeListeningRanking.ranks(events: events, songs: songs, folders: nil, period: .all, category: .albums, now: date(5), calendar: calendar)
        let reversed = HomeListeningRanking.ranks(events: events.reversed(), songs: songs, folders: nil, period: .all, category: .albums, now: date(5), calendar: calendar)
        #expect(first.count == 2)
        #expect(first.map(\.id) == reversed.map(\.id))
    }

    @Test func unavailableSongsAndEmptyMetadataAreExcluded() {
        let songs = ["a": song("a", artist: "", album: "")]
        let events = [event("a", day: 1), event("removed", day: 2)]
        let songsRank = HomeListeningRanking.ranks(events: events, songs: songs, folders: nil, period: .week, category: .songs, now: date(5), calendar: calendar)
        let artists = HomeListeningRanking.ranks(events: events, songs: songs, folders: nil, period: .week, category: .artists, now: date(5), calendar: calendar)
        #expect(songsRank.count == 1)
        #expect(artists.isEmpty)
    }

    @Test func nestedFoldersCountEachPlayOnceAndKeepSourcesSeparate() throws {
        let songs = [song("a", path: "/Music/Pop/Live/a.mp3"), song("b", path: "/Music/Pop/Live/b.mp3", source: "other")]
        let sources = ["nas", "other"].map {
            LibraryFolderSourceDescriptor(sourceID: $0, displayName: "NAS", scanRoots: ["/Music"], pathSemantics: .hierarchical)
        }
        let index = LibraryFolderIndexBuilder.build(sources: sources, songs: songs)
        let ranks = HomeListeningRanking.ranks(events: [event("a", day: 1), event("b", day: 2)],
                                              songs: Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) }), folders: index,
                                              period: .all, category: .folders, now: date(5), calendar: calendar)
        #expect(ranks.count == 2)
        #expect(ranks.reduce(0) { $0 + $1.playCount } == 2)
        #expect(ranks.allSatisfy { $0.title == "Live" })
        #expect(Set(ranks.compactMap(\.folderID).map(\.sourceID)) == Set(["nas", "other"]))
    }

    @Test func folderPinsResolveLiveMembershipAfterRescanAndSourceRestoration() throws {
        let source = LibraryFolderSourceDescriptor(sourceID: "nas", displayName: "NAS", scanRoots: ["/Music"], pathSemantics: .hierarchical)
        let first = LibraryFolderIndexBuilder.build(sources: [source], songs: [song("a")])
        let id = try #require(first.nodeID(containingSongID: "a"))
        let encoded = HomeFolderPinStorage.encode([id, id])
        let pins = HomeFolderPinStorage.decode(encoded)
        #expect(pins == [id])
        let rescanned = LibraryFolderIndexBuilder.build(sources: [source], songs: [song("a"), song("b")])
        #expect(Set(rescanned.songIDs(in: pins[0], scope: .descendants)) == Set(["a", "b"]))
        let disabled = LibraryFolderSourceDescriptor(sourceID: "nas", displayName: "NAS", scanRoots: ["/Music"], pathSemantics: .hierarchical, isEnabled: false)
        #expect(LibraryFolderIndexBuilder.build(sources: [disabled], songs: [song("a")]).node(withID: pins[0]) == nil)
        #expect(HomeFolderPinStorage.decode(encoded) == pins)
        #expect(rescanned.node(withID: pins[0]) != nil)
    }

    @Test func pinsRoundTripSpecialCharactersAndKeepAnExplicitEmptySelection() {
        let ids = [LibraryFolderNodeID(sourceID: "source:1", kind: .folder, normalizedRelativePath: "/音乐/a|b/\"Live\""),
                   LibraryFolderNodeID(sourceID: "source:2", kind: .folder, normalizedRelativePath: "/音乐/a|b/\"Live\"")]
        #expect(HomeFolderPinStorage.decode(HomeFolderPinStorage.encode(ids)) == ids)
        #expect(HomeFolderPinStorage.encode([]) == "[]")
        #expect(HomeFolderPinStorage.decode("invalid").isEmpty)
    }
}
