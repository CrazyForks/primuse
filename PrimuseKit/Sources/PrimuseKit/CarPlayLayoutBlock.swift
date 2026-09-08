import Foundation

public enum CarPlayLayoutBlockKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case shortcuts, playlists, albums, recentlyAdded, custom, radio
    public var id: String { rawValue }
    public var titleKey: String {
        switch self {
        case .custom: "carplay_block_custom"
        case .radio: "radio_title"
        default: "carplay_section_" + rawValue
        }
    }
    public var symbol: String {
        switch self {
        case .shortcuts: "pin"
        case .playlists: "music.note.list"
        case .albums: "square.stack"
        case .recentlyAdded: "clock"
        case .custom: "square.grid.2x2"
        case .radio: "radio"
        }
    }
}

public struct CarPlayLayoutItem: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case playlist, folder, album, song, radio
        public var id: String { rawValue }
    }
    public var id: String
    public var kind: Kind
    public var targetID: String
    public var title: String

    public init(id: String = UUID().uuidString, kind: Kind, targetID: String, title: String) {
        self.id = id
        self.kind = kind
        self.targetID = targetID
        self.title = title
    }

    public var folderID: LibraryFolderNodeID? {
        guard kind == .folder else { return nil }
        return HomeFolderPinStorage.decode(targetID).first
    }

    public var dragValue: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return "carplay-content:" + data.base64EncodedString()
    }

    public static func fromDragValue(_ value: String) -> Self? {
        let prefix = "carplay-content:"
        guard value.hasPrefix(prefix), value.utf8.count < 16_384,
              let data = Data(base64Encoded: String(value.dropFirst(prefix.count))),
              let item = try? JSONDecoder().decode(Self.self, from: data),
              !item.targetID.isEmpty, item.title.count <= 512 else { return nil }
        return item
    }
}

public struct CarPlayLayoutBlock: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: CarPlayLayoutBlockKind
    public var title = ""
    public var style: CarPlayBrowseStyle
    public var columns = 3
    public var itemLimit = 6
    public var showsTitle = true
    public var playsImmediately = true
    public var items: [CarPlayLayoutItem] = []

    public init(id: String = UUID().uuidString, kind: CarPlayLayoutBlockKind, style: CarPlayBrowseStyle = .covers) {
        self.id = id
        self.kind = kind
        self.style = style
    }

    public var normalized: Self {
        var result = self
        result.columns = min(6, max(2, columns))
        result.itemLimit = min(24, max(1, itemLimit))
        result.title = String(title.prefix(80))
        var seen = Set<String>()
        result.items = Array(items.filter { !$0.targetID.isEmpty && seen.insert($0.id).inserted }.prefix(24))
        return result
    }
}

public struct CarPlaySavedLayout: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var configuration: CarPlayLayoutConfiguration

    public init(id: String = UUID().uuidString, name: String, configuration: CarPlayLayoutConfiguration) {
        self.id = id
        self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        self.configuration = configuration
    }
}

public struct CarPlayLayoutHistory {
    private var previous: [CarPlayLayoutConfiguration] = []
    private var following: [CarPlayLayoutConfiguration] = []
    public init() {}
    public var canUndo: Bool { !previous.isEmpty }
    public var canRedo: Bool { !following.isEmpty }

    public mutating func record(_ old: CarPlayLayoutConfiguration, replacing new: CarPlayLayoutConfiguration) {
        guard old != new else { return }
        previous.append(old)
        previous = Array(previous.suffix(30))
        following.removeAll()
    }

    public mutating func undo(_ current: CarPlayLayoutConfiguration) -> CarPlayLayoutConfiguration? {
        guard let result = previous.popLast() else { return nil }
        following.append(current)
        return result
    }

    public mutating func redo(_ current: CarPlayLayoutConfiguration) -> CarPlayLayoutConfiguration? {
        guard let result = following.popLast() else { return nil }
        previous.append(current)
        return result
    }
}
