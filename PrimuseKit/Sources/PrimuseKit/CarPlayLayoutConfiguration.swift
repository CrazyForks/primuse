import Foundation

public enum CarPlayLayoutPreset: String, CaseIterable, Identifiable, Sendable {
    case quickPlay, artwork, focus
    public var id: String { rawValue }
    public var titleKey: String { "carplay_preset_" + rawValue }
}

public enum CarPlayBrowseStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case list, covers, cards
    public var id: String { rawValue }
    public var titleKey: String { "carplay_style_" + rawValue }
}

public enum CarPlayHomeSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case shortcuts, playlists, albums, recentlyAdded
    public var id: String { rawValue }
    public var titleKey: String { "carplay_section_" + rawValue }
}

public struct CarPlayLayoutConfiguration: Codable, Equatable, Sendable {
    public static let storageKey = "primuse.carplay.layout.v1"
    public static let maximumShortcutCount = 12
    public static let maximumBlockCount = 12

    public var browseStyle: CarPlayBrowseStyle = .list
    public var sectionOrder: [CarPlayHomeSection] = CarPlayHomeSection.allCases
    public var hiddenSections: Set<CarPlayHomeSection> = [.albums]
    public var playsCollectionsDirectly = true
    public var opensNowPlayingOnConnect = false
    public var opensNowPlayingAfterSelection = true
    public var minimalNowPlaying = false
    public var pinnedPlaylistIDs: [String] = []
    public var pinnedFolders = "[]"
    public var customBlocks: [CarPlayLayoutBlock]?

    public init() {}

    public var folderIDs: [LibraryFolderNodeID] {
        get { HomeFolderPinStorage.decode(pinnedFolders) }
        set { pinnedFolders = HomeFolderPinStorage.encode(newValue) }
    }

    public var canAddShortcut: Bool {
        pinnedPlaylistIDs.count + folderIDs.count < Self.maximumShortcutCount
    }

    public var visibleSections: [CarPlayHomeSection] {
        Self.unique(sectionOrder + CarPlayHomeSection.allCases).filter { !hiddenSections.contains($0) }
    }

    public var blocks: [CarPlayLayoutBlock] {
        get {
            if let customBlocks {
                var seen = Set<String>()
                return Array(customBlocks.filter { seen.insert($0.id).inserted }.prefix(Self.maximumBlockCount)).map(\.normalized)
            }
            return visibleSections.map { section in
                var block = CarPlayLayoutBlock(id: "legacy." + section.rawValue,
                                               kind: CarPlayLayoutBlockKind(rawValue: section.rawValue) ?? .custom,
                                               style: browseStyle)
                block.playsImmediately = section == .shortcuts || playsCollectionsDirectly
                block.itemLimit = section == .shortcuts ? 24 : (section == .recentlyAdded ? 8 : 6)
                return block
            }
        }
        set { customBlocks = newValue.map(\.normalized) }
    }

    @discardableResult
    public mutating func moveBlock(_ id: String, before destination: String?) -> Bool {
        guard id != destination else { return false }
        var updated = blocks
        guard let index = updated.firstIndex(where: { $0.id == id }),
              destination == nil || updated.contains(where: { $0.id == destination }) else { return false }
        let block = updated.remove(at: index)
        let target = destination.flatMap { destination in updated.firstIndex { $0.id == destination } } ?? updated.count
        updated.insert(block, at: target)
        blocks = updated
        return true
    }

    @discardableResult
    public mutating func moveItem(_ id: String, from sourceID: String, to destinationID: String, before itemID: String? = nil) -> Bool {
        guard id != itemID else { return false }
        var updated = blocks
        guard let source = updated.firstIndex(where: { $0.id == sourceID }),
              let destination = updated.firstIndex(where: { $0.id == destinationID }),
              updated[destination].kind == .custom,
              source == destination || (updated[destination].items.count < 24 && !updated[destination].items.contains { $0.id == id }),
              let index = updated[source].items.firstIndex(where: { $0.id == id }),
              itemID == nil || updated[destination].items.contains(where: { $0.id == itemID }) else { return false }
        let item = updated[source].items.remove(at: index)
        let target = itemID.flatMap { id in updated[destination].items.firstIndex { $0.id == id } }
            ?? updated[destination].items.count
        updated[destination].items.insert(item, at: target)
        updated[destination].itemLimit = max(updated[destination].itemLimit, updated[destination].items.count)
        blocks = updated
        return true
    }

    public mutating func apply(_ preset: CarPlayLayoutPreset) {
        let playlists = pinnedPlaylistIDs
        let folders = pinnedFolders
        let collections = blocks.filter { $0.kind == .custom }
        self = Self()
        pinnedPlaylistIDs = playlists
        pinnedFolders = folders
        switch preset {
        case .quickPlay:
            break
        case .artwork:
            browseStyle = .cards
            hiddenSections = []
            playsCollectionsDirectly = false
        case .focus:
            hiddenSections = [.playlists, .albums, .recentlyAdded]
            opensNowPlayingOnConnect = true
            minimalNowPlaying = true
        }
        if !collections.isEmpty {
            blocks = collections.map { block in
                var updated = block
                updated.style = browseStyle
                return updated
            } + blocks
        }
    }

    public var matchingPreset: CarPlayLayoutPreset? {
        var presentation = self
        presentation.pinnedPlaylistIDs = []
        presentation.pinnedFolders = "[]"
        return CarPlayLayoutPreset.allCases.first { preset in
            var candidate = Self()
            candidate.apply(preset)
            return candidate == presentation
        }
    }

    public static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }

    public func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private enum CodingKeys: String, CodingKey {
        case browseStyle, sectionOrder, hiddenSections, playsCollectionsDirectly
        case opensNowPlayingOnConnect, opensNowPlayingAfterSelection, minimalNowPlaying
        case pinnedPlaylistIDs, pinnedFolders, customBlocks
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        browseStyle = (try? values.decode(CarPlayBrowseStyle.self, forKey: .browseStyle)) ?? browseStyle
        if let order = try? values.decode([String].self, forKey: .sectionOrder) {
            sectionOrder = Self.unique(order.compactMap(CarPlayHomeSection.init(rawValue:)) + CarPlayHomeSection.allCases)
        }
        if let hidden = try? values.decode([String].self, forKey: .hiddenSections) {
            hiddenSections = Set(hidden.compactMap(CarPlayHomeSection.init(rawValue:)))
        }
        playsCollectionsDirectly = (try? values.decode(Bool.self, forKey: .playsCollectionsDirectly)) ?? playsCollectionsDirectly
        opensNowPlayingOnConnect = (try? values.decode(Bool.self, forKey: .opensNowPlayingOnConnect)) ?? opensNowPlayingOnConnect
        opensNowPlayingAfterSelection = (try? values.decode(Bool.self, forKey: .opensNowPlayingAfterSelection)) ?? opensNowPlayingAfterSelection
        minimalNowPlaying = (try? values.decode(Bool.self, forKey: .minimalNowPlaying)) ?? minimalNowPlaying
        pinnedPlaylistIDs = Self.unique((try? values.decode([String].self, forKey: .pinnedPlaylistIDs)) ?? [])
        pinnedFolders = (try? values.decode(String.self, forKey: .pinnedFolders)) ?? pinnedFolders
        if let records = try? values.decode([BlockRecord].self, forKey: .customBlocks) {
            customBlocks = records.compactMap(\.value)
        }
    }

    private struct BlockRecord: Decodable {
        let value: CarPlayLayoutBlock?
        init(from decoder: Decoder) throws { value = try? CarPlayLayoutBlock(from: decoder) }
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }
}
