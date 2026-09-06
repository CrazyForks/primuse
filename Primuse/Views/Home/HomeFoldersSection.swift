import SwiftUI
import PrimuseKit

struct HomeFoldersSection: View {
    @Environment(HomeDiscoveryModel.self) private var model
    @AppStorage(HomeFolderPinStorage.key) private var pinsRawValue = ""
    @AppStorage(HomeFolderPinStorage.displayCountKey) private var displayCount = HomeFolderPinStorage.defaultDisplayCount

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(HomeDiscoveryText.string("folders"))
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                NavigationLink {
                    HomeFolderBrowser()
                } label: {
                    HStack(spacing: 5) {
                        Text("see_all")
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("home.allFolders")
            }

            if model.index == nil {
                ProgressView().frame(maxWidth: .infinity).padding()
            } else {
                let nodes = model.pins(from: pinsRawValue).compactMap { model.index?.node(withID: $0) }
                ForEach(Array(nodes.prefix(HomeFolderPinStorage.displayCount(displayCount)))) { node in
                    HomeFolderRow(node: node)
                    Divider().padding(.leading, 68)
                }
                if nodes.isEmpty {
                    Text(HomeDiscoveryText.string("no_pinned_folders"))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

struct HomeFolderManagementView: View {
    var usesInlineControls = false
    @State private var model = HomeDiscoveryModel()
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif

    var body: some View {
        HomeFolderBrowser(usesInlineControls: usesInlineControls)
            .environment(model)
            .background { HomeDiscoveryObserver(model: model) }
            #if os(iOS)
            .environment(\.editMode, $editMode)
            #endif
    }
}

struct HomeFolderArtwork: View {
    let node: LibraryFolderNode
    var size: CGFloat = 54
    @Environment(HomeDiscoveryModel.self) private var model

    var body: some View {
        let _ = model.revision
        let songs = (model.folderCoverSongIDs[node.id] ?? []).compactMap { model.songsByID[$0] }
        Group {
            if songs.count >= 4 {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow { artwork(songs[0], size: size / 2); artwork(songs[1], size: size / 2) }
                    GridRow { artwork(songs[2], size: size / 2); artwork(songs[3], size: size / 2) }
                }
            } else if let song = songs.first {
                artwork(song, size: size)
            } else {
                Image(systemName: "folder.fill")
                    .font(.system(size: size * 0.38))
                    .foregroundStyle(.tint)
                    .frame(width: size, height: size)
                    .background(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .accessibilityHidden(true)
    }

    private func artwork(_ song: Song, size: CGFloat) -> some View {
        CachedArtworkView(
            coverRef: song.coverArtFileName, songID: song.id, size: size, cornerRadius: 0,
            sourceID: song.sourceID, filePath: song.filePath, fileFormat: song.fileFormat
        )
    }
}

private struct HomeFolderRow: View {
    let node: LibraryFolderNode
    @Environment(HomeDiscoveryModel.self) private var model
    @Environment(MusicLibrary.self) private var library
    @Environment(AudioPlayerService.self) private var player
    @AppStorage(HomeFolderPinStorage.key) private var pinsRawValue = ""

    var body: some View {
        let _ = model.revision
        HStack(spacing: 8) {
            NavigationLink {
                HomeFolderBrowser(nodeID: node.id)
                    .environment(model)
            } label: {
                HStack(spacing: 14) {
                    HomeFolderArtwork(node: node)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill").font(.caption).foregroundStyle(.tint)
                            Text(HomeDiscoveryText.folderTitle(node))
                                .font(.headline).lineLimit(1).foregroundStyle(.primary)
                        }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 6) { sourceBadge; songCount }
                            VStack(alignment: .leading, spacing: 3) { sourceBadge; songCount }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { play(shuffle: false) } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 25))
                    .frame(width: 44, height: 54)
            }
            .buttonStyle(.plain).foregroundStyle(.tint)
            .disabled(node.descendantSongCount == 0)
            .accessibilityLabel(String(localized: "play") + " · " + HomeDiscoveryText.folderTitle(node))
        }
        .contextMenu {
            Button("play", systemImage: "play.fill") { play(shuffle: false) }
            Button("shuffle", systemImage: "shuffle") { play(shuffle: true) }
            Button(HomeDiscoveryText.string("unpin_folder"), systemImage: "pin.slash") {
                pinsRawValue = HomeFolderPinStorage.encode(model.pins(from: pinsRawValue).filter { $0 != node.id })
            }
        }
    }

    private var sourceBadge: some View {
        Text(model.index?.sourceNode(for: node.sourceID)?.displayName ?? String(localized: "source_label"))
            .font(.caption2.weight(.medium)).lineLimit(1)
            .foregroundStyle(.tint)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
    }

    private var songCount: some View {
        let counts = node.childNodeCount > 0
            ? String(format: HomeDiscoveryText.string("folder_counts"), node.childNodeCount, node.descendantSongCount)
            : "\(node.descendantSongCount.formatted()) \(String(localized: "songs_count"))"
        let lastPlayed = node.childNodeCount == 0 ? model.lastPlayedByFolder[node.id] : nil
        let suffix = lastPlayed.map { " · " + $0.formatted(.relative(presentation: .named)) } ?? ""
        return Text(counts + suffix)
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }

    private func play(shuffle: Bool) {
        HomeDiscoveryPlayback.play(
            ids: model.songs(in: node.id).map(\.id), shuffle: shuffle,
            library: library, player: player
        )
    }
}

struct HomeFolderBrowser: View {
    var nodeID: LibraryFolderNodeID?
    var usesInlineControls = false
    #if os(iOS)
    @Environment(\.appNavigationMode) private var appNavigationMode
    @Environment(\.editMode) private var editMode
    #endif
    @Environment(HomeDiscoveryModel.self) private var model
    @Environment(MusicLibrary.self) private var library
    @Environment(AudioPlayerService.self) private var player
    @AppStorage(HomeFolderPinStorage.key) private var pinsRawValue = ""

    private var node: LibraryFolderNode? { nodeID.flatMap { model.index?.node(withID: $0) } }
    private var pins: [LibraryFolderNodeID] { model.pins(from: pinsRawValue) }
    private var children: [LibraryFolderNode] {
        if let nodeID { return model.index?.children(of: nodeID) ?? [] }
        return model.index?.sourceNodes ?? []
    }

    private var legacyBottomClearance: CGFloat {
        #if os(iOS)
        appNavigationMode == .minimal ? 0 : 90
        #else
        90
        #endif
    }

    var body: some View {
        List {
            if nodeID == nil, !pins.isEmpty {
                Section {
                    ForEach(pins, id: \.self) { id in
                        if let node = model.index?.node(withID: id) {
                            HomeFolderRow(node: node)
                        } else {
                            Label(HomeDiscoveryText.string("folder_unavailable"), systemImage: "folder.badge.questionmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onMove { from, to in
                        var updated = pins
                        updated.move(fromOffsets: from, toOffset: to)
                        pinsRawValue = HomeFolderPinStorage.encode(updated)
                    }
                    .onDelete { offsets in
                        var updated = pins
                        updated.remove(atOffsets: offsets)
                        pinsRawValue = HomeFolderPinStorage.encode(updated)
                        #if os(iOS)
                        if usesInlineControls, updated.isEmpty {
                            editMode?.wrappedValue = .inactive
                        }
                        #endif
                    }
                } header: {
                    HStack {
                        Text(HomeDiscoveryText.string("pinned_folders"))
                        #if os(iOS)
                        if usesInlineControls {
                            Spacer()
                            EditButton()
                                .font(.subheadline)
                                .textCase(nil)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("minimal.folders.edit")
                        }
                        #endif
                    }
                }
            }

            if !children.isEmpty {
                Section(nodeID == nil ? String(localized: "sources_title") : HomeDiscoveryText.string("folders")) {
                    ForEach(children) { child in
                        childRow(child)
                    }
                }
            }

            if let nodeID {
                let ids = model.index?.directSongIDs(in: nodeID) ?? []
                if !ids.isEmpty {
                    Section("tab_songs") {
                        ForEach(ids, id: \.self) { id in
                            if let song = library.unobservedVisibleSong(id: id) {
                                SongRowView(song: song, isPlaying: player.currentSong?.id == id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        HomeDiscoveryPlayback.play(ids: ids, startingAt: id, library: library, player: player)
                                    }
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: legacyBottomClearance == 0 ? 0 : nil) {
            Color.clear.frame(height: legacyBottomClearance)
        }
        .overlay {
            if model.index == nil {
                ProgressView()
            } else if children.isEmpty && (node?.directSongCount ?? 0) == 0 {
                ContentUnavailableView(
                    HomeDiscoveryText.string(nodeID == nil ? "no_folders" : "folder_unavailable"),
                    systemImage: "folder",
                    description: Text(HomeDiscoveryText.string("folders_hint"))
                )
            }
        }
        .navigationTitle(node.map(HomeDiscoveryText.folderTitle) ?? HomeDiscoveryText.string("folders"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .minimalNavigationDetail(isDetail: nodeID != nil)
        .librarySearchContext {
            guard let nodeID, let node else { return nil }
            return LibrarySearchScope(
                title: HomeDiscoveryText.folderTitle(node),
                songIDs: Set(model.index?.songIDs(in: nodeID, scope: .descendants) ?? []),
                includesSubfolders: true
            )
        }
        #endif
        .toolbar {
            if let node {
                ToolbarItemGroup(placement: .primaryAction) {
                    pinButton(node.id)
                    Menu {
                        Button("play", systemImage: "play.fill") { playFolder(node.id, shuffle: false) }
                        Button("shuffle", systemImage: "shuffle") { playFolder(node.id, shuffle: true) }
                    } label: { Image(systemName: "play.circle") }
                    .disabled(node.descendantSongCount == 0)
                    .accessibilityLabel("play")
                }
            }
            #if os(iOS)
            if node == nil, !usesInlineControls {
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
            #endif
        }
    }

    private func childRow(_ child: LibraryFolderNode) -> some View {
        HStack {
            NavigationLink {
                HomeFolderBrowser(nodeID: child.id)
                    .environment(model)
            } label: {
                HomeFolderChildLabel(node: child)
            }
            if child.kind != .source { pinButton(child.id) }
        }
    }

    private func pinButton(_ id: LibraryFolderNodeID) -> some View {
        let pinned = pins.contains(id)
        return Button {
            var updated = pins
            if pinned { updated.removeAll { $0 == id } } else { updated.insert(id, at: 0) }
            pinsRawValue = HomeFolderPinStorage.encode(updated)
        } label: {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .frame(width: 44, height: 44)
                .foregroundStyle(pinned ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(HomeDiscoveryText.string(pinned ? "unpin_folder" : "pin_folder"))
    }

    private func playFolder(_ id: LibraryFolderNodeID, shuffle: Bool) {
        HomeDiscoveryPlayback.play(ids: model.songs(in: id).map(\.id), shuffle: shuffle, library: library, player: player)
    }
}

private struct HomeFolderChildLabel: View {
    let node: LibraryFolderNode

    var body: some View {
        HStack(spacing: 12) {
            HomeFolderArtwork(node: node, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(HomeDiscoveryText.folderTitle(node)).lineLimit(2)
                Text("\(node.descendantSongCount.formatted()) \(String(localized: "songs_count"))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
enum HomeDiscoveryPlayback {
    static func play(
        ids: [String], startingAt selectedID: String? = nil, shuffle: Bool = false,
        library: MusicLibrary, player: AudioPlayerService
    ) {
        var queue = ids.compactMap { library.unobservedVisibleSong(id: $0) }.filteredPlayable()
        if shuffle { queue.shuffle() }
        guard !queue.isEmpty else { return }
        if let selectedID, !queue.contains(where: { $0.id == selectedID }) { return }
        let position = selectedID.flatMap { id in queue.firstIndex { $0.id == id } } ?? 0
        player.setQueue(queue, startAt: position)
        Task { await player.play(song: queue[position]) }
    }
}
