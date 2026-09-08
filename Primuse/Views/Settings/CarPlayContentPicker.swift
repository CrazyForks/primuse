#if os(iOS)
import PrimuseKit
import SwiftUI

struct CarPlayContentPicker: View {
    var embedded = false
    var close: (() -> Void)?
    let add: (CarPlayLayoutItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind: CarPlayLayoutItem.Kind = .playlist
    @State private var query = ""
    @State private var folderID: LibraryFolderNodeID?
    @State private var folders = CarPlayFolderLibrary.shared
    @State private var owner = UUID()

    init(embedded: Bool = false, initialKind: CarPlayLayoutItem.Kind = .playlist,
         close: (() -> Void)? = nil, add: @escaping (CarPlayLayoutItem) -> Void) {
        self.embedded = embedded
        self.close = close
        self.add = add
        _kind = State(initialValue: initialKind)
    }

    private var items: [CarPlayLayoutItem] {
        let library = AppServices.shared.musicLibrary
        let all: [CarPlayLayoutItem]
        switch kind {
        case .playlist:
            all = library.playlists.map { .init(id: $0.id, kind: .playlist, targetID: $0.id, title: $0.name) }
        case .album:
            all = library.visibleAlbums.map { .init(id: $0.id, kind: .album, targetID: $0.id, title: $0.title) }
        case .song:
            all = library.visibleSongs.map { .init(id: $0.id, kind: .song, targetID: $0.id, title: $0.title) }
        case .radio:
            all = AppServices.shared.radioStationsStore.stations.map { .init(id: $0.id, kind: .radio, targetID: $0.id, title: $0.name) }
        case .folder:
            let nodes = folderID.map { folders.index?.children(of: $0) ?? [] } ?? folders.index?.sourceNodes ?? []
            all = nodes.map { .init(id: HomeFolderPinStorage.encode([$0.id]), kind: .folder,
                                    targetID: HomeFolderPinStorage.encode([$0.id]), title: HomeDiscoveryText.folderTitle($0)) }
        }
        return all.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        Group {
            if embedded {
                VStack(spacing: 12) {
                    HStack {
                        Text(LocalizedStringKey(title(kind))).font(.headline)
                        Spacer()
                        Button("done") { close?() }
                    }
                    TextField("carplay_find_content", text: $query).textFieldStyle(.roundedBorder)
                    contents
                }
            } else {
                NavigationStack {
                    contents
                        .navigationTitle(LocalizedStringKey(title(kind)))
                        .navigationBarTitleDisplayMode(.inline)
                        .searchable(text: $query)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("done") { dismiss() } } }
                }
            }
        }
        .onChange(of: kind) { query = ""; folderID = nil }
        .onAppear { folders.acquire(owner) }
        .onDisappear { folders.release(owner) }
    }

    private var contents: some View {
        VStack(spacing: 0) {
            Picker("carplay_content_type", selection: $kind) {
                ForEach(CarPlayLayoutItem.Kind.allCases) { kind in
                    Image(systemName: symbol(kind)).accessibilityLabel(LocalizedStringKey(title(kind))).tag(kind)
                }
            }.pickerStyle(.segmented).padding(.bottom, 10)
            List {
                if kind == .folder, let folderID {
                    Button("carplay_parent_folder", systemImage: "arrow.up") {
                        self.folderID = folders.index?.node(withID: folderID)?.parentID
                    }
                    if let node = folders.index?.node(withID: folderID) {
                        row(.init(kind: .folder, targetID: HomeFolderPinStorage.encode([folderID]), title: HomeDiscoveryText.folderTitle(node)), navigates: false)
                    }
                }
                ForEach(items) { item in row(item, navigates: kind == .folder) }
            }
            .listStyle(.plain)
            .overlay {
                if items.isEmpty && folderID == nil {
                    if kind == .folder && folders.isLoading { ProgressView() }
                    else { ContentUnavailableView("carplay_no_content", systemImage: symbol(kind)) }
                }
            }
        }
    }

    private func row(_ item: CarPlayLayoutItem, navigates: Bool) -> some View {
        HStack {
            if navigates {
                Button { folderID = item.folderID; query = "" } label: {
                    Label(item.title, systemImage: "folder").frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            } else {
                Label(item.title, systemImage: symbol(item.kind))
                Spacer()
            }
            Button("carplay_add_content", systemImage: "plus.circle") {
                add(item)
                if !embedded { dismiss() }
            }.labelStyle(.iconOnly).buttonStyle(.borderless)
        }
        .draggable(item.dragValue)
    }

    private func title(_ kind: CarPlayLayoutItem.Kind) -> String {
        switch kind {
        case .playlist: "playlists_title"
        case .folder: "library_browse_folder"
        case .album: "carplay_section_albums"
        case .song: "carplay_tab_songs"
        case .radio: "radio_title"
        }
    }
    private func symbol(_ kind: CarPlayLayoutItem.Kind) -> String {
        switch kind {
        case .playlist: "music.note.list"
        case .folder: "folder"
        case .album: "square.stack"
        case .song: "music.note"
        case .radio: "radio"
        }
    }
}
#endif
