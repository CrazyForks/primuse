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
                    HomeFolderBrowser(showsInlineBack: true)
                        #if os(iOS)
                        .minimalNavigationDetail()
                        #endif
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
    var onOpen: (() -> Void)? = nil
    @Environment(HomeDiscoveryModel.self) private var model
    @Environment(MusicLibrary.self) private var library
    @Environment(AudioPlayerService.self) private var player
    @AppStorage(HomeFolderPinStorage.key) private var pinsRawValue = ""

    private var playButtonWidth: CGFloat {
        #if os(macOS)
        32
        #else
        44
        #endif
    }

    private var artworkSize: CGFloat {
        #if os(macOS)
        36
        #else
        54
        #endif
    }

    var body: some View {
        let _ = model.revision
        HStack(spacing: 8) {
            Group {
                if let onOpen {
                    Button(action: onOpen) { folderLabel }
                } else {
                    NavigationLink {
                        HomeFolderBrowser(nodeID: node.id)
                            .environment(model)
                    } label: { folderLabel }
                }
            }
            .buttonStyle(.plain)

            Button { play(shuffle: false) } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 25))
                    .frame(width: playButtonWidth, height: artworkSize)
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

    private var folderLabel: some View {
        HStack(spacing: 14) {
            HomeFolderArtwork(node: node, size: artworkSize)
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
    var showsInlineBack = false
    #if os(iOS)
    @Environment(\.appNavigationMode) private var appNavigationMode
    @Environment(\.editMode) private var editMode
    #endif
    #if os(macOS)
    @Environment(\.dismiss) private var dismiss
    @State private var macListChromeHeight: CGFloat = 0
    @State private var macListViewportHeight: CGFloat = 0
    @State private var macSongAction: SongRowActionRequest?
    @State private var macFolderPath: [LibraryFolderNodeID] = []
    #endif
    @Environment(HomeDiscoveryModel.self) private var model
    @Environment(MusicLibrary.self) private var library
    @Environment(AudioPlayerService.self) private var player
    @AppStorage(HomeFolderPinStorage.key) private var pinsRawValue = ""

    private var currentNodeID: LibraryFolderNodeID? {
        #if os(macOS)
        macFolderPath.last ?? nodeID
        #else
        nodeID
        #endif
    }

    private var node: LibraryFolderNode? { currentNodeID.flatMap { model.index?.node(withID: $0) } }
    private var pins: [LibraryFolderNodeID] { model.pins(from: pinsRawValue) }
    private var children: [LibraryFolderNode] {
        if let currentNodeID { return model.index?.children(of: currentNodeID) ?? [] }
        return model.index?.sourceNodes ?? []
    }

    private var legacyBottomClearance: CGFloat {
        #if os(iOS)
        appNavigationMode == .minimal ? 0 : 90
        #else
        0
        #endif
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            macHeader
            if let currentNodeID {
                macFolderList(nodeID: currentNodeID)
            } else {
                folderList
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .environment(\.defaultMinListRowHeight, 48)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PMColor.bg)
        .background {
            if let request = macSongAction {
                // Present actions once per page, outside the recycled scroll rows.
                SongRowView(song: request.song, actionRequest: request)
                    .id(request.id)
            }
        }
        .navigationBarBackButtonHidden(nodeID != nil || showsInlineBack)
        #else
        folderList
        #endif
    }

    private var folderList: some View {
        List {
            if nodeID == nil, !pins.isEmpty {
                Section {
                    ForEach(pins, id: \.self) { id in
                        if let node = model.index?.node(withID: id) {
                            #if os(macOS)
                            HomeFolderRow(node: node, onOpen: { openMacFolder(node.id) })
                            #else
                            HomeFolderRow(node: node)
                            #endif
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
                // 先过滤缺失歌曲，让 List 的每个元素固定生成一行，保留按需加载。
                let songs = ids.compactMap { library.unobservedVisibleSong(id: $0) }
                if !songs.isEmpty {
                    Section("tab_songs") {
                        ForEach(songs) { song in
                            SongRowView(song: song, isPlaying: player.currentSong?.id == song.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    HomeDiscoveryPlayback.play(ids: ids, startingAt: song.id, library: library, player: player)
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
            if node == nil, !usesInlineControls {
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
        }
        #endif
    }

    #if os(macOS)
    private func openMacFolder(_ id: LibraryFolderNodeID) {
        guard id != currentNodeID else { return }
        // Native navigation pushes recreate window history/chrome; keep folder changes inside this pane.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            macSongAction = nil
            macFolderPath.append(id)
        }
    }

    private func macFolderList(nodeID: LibraryFolderNodeID) -> some View {
        let folders = children
        let songIDs = model.index?.directSongIDs(in: nodeID) ?? []
        let hasSongSection = !folders.isEmpty && !songIDs.isEmpty
        let songStart = folders.count + (hasSongSection ? 1 : 0)

        return MacWindowedSongScrollView(
            rowCount: songStart + songIDs.count,
            rowHeight: 56,
            chromeHeight: $macListChromeHeight,
            viewportHeight: $macListViewportHeight
        ) {
            if !folders.isEmpty || !songIDs.isEmpty {
                macSectionHeader(folders.isEmpty ? String(localized: "tab_songs") : HomeDiscoveryText.string("folders"))
                    .padding(.horizontal, PMSpace.xxxl)
                    .padding(.vertical, 8)
            }
        } rowContent: { position in
            if position < folders.count {
                childRow(folders[position])
            } else if hasSongSection && position == folders.count {
                macSectionHeader(String(localized: "tab_songs"))
            } else {
                let songID = songIDs[position - songStart]
                MacHomeFolderSongRow(songID: songID, orderedSongIDs: songIDs) { song, action in
                    macSongAction = SongRowActionRequest(song: song, action: action)
                }
                    .id(songID)
            }
        }
        .modifier(MacFolderScrollReset(nodeID: nodeID))
        .overlay {
            if model.index == nil {
                ProgressView()
            } else if folders.isEmpty && songIDs.isEmpty {
                ContentUnavailableView(
                    HomeDiscoveryText.string("folder_unavailable"),
                    systemImage: "folder",
                    description: Text(HomeDiscoveryText.string("folders_hint"))
                )
            }
        }
    }

    private func macSectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PMColor.textMuted)
            Divider()
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var macHeader: some View {
        HStack(spacing: 12) {
            if currentNodeID != nil || showsInlineBack {
                MacNavigationBackButton(accessibilityIdentifier: "folderInlineBack") {
                    if macFolderPath.isEmpty {
                        dismiss()
                    } else {
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            macSongAction = nil
                            macFolderPath.removeLast()
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(node.map(HomeDiscoveryText.folderTitle) ?? HomeDiscoveryText.string("folders"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(PMColor.text)
                    .lineLimit(1)
                if let node {
                    Text("\(node.descendantSongCount.formatted()) \(String(localized: "songs_count"))")
                        .font(.system(size: 12))
                        .foregroundStyle(PMColor.textMuted)
                }
            }
            Spacer(minLength: 12)
            if let node {
                pinButton(node.id)
                Button("play_all", systemImage: "play.fill") {
                    playFolder(node.id, shuffle: false)
                }
                .buttonStyle(.borderedProminent)
                .disabled(node.descendantSongCount == 0)
                Button("shuffle", systemImage: "shuffle") {
                    playFolder(node.id, shuffle: true)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .disabled(node.descendantSongCount == 0)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }
    #endif

    private func childRow(_ child: LibraryFolderNode) -> some View {
        HStack {
            #if os(macOS)
            Button { openMacFolder(child.id) } label: {
                HomeFolderChildLabel(node: child)
            }
            .buttonStyle(.plain)
            #else
            NavigationLink {
                HomeFolderBrowser(nodeID: child.id)
                    .environment(model)
            } label: {
                HomeFolderChildLabel(node: child)
            }
            if child.kind != .source { pinButton(child.id) }
            #endif
        }
        #if os(macOS)
        .contextMenu {
            Button("play", systemImage: "play.fill") { playFolder(child.id, shuffle: false) }
                .disabled(child.descendantSongCount == 0)
            Button("shuffle", systemImage: "shuffle") { playFolder(child.id, shuffle: true) }
                .disabled(child.descendantSongCount == 0)
            if child.kind != .source {
                let pinned = pins.contains(child.id)
                Button(HomeDiscoveryText.string(pinned ? "unpin_folder" : "pin_folder"),
                       systemImage: pinned ? "pin.slash" : "pin") {
                    togglePin(child.id)
                }
            }
        }
        #endif
    }

    private func pinButton(_ id: LibraryFolderNodeID) -> some View {
        let pinned = pins.contains(id)
        return Button {
            togglePin(id)
        } label: {
            Image(systemName: pinned ? "pin.fill" : "pin")
                #if os(macOS)
                .frame(width: 30, height: 30)
                #else
                .frame(width: 44, height: 44)
                #endif
                .foregroundStyle(pinned ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(HomeDiscoveryText.string(pinned ? "unpin_folder" : "pin_folder"))
    }

    private func togglePin(_ id: LibraryFolderNodeID) {
        var updated = pins
        if updated.contains(id) { updated.removeAll { $0 == id } } else { updated.insert(id, at: 0) }
        pinsRawValue = HomeFolderPinStorage.encode(updated)
    }

    private func playFolder(_ id: LibraryFolderNodeID, shuffle: Bool) {
        HomeDiscoveryPlayback.play(ids: model.songs(in: id).map(\.id), shuffle: shuffle, library: library, player: player)
    }
}

#if os(macOS)
private struct MacFolderScrollReset: ViewModifier {
    let nodeID: LibraryFolderNodeID
    @State private var position = ScrollPosition()

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .task(id: nodeID) {
                await Task.yield()
                guard !Task.isCancelled else { return }
                position.scrollTo(y: 0)
            }
    }
}

private struct MacHomeFolderSongRow: View {
    let songID: String
    let orderedSongIDs: [String]
    let performAction: (Song, SongRowActionRequest.Action) -> Void
    @Environment(MusicLibrary.self) private var library
    @Environment(AudioPlayerService.self) private var player
    @Environment(SourceManager.self) private var sourceManager

    var body: some View {
        // Observe replacements only for rows inside the scroll window.
        if let song = library.visibleSong(id: songID) {
            let isCurrent = player.currentSong?.id == songID
            Button {
                if song.isPlayable {
                    HomeDiscoveryPlayback.play(ids: orderedSongIDs, startingAt: songID, library: library, player: player)
                } else {
                    performAction(song, .unavailable)
                }
            } label: {
                HStack(spacing: 10) {
                    CachedArtworkView(
                        coverRef: song.coverArtFileName, songID: songID,
                        size: 36, cornerRadius: 5,
                        sourceID: song.sourceID, filePath: song.filePath,
                        fileFormat: song.fileFormat
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(isCurrent ? PMColor.brand : PMColor.text)
                        Text([library.artistDisplayName(for: song), song.albumTitle].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11.5))
                            .foregroundStyle(PMColor.textMuted)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if isCurrent {
                        Image(systemName: "play.fill")
                            .foregroundStyle(PMColor.brand)
                            .font(.system(size: 11))
                    }
                    if song.duration > 0 {
                        Text(song.duration.formattedDuration)
                            .font(.system(size: 11, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(PMColor.textMuted)
                    }
                    if song.sourceID != AppleMusicLibraryService.systemSourceID {
                        OfflineAudioStatusBadge(snapshot: sourceManager.offlineAudioSnapshotEntry(for: song).snapshot)
                    }
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .pmRowBackground(selected: isCurrent)
            }
            .buttonStyle(.plain)
            .contextMenu {
                MacHomeFolderSongMenu(song: song) { performAction(song, $0) }
            }
            .task(id: songID) {
                guard song.sourceID != AppleMusicLibraryService.systemSourceID else { return }
                // Skip disk probes for rows that pass through the window during fast scrolling.
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                await sourceManager.ensureOfflineAudioSnapshot(for: song)
            }
        } else {
            Color.clear
        }
    }
}

private struct MacHomeFolderSongMenu: View {
    let song: Song
    let performAction: (SongRowActionRequest.Action) -> Void
    @Environment(SourceManager.self) private var sourceManager
    @Environment(MetadataBackfillService.self) private var backfill

    var body: some View {
        Section {
            Button("scrape_song", systemImage: "wand.and.stars") { performAction(.scrape) }
            Button("tag_editor_menu", systemImage: "tag") { performAction(.editTags) }
            Button("lyrics_editor_menu", systemImage: "quote.bubble") { performAction(.editLyrics) }
            Button("add_to_playlist", systemImage: "text.badge.plus") { performAction(.addToPlaylist) }
            Button("similar_songs", systemImage: "sparkles") { performAction(.similar) }
            if song.sourceID != AppleMusicLibraryService.systemSourceID {
                offlineActions
            }
            if backfill.canRereadTags(for: song) {
                Button(String(localized: backfill.isRereadingTags(songID: song.id) ? "reread_song_tags_in_progress" : "reread_song_tags"),
                       systemImage: "arrow.clockwise") { performAction(.rereadTags) }
                    .disabled(backfill.isRereadingTags(songID: song.id))
            }
            Button("song_info", systemImage: "info.circle") { performAction(.info) }
        }
        Section {
            Button("share", systemImage: "square.and.arrow.up") { performAction(.share) }
        }
    }

    @ViewBuilder
    private var offlineActions: some View {
        let snapshot = sourceManager.offlineAudioSnapshotEntry(for: song).snapshot
        switch snapshot.state {
        case .downloading:
            Button("offline_downloading", systemImage: "arrow.down.circle") {}
                .disabled(true)
        case .pinned:
            Button("offline_remove_song_cache", systemImage: "trash", role: .destructive) {
                sourceManager.removeOfflineDownload(song: song)
            }
        case .cached:
            Button("offline_keep_cached", systemImage: "pin") { sourceManager.downloadForOffline(song: song) }
            Button("offline_remove_cached_file", systemImage: "trash", role: .destructive) {
                sourceManager.removeOfflineDownload(song: song)
            }
        case .failed:
            Button("offline_retry_download", systemImage: "arrow.clockwise") { sourceManager.downloadForOffline(song: song) }
            Button("offline_clear_failed_download", systemImage: "trash", role: .destructive) {
                sourceManager.removeOfflineDownload(song: song)
            }
        case .notCached:
            Button("offline_cache_song", systemImage: "arrow.down.circle") { sourceManager.downloadForOffline(song: song) }
        }
    }
}
#endif

private struct HomeFolderChildLabel: View {
    let node: LibraryFolderNode

    var body: some View {
        HStack(spacing: 12) {
            #if os(macOS)
            HomeFolderArtwork(node: node, size: 32)
            #else
            HomeFolderArtwork(node: node, size: 44)
            #endif
            VStack(alignment: .leading, spacing: 4) {
                Text(HomeDiscoveryText.folderTitle(node)).lineLimit(2)
                Text("\(node.descendantSongCount.formatted()) \(String(localized: "songs_count"))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        #if os(macOS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        #endif
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
