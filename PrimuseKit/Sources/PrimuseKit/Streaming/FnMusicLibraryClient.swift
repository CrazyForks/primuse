import CoreFoundation
import Foundation

private protocol FnMusicLibraryItem: Sendable { var id: String { get } }

public struct FnMusicLibraryRequest: Sendable {
    public let method: String
    public let path: String
    public let queryItems: [URLQueryItem]
    public let body: [String: String]?
}

public struct FnMusicPlaylist: Sendable {
    public let id: String
    public let name: String
    public let coverReference: String?
    public let trackIDs: [String]
}

public struct FnMusicPlaylistSnapshot: Sendable {
    public let playlists: [FnMusicPlaylist]
    public let failedPlaylistIDs: Set<String>
}

/// Uses each platform's existing authenticated session. Only complete pages
/// may become authoritative mirrors or replace a user's favorite state.
public struct FnMusicLibraryClient: Sendable {
    private let load: @Sendable (FnMusicLibraryRequest) async throws -> Data
    private static let pageSize = 50

    public init(load: @escaping @Sendable (FnMusicLibraryRequest) async throws -> Data) {
        self.load = load
    }

    public func playlists() async throws -> FnMusicPlaylistSnapshot {
        let summaries: [Summary] = try await pages(path: "/playlist/list", parse: Summary.init)
        var playlists: [FnMusicPlaylist] = []
        var failed: Set<String> = []
        for summary in summaries {
            try Task.checkCancellation()
            do {
                let tracks: [Track] = try await pages(
                    path: "/track/playlist-detail/list",
                    query: [URLQueryItem(name: "playlistGUID", value: summary.id)],
                    expectedTotal: summary.trackCount,
                    allowsDuplicates: true,
                    parse: Track.init
                )
                playlists.append(FnMusicPlaylist(
                    id: summary.id, name: summary.name,
                    coverReference: summary.coverReference, trackIDs: tracks.map(\.id)
                ))
            } catch {
                if OperationCancellationPolicy.isCancellation(error) { throw CancellationError() }
                failed.insert(summary.id)
            }
        }
        return FnMusicPlaylistSnapshot(playlists: playlists, failedPlaylistIDs: failed)
    }

    public func favorites() async throws -> [String] {
        let tracks: [Track] = try await pages(path: "/favorite-track/list", parse: Track.init)
        return tracks.map(\.id)
    }

    public func setFavorite(trackID: String, isFavorite: Bool) async throws -> [String] {
        guard Self.validID(trackID) else { throw Self.invalidResponse() }
        let existing = try await favorites()
        if existing.contains(trackID) != isFavorite {
            try Task.checkCancellation()
            _ = try await load(FnMusicLibraryRequest(
                method: "POST",
                path: isFavorite ? "/favorite-track/create" : "/favorite-track/delete",
                queryItems: [], body: ["trackGUID": trackID]
            ))
        }
        let confirmed = try await favorites()
        guard confirmed.contains(trackID) == isFavorite else { throw Self.invalidResponse() }
        return confirmed
    }

    private func pages<Item: FnMusicLibraryItem>(
        path: String,
        query: [URLQueryItem] = [],
        expectedTotal: Int? = nil,
        allowsDuplicates: Bool = false,
        parse: ([String: Any]) throws -> Item
    ) async throws -> [Item] {
        var page = 1
        var total = expectedTotal
        var result: [Item] = []
        var seen: Set<String> = []
        while true {
            try Task.checkCancellation()
            let data = try await load(FnMusicLibraryRequest(
                method: "GET", path: path,
                queryItems: query + [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "size", value: String(Self.pageSize)),
                ], body: nil
            ))
            try Task.checkCancellation()
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = object["list"] as? [[String: Any]],
                  let pageTotal = Self.integer(object["total"]), pageTotal >= 0,
                  list.count <= Self.pageSize,
                  total == nil || total == pageTotal else { throw Self.invalidResponse() }
            total = pageTotal
            for json in list {
                let item = try parse(json)
                guard allowsDuplicates || seen.insert(item.id).inserted else { throw Self.invalidResponse() }
                result.append(item)
            }
            guard result.count <= pageTotal else { throw Self.invalidResponse() }
            if result.count == pageTotal { return result }
            guard list.count == Self.pageSize else { throw Self.invalidResponse() }
            page += 1
        }
    }

    private struct Track: FnMusicLibraryItem {
        let id: String
        init(_ json: [String: Any]) throws {
            guard let id = FnMusicLibraryClient.identifier(json["guid"] ?? json["trackGUID"] ?? json["id"]) else {
                throw FnMusicLibraryClient.invalidResponse()
            }
            self.id = id
        }
    }

    private struct Summary: FnMusicLibraryItem {
        let id: String
        let name: String
        let coverReference: String?
        let trackCount: Int?

        init(_ json: [String: Any]) throws {
            guard let id = FnMusicLibraryClient.identifier(json["guid"]),
                  let name = json["name"] as? String,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw FnMusicLibraryClient.invalidResponse()
            }
            self.id = id
            self.name = name
            trackCount = FnMusicLibraryClient.integer(json["trackCount"])
            if let trackCount, trackCount < 0 { throw FnMusicLibraryClient.invalidResponse() }
            if let rawCount = json["trackCount"], !(rawCount is NSNull), trackCount == nil {
                throw FnMusicLibraryClient.invalidResponse()
            }
            coverReference = FnMusicLibraryClient.identifier(json["coverId"]).map {
                FnMusicAPIProtocol.coverReference(coverID: $0, revision: FnMusicLibraryClient.integer(json["updatedAt"]))
            }
        }
    }

    private static func identifier(_ value: Any?) -> String? {
        guard let value = value as? String, validID(value) else { return nil }
        return value
    }

    private static func validID(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".."
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.contains("/")
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? String { return Int(value) }
        if let value = value as? NSNumber,
           CFGetTypeID(value) != CFBooleanGetTypeID(),
           value.doubleValue == Double(value.intValue) { return value.intValue }
        return nil
    }

    private static func invalidResponse() -> FnMusicServiceError {
        .invalidResponse(PMString("error.catalog.invalidFnMusicJSON"))
    }
}
