#if os(iOS)
import CarPlay
import ImageIO
import UIKit
import PrimuseKit

enum CarPlayContentArtwork: Sendable {
    case song(Song), album(Album), playlist(Playlist)
}

struct CarPlayHomeItem: Identifiable, Sendable {
    enum Target: Sendable {
        case nowPlaying
        case song(String, queue: [String])
        case playlist(String, directly: Bool)
        case album(String, directly: Bool)
        case folder(LibraryFolderNodeID, directly: Bool)
        case radio(String)
        case unavailable
    }
    let id: String
    let title: String
    var subtitle: String? = nil
    var symbol = "music.note"
    var artwork: CarPlayContentArtwork? = nil
    var enabled = true
    let target: Target
}

struct CarPlayHomeBlock: Identifiable {
    let configuration: CarPlayLayoutBlock
    var items: [CarPlayHomeItem]
    var id: String { configuration.id }
    var title: String {
        configuration.title.isEmpty ? NSLocalizedString(configuration.kind.titleKey, comment: "") : configuration.title
    }
}

/// Both the editor and the CarPlay templates resolve the same identities and
/// apply the same grouping budget; previewing never starts audio playback.
@MainActor
enum CarPlayHomeContent {
    static func resolve(_ configuration: CarPlayLayoutConfiguration) -> [CarPlayHomeBlock] {
        let library = AppServices.shared.musicLibrary
        let folders = CarPlayFolderLibrary.shared
        let player = AppServices.shared.playerService
        let blocks = configuration.blocks
        let playlists = library.playlists.sorted { $0.updatedAt > $1.updatedAt }
        let albums = blocks.contains { $0.kind == .albums }
            ? library.visibleAlbums.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } : []
        let recent = blocks.contains { $0.kind == .recentlyAdded }
            ? Array(library.visibleSongs.sorted { $0.dateAdded > $1.dateAdded }.prefix(100)) : []
        var remainingRows = max(1, CPListTemplate.maximumItemCount - 3)
        var remainingSections = max(1, CPListTemplate.maximumSectionCount - 1)
        return blocks.map { block in
            var items: [CarPlayHomeItem]
            switch block.kind {
            case .custom:
                items = block.items.map { resolve($0, directly: block.playsImmediately) }
            case .playlists:
                items = playlists.prefix(block.itemLimit).map { playlist($0, directly: block.playsImmediately) }
            case .albums:
                items = albums.prefix(block.itemLimit).map { album($0, directly: block.playsImmediately) }
            case .recentlyAdded:
                let queue = recent.map(\.id)
                items = recent.prefix(block.itemLimit).map { song($0, queue: queue) }
            case .radio:
                items = AppServices.shared.radioStationsStore.stations.prefix(block.itemLimit).map {
                    CarPlayHomeItem(id: $0.id, title: $0.name, subtitle: $0.playbackSubtitle,
                                    symbol: "radio", target: .radio($0.id))
                }
            case .shortcuts:
                items = []
                if player.currentSong != nil || player.currentRadioStation != nil {
                    items.append(CarPlayHomeItem(id: "nowPlaying", title: String(localized: "carplay_now_playing"),
                                                 subtitle: player.currentSong?.title ?? player.currentRadioStation?.name,
                                                 symbol: "play.circle", artwork: player.currentSong.map(CarPlayContentArtwork.song),
                                                 target: .nowPlaying))
                }
                let ids = [MusicLibrary.likedSongsPlaylistID] + configuration.pinnedPlaylistIDs.filter { $0 != MusicLibrary.likedSongsPlaylistID }
                items += ids.compactMap { id in playlists.first { $0.id == id }.map { playlist($0, directly: block.playsImmediately) } }
                items += configuration.folderIDs.compactMap { id in
                    guard let node = folders.index?.node(withID: id) else { return nil }
                    return folder(node, directly: block.playsImmediately)
                }
            }
            let columns = block.style == .list ? 1 : rowSize(for: block)
            let available = remainingSections > 0 ? remainingRows * columns : 0
            items = Array(items.prefix(min(block.itemLimit, available)))
            if !items.isEmpty {
                remainingRows -= (items.count + columns - 1) / columns
                remainingSections -= 1
            }
            return CarPlayHomeBlock(configuration: block, items: items)
        }
    }

    static func rowSize(for block: CarPlayLayoutBlock) -> Int {
        max(1, min(Int(CPMaximumNumberOfGridImages), block.normalized.columns))
    }

    static func resolve(_ item: CarPlayLayoutItem, directly: Bool) -> CarPlayHomeItem {
        let library = AppServices.shared.musicLibrary
        var resolved: CarPlayHomeItem?
        switch item.kind {
        case .playlist:
            resolved = library.playlists.first { $0.id == item.targetID }.map { playlist($0, directly: directly) }
        case .album:
            resolved = library.visibleAlbums.first { $0.id == item.targetID }.map { album($0, directly: directly) }
        case .song:
            resolved = library.unobservedVisibleSong(id: item.targetID).map { song($0, queue: [$0.id]) }
        case .folder:
            resolved = item.folderID.flatMap { CarPlayFolderLibrary.shared.index?.node(withID: $0) }.map { folder($0, directly: directly) }
        case .radio:
            resolved = AppServices.shared.radioStationsStore.station(id: item.targetID).map {
                CarPlayHomeItem(id: item.id, title: $0.name, subtitle: $0.playbackSubtitle, symbol: "radio", target: .radio($0.id))
            }
        }
        guard let resolved else {
            return CarPlayHomeItem(id: item.id, title: item.title, subtitle: String(localized: "carplay_content_unavailable"),
                                   symbol: "exclamationmark.circle", enabled: false, target: .unavailable)
        }
        return CarPlayHomeItem(id: item.id, title: resolved.title, subtitle: resolved.subtitle,
                               symbol: resolved.symbol, artwork: resolved.artwork, enabled: resolved.enabled, target: resolved.target)
    }

    static func songs(for target: CarPlayHomeItem.Target) -> [Song] {
        let library = AppServices.shared.musicLibrary
        switch target {
        case .song(_, let queue): return queue.compactMap { library.unobservedVisibleSong(id: $0) }
        case .playlist(let id, _): return library.songs(forPlaylist: id)
        case .album(let id, _):
            return library.songs(forAlbum: id).sorted {
                ($0.discNumber ?? 0, $0.trackNumber ?? 0) < ($1.discNumber ?? 0, $1.trackNumber ?? 0)
            }
        case .folder(let id, _): return CarPlayFolderLibrary.shared.songs(in: id)
        case .nowPlaying: return AppServices.shared.playerService.currentSong.map { [$0] } ?? []
        case .radio, .unavailable: return []
        }
    }

    static func artwork(_ artwork: CarPlayContentArtwork, pixelSize: Int) async -> UIImage? {
        let library = AppServices.shared.musicLibrary
        let songs: [Song]
        let owner: LibraryArtworkOwner
        switch artwork {
        case .song(let song):
            return await CarPlayArtworkDecoder.shared.thumbnail(forSongID: song.id, coverRef: song.coverArtFileName, maximumPixelSize: pixelSize)
        case .album(let album):
            songs = library.songs(forAlbum: album.id)
            owner = LibraryArtworkOwner(kind: .album, id: album.id)
        case .playlist(let playlist):
            songs = library.songs(forPlaylist: playlist.id)
            owner = LibraryArtworkOwner(kind: .playlist, id: playlist.id)
        }
        let resolution = library.artworkOverrideResolution(for: owner, eligibleSongs: songs)
        switch resolution {
        case .uploaded(let contentID):
            return await Task.detached(priority: .utility) {
                guard let data = MetadataAssetStore.shared.customArtworkData(contentID: contentID),
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: pixelSize
                      ] as CFDictionary) else { return nil as UIImage? }
                return UIImage(cgImage: image)
            }.value
        case .selectedSong(let id):
            guard let song = songs.first(where: { $0.id == id }) else { return nil }
            return await CarPlayArtworkDecoder.shared.thumbnail(forSongID: song.id, coverRef: song.coverArtFileName, maximumPixelSize: pixelSize)
        case .automatic:
            if case .playlist(let playlist) = artwork {
                let candidates = Array(songs.prefix(12))
                let plan = PlaylistArtworkResolutionPolicy.makePlan(playlist: playlist, songs: candidates)
                let result = await PlaylistArtworkResourceResolver.resolve(
                    playlist: playlist, plan: plan, songs: candidates, size: CGFloat(pixelSize),
                    sourceManager: AppServices.shared.sourceManager, allowsMusicKitArtwork: false,
                    cacheDiscriminator: "carplay:\(playlist.updatedAt.timeIntervalSinceReferenceDate)"
                )
                if case .image(let image) = result?.value { return image }
            }
            guard let song = songs.first(where: { $0.coverArtFileName != nil }) ?? songs.first else { return nil }
            return await CarPlayArtworkDecoder.shared.thumbnail(forSongID: song.id, coverRef: song.coverArtFileName, maximumPixelSize: pixelSize)
        }
    }

    private static func playlist(_ playlist: Playlist, directly: Bool) -> CarPlayHomeItem {
        let summary = AppServices.shared.musicLibrary.songSummary(forPlaylist: playlist.id)
        return CarPlayHomeItem(id: playlist.id, title: playlist.name, subtitle: count(summary.count),
                               symbol: playlist.id == MusicLibrary.likedSongsPlaylistID ? "heart.fill" : "music.note.list",
                               artwork: .playlist(playlist), enabled: summary.count > 0 || !directly,
                               target: .playlist(playlist.id, directly: directly))
    }

    private static func album(_ album: Album, directly: Bool) -> CarPlayHomeItem {
        CarPlayHomeItem(id: album.id, title: album.title, subtitle: album.artistName, symbol: "square.stack",
                        artwork: .album(album), target: .album(album.id, directly: directly))
    }

    private static func song(_ song: Song, queue: [String]) -> CarPlayHomeItem {
        CarPlayHomeItem(id: song.id, title: song.title, subtitle: AppServices.shared.musicLibrary.artistDisplayName(for: song),
                        artwork: .song(song), target: .song(song.id, queue: queue))
    }

    private static func folder(_ node: LibraryFolderNode, directly: Bool) -> CarPlayHomeItem {
        CarPlayHomeItem(id: HomeFolderPinStorage.encode([node.id]), title: HomeDiscoveryText.folderTitle(node),
                        subtitle: count(node.descendantSongCount), symbol: "folder.fill",
                        enabled: node.descendantSongCount > 0 || !directly, target: .folder(node.id, directly: directly))
    }

    private static func count(_ count: Int) -> String {
        String(format: String(localized: "carplay_playlist_song_count_format"), count)
    }
}
#endif
