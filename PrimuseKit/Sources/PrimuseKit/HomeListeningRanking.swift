import Foundation

public enum HomeListeningPeriod: String, CaseIterable, Sendable {
    case week, month, all

    public func interval(now: Date, calendar: Calendar) -> DateInterval {
        let component: Calendar.Component = self == .week ? .weekOfYear : .month
        let start = self == .all ? Date.distantPast
            : calendar.dateInterval(of: component, for: now)?.start ?? now
        return DateInterval(start: start, end: now)
    }

    public func previousInterval(now: Date, calendar: Calendar) -> DateInterval? {
        guard self != .all else { return nil }
        let component: Calendar.Component = self == .week ? .weekOfYear : .month
        guard let current = calendar.dateInterval(of: component, for: now),
              let previous = calendar.date(byAdding: component, value: -1, to: current.start)
        else { return nil }
        return DateInterval(start: previous, end: current.start)
    }
}

public enum HomeListeningCategory: String, CaseIterable, Sendable {
    case songs, artists, albums, folders
}

public struct HomeListeningEvent: Sendable {
    public let songID: String
    public let playedAt: Date
    public let listenedSeconds: TimeInterval

    public init(songID: String, playedAt: Date, listenedSeconds: TimeInterval) {
        self.songID = songID
        self.playedAt = playedAt
        self.listenedSeconds = listenedSeconds
    }
}

public struct HomeListeningRank: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let songIDs: [String]
    public let folderID: LibraryFolderNodeID?
    public let playCount: Int
    public let listenedSeconds: TimeInterval
    public var positionsGained: Int?
}

public enum HomeListeningRanking {
    private struct GroupKey: Hashable {
        let category: HomeListeningCategory
        let components: [String]

        var id: String {
            let data = (try? JSONEncoder().encode([category.rawValue] + components)) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }
    }

    private struct Accumulator {
        var title: String
        var subtitle: String
        var folderID: LibraryFolderNodeID?
        var songIDs = Set<String>()
        var count = 0
        var seconds: TimeInterval = 0
    }

    /// Resolve against the visible library so every ranking can be played and
    /// hidden/deleted sources do not leak back into the home screen.
    public static func ranks(
        events: [HomeListeningEvent],
        songs: [String: Song],
        folders: LibraryFolderIndex?,
        period: HomeListeningPeriod,
        category: HomeListeningCategory,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [HomeListeningRank] {
        let current = aggregate(
            events: events, songs: songs, folders: folders, category: category,
            interval: period.interval(now: now, calendar: calendar), includesEnd: true
        )
        guard let interval = period.previousInterval(now: now, calendar: calendar) else {
            return current
        }
        let previous = aggregate(
            events: events, songs: songs, folders: folders, category: category,
            interval: interval, includesEnd: false
        )
        let positions = Dictionary(uniqueKeysWithValues: previous.enumerated().map { ($1.id, $0) })
        return current.enumerated().map { position, value in
            var value = value
            if let oldPosition = positions[value.id] {
                value.positionsGained = oldPosition - position
            }
            return value
        }
    }

    private static func aggregate(
        events: [HomeListeningEvent], songs: [String: Song], folders: LibraryFolderIndex?,
        category: HomeListeningCategory, interval: DateInterval, includesEnd: Bool
    ) -> [HomeListeningRank] {
        var groups: [GroupKey: Accumulator] = [:]
        for event in events {
            guard event.playedAt >= interval.start,
                  includesEnd ? event.playedAt <= interval.end : event.playedAt < interval.end,
                  let song = songs[event.songID] else { continue }
            let components: [String]
            let title: String
            let subtitle: String
            var folderID: LibraryFolderNodeID?
            switch category {
            case .songs:
                components = [song.id]
                title = song.title
                subtitle = song.artistName ?? ""
            case .artists:
                guard let name = song.artistName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                components = [name]
                title = name
                subtitle = ""
            case .albums:
                guard let name = song.albumTitle, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                components = [name, song.artistName ?? ""]
                title = name
                subtitle = song.artistName ?? ""
            case .folders:
                // One play belongs to its containing directory, not every
                // ancestor. This keeps nested-folder totals comparable.
                guard let folders, let id = folders.nodeID(containingSongID: song.id),
                      let node = folders.node(withID: id),
                      node.kind == .folder || node.kind == .scanRoot else { continue }
                components = [id.sourceID, id.kind.rawValue, id.normalizedRelativePath]
                title = node.displayName ?? ""
                subtitle = folders.sourceNode(for: id.sourceID)?.displayName ?? ""
                folderID = id
            }
            let key = GroupKey(category: category, components: components)
            var group = groups[key] ?? Accumulator(title: title, subtitle: subtitle, folderID: folderID)
            group.songIDs.insert(song.id)
            group.count += 1
            if event.listenedSeconds.isFinite { group.seconds += max(0, event.listenedSeconds) }
            groups[key] = group
        }
        return groups.map { key, value in
            HomeListeningRank(
                id: key.id, title: value.title, subtitle: value.subtitle,
                songIDs: value.songIDs.sorted(), folderID: value.folderID,
                playCount: value.count, listenedSeconds: value.seconds, positionsGained: nil
            )
        }.sorted {
            if $0.playCount != $1.playCount { return $0.playCount > $1.playCount }
            if $0.listenedSeconds != $1.listenedSeconds { return $0.listenedSeconds > $1.listenedSeconds }
            return $0.id < $1.id
        }
    }
}

public enum HomeFolderPinStorage {
    public static let key = "primuse.home.folders.v1"

    private struct Record: Codable {
        let sourceID: String
        let kind: String
        let path: String
    }

    public static func decode(_ value: String) -> [LibraryFolderNodeID] {
        guard let data = value.data(using: .utf8),
              let records = try? JSONDecoder().decode([Record].self, from: data) else { return [] }
        var seen = Set<LibraryFolderNodeID>()
        return records.compactMap { record in
            guard let kind = LibraryFolderNodeKind(rawValue: record.kind) else { return nil }
            let id = LibraryFolderNodeID(sourceID: record.sourceID, kind: kind, normalizedRelativePath: record.path)
            return seen.insert(id).inserted ? id : nil
        }
    }

    public static func encode(_ ids: [LibraryFolderNodeID]) -> String {
        let records = ids.map { Record(sourceID: $0.sourceID, kind: $0.kind.rawValue, path: $0.normalizedRelativePath) }
        guard let data = try? JSONEncoder().encode(records) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}
