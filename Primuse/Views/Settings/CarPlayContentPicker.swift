#if os(iOS)
import PrimuseKit
import SwiftUI

struct CarPlayContentPicker: View {
    let catalog: CarPlayEditorCatalog
    let add: (CarPlayLayoutItem) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var kind: CarPlayLayoutItem.Kind
    @State private var query = ""
    @State private var results: [CarPlayLayoutItem] = []
    @State private var selected: Set<String> = []
    @State private var folderID: LibraryFolderNodeID?
    @State private var folders = CarPlayFolderLibrary.shared
    @State private var owner = UUID()

    init(catalog: CarPlayEditorCatalog, initialKind: CarPlayLayoutItem.Kind = .playlist, add: @escaping (CarPlayLayoutItem) -> Bool) {
        self.catalog = catalog
        self.add = add
        _kind = State(initialValue: initialKind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(CarPlayEditorTheme.border).frame(width: 36, height: 4).frame(maxWidth: .infinity)
            HStack {
                Text("carplay_content_sources").font(.system(size: 19, weight: .semibold))
                Spacer()
                Button("done") { dismiss() }.font(.system(size: 14, weight: .semibold)).foregroundStyle(CarPlayEditorTheme.accent)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(CarPlayEditorTheme.muted)
                TextField("carplay_find_content", text: $query).autocorrectionDisabled()
                    .accessibilityIdentifier("carplay.contentSearch")
            }.font(.system(size: 14)).padding(11).background(CarPlayEditorTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(CarPlayLayoutItem.Kind.allCases) { option in
                        Button { kind = option } label: {
                            Label(LocalizedStringKey(title(option)), systemImage: symbol(option)).font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 11).padding(.vertical, 8)
                                .foregroundStyle(kind == option ? CarPlayEditorTheme.accentText : CarPlayEditorTheme.secondary)
                                .background(kind == option ? CarPlayEditorTheme.accent.opacity(0.16) : CarPlayEditorTheme.surface, in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }.scrollIndicators(.hidden).accessibilityIdentifier("carplay.contentKinds")
            if kind == .folder, let folderID {
                HStack {
                    Button {
                        self.folderID = folders.index?.node(withID: folderID)?.parentID
                        query = ""
                    } label: { Label("carplay_parent_folder", systemImage: "chevron.left") }
                    Spacer()
                    if let node = folders.index?.node(withID: folderID) {
                        Button("carplay_add_this_folder") {
                            append(CarPlayLayoutItem(id: HomeFolderPinStorage.encode([node.id]), kind: .folder,
                                targetID: HomeFolderPinStorage.encode([node.id]), title: HomeDiscoveryText.folderTitle(node)))
                        }
                    }
                }.font(.system(size: 12)).foregroundStyle(CarPlayEditorTheme.accent)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(results) { item in row(item) }
                    if results.isEmpty {
                        if catalog.isLoading || (kind == .folder && folders.isLoading) { ProgressView().padding(30) }
                        else { Text("carplay_no_content").font(.system(size: 14)).foregroundStyle(CarPlayEditorTheme.muted).padding(40) }
                    }
                }
            }.scrollIndicators(.hidden)
        }
        .padding(16).background(CarPlayEditorTheme.sheet).foregroundStyle(CarPlayEditorTheme.text)
        .presentationBackground(CarPlayEditorTheme.sheet).presentationCornerRadius(20)
        .task(id: requestID) { await search() }
        .onChange(of: kind) { query = ""; folderID = nil; updateFolderAccess() }
        .onAppear { updateFolderAccess() }
        .onDisappear { folders.release(owner) }
    }

    private var requestID: String {
        "\(kind.rawValue):\(query):\(folderID.map { HomeFolderPinStorage.encode([$0]) } ?? ""): \(catalog.revision):\(folders.revision)"
    }

    private func search() async {
        let source: [CarPlayLayoutItem]
        if kind == .folder {
            let nodes = folderID.map { folders.index?.children(of: $0) ?? [] } ?? folders.index?.sourceNodes ?? []
            source = nodes.map {
                .init(id: HomeFolderPinStorage.encode([$0.id]), kind: .folder,
                      targetID: HomeFolderPinStorage.encode([$0.id]), title: HomeDiscoveryText.folderTitle($0))
            }
        } else if kind == .nowPlaying {
            source = [.init(id: "nowPlaying", kind: .nowPlaying, targetID: "nowPlaying", title: String(localized: "carplay_now_playing"))]
        } else { source = catalog.snapshot.searchItems[kind] ?? [] }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
        }
        let work = Task.detached(priority: .userInitiated) {
            source.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
        }
        let values = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        guard !Task.isCancelled else { return }
        results = values
    }

    private func row(_ item: CarPlayLayoutItem) -> some View {
        let added = selected.contains(item.kind.rawValue + item.targetID)
        return HStack(spacing: 12) {
            Image(systemName: symbol(item.kind)).font(.system(size: 16)).foregroundStyle(CarPlayEditorTheme.accentText)
                .frame(width: 34, height: 34).background(CarPlayEditorTheme.border.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
            Button {
                if kind == .folder { folderID = item.folderID; query = "" }
                else { append(item) }
            } label: {
                Text(item.title).font(.system(size: 14)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { append(item) } label: {
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle").font(.system(size: 20))
                    .foregroundStyle(CarPlayEditorTheme.accent).frame(width: 36, height: 36)
            }.buttonStyle(.plain).disabled(added).accessibilityLabel("carplay_add_content")
        }.padding(10).background(CarPlayEditorTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func append(_ item: CarPlayLayoutItem) {
        let key = item.kind.rawValue + item.targetID
        guard !selected.contains(key), add(item) else { return }
        selected.insert(key)
    }

    private func updateFolderAccess() {
        if kind == .folder { folders.acquire(owner) } else { folders.release(owner) }
    }

    private func title(_ kind: CarPlayLayoutItem.Kind) -> String {
        switch kind {
        case .playlist: "playlists_title"
        case .folder: "library_browse_folder"
        case .album: "carplay_section_albums"
        case .song: "carplay_tab_songs"
        case .radio: "radio_title"
        case .nowPlaying: "carplay_now_playing"
        }
    }
    private func symbol(_ kind: CarPlayLayoutItem.Kind) -> String {
        switch kind {
        case .playlist: "music.note.list"
        case .folder: "folder"
        case .album: "square.stack"
        case .song: "music.note"
        case .radio: "radio"
        case .nowPlaying: "play.circle"
        }
    }
}
#endif
