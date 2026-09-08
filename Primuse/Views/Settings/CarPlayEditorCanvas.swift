#if os(iOS)
import PrimuseKit
import SwiftUI

struct CarPlayEditorCanvas: View {
    let blocks: [CarPlayHomeBlock]
    let configuration: CarPlayLayoutConfiguration
    let selectedID: String?
    let editing: Bool
    let playerPage: Bool
    let wide: Bool
    let previewItem: CarPlayHomeItem?
    let select: (String) -> Void
    let activate: (CarPlayHomeItem) -> Void
    let drop: ([String], String?, String?) -> Bool
    let addContent: (String?) -> Void
    var catalog = CarPlayEditorCatalog.Snapshot()
    @State private var detail: CarPlayHomeItem?
    @State private var localPlayer: CarPlayHomeItem?

    private var screenWidth: CGFloat { wide ? 800 : 600 }
    private var screenHeight: CGFloat { screenWidth * 9 / 16 }

    var body: some View {
        GeometryReader { geometry in
            screen
                .frame(width: screenWidth, height: screenHeight)
                .environment(\.dynamicTypeSize, .large)
                .scaleEffect(geometry.size.width / screenWidth, anchor: .topLeading)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .background(CarPlayEditorTheme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(CarPlayEditorTheme.border, lineWidth: 1) }
        .environment(\.colorScheme, .dark)
        .onChange(of: playerPage) { detail = nil; localPlayer = nil }
        .onChange(of: editing) { detail = nil; localPlayer = nil }
        .onChange(of: configuration.visualStyle) { detail = nil; localPlayer = nil }
        .accessibilityIdentifier("carplay.canvas")
    }

    private var screen: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                if playerPage || localPlayer != nil { player(localPlayer ?? previewItem) }
                else if let detail { detailPage(detail) }
                else { home }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(CarPlayEditorTheme.text)
        .buttonStyle(.plain)
        .background(CarPlayEditorTheme.canvas)
    }

    private var sidebar: some View {
        VStack(spacing: 17) {
            Text("9:41").font(.system(size: 11, weight: .semibold))
            Image(systemName: "wifi").font(.system(size: 11))
            Image(systemName: "music.note").font(.system(size: 19, weight: .semibold))
                .foregroundStyle(CarPlayEditorTheme.background)
                .frame(width: 30, height: 30).background(CarPlayEditorTheme.accent, in: RoundedRectangle(cornerRadius: 9))
            Image(systemName: "map.fill").font(.system(size: 20)).foregroundStyle(CarPlayEditorTheme.secondary)
            Spacer()
            Image(systemName: "square.grid.2x2.fill").font(.system(size: 19))
        }
        .padding(.vertical, 14).frame(width: 54)
        .background(CarPlayEditorTheme.sidebar)
    }

    private var home: some View {
        VStack(spacing: 0) {
            HStack(spacing: 34) {
                tab("carplay_home_title", symbol: "house.fill", selected: true)
                tab("library_title", symbol: "music.note.house", selected: false)
                tab("radio_title", symbol: "radio.fill", selected: false)
                tab("playlists_title", symbol: "music.note.list", selected: false)
            }.padding(.vertical, 8)
            if configuration.showsSiri {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                Text("carplay_ask_siri")
                Spacer()
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(CarPlayEditorTheme.secondary)
            .padding(.horizontal, 10).frame(height: 26)
            .background(CarPlayEditorTheme.surface, in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12).padding(.bottom, 10)
            .onTapGesture { if editing, let block = blocks.first(where: { $0.configuration.kind == .siri }) { select(block.id) } }
            }
            if configuration.visualStyle == .split && !editing {
                HStack(alignment: .top, spacing: 12) {
                    compactPlayer.frame(width: 186)
                    blockScroll
                }.padding(.leading, 12)
            } else { blockScroll }
        }
    }

    private var blockScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 15) {
                    ForEach(blocks.filter { $0.configuration.isVisible && $0.configuration.kind != .siri }) { block in
                        blockView(block).id(block.id)
                    }
                    if editing {
                        Button { addContent(nil) } label: {
                            Label("carplay_add_module", systemImage: "plus")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(CarPlayEditorTheme.secondary)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(CarPlayEditorTheme.border, style: StrokeStyle(lineWidth: 1, dash: [4])) }
                        }
                        .dropDestination(for: String.self) { values, _ in drop(values, nil, nil) }
                    }
                }.padding(.horizontal, 12).padding(.top, editing ? 7 : 0).padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selectedID) { _, id in
                if editing, let id { proxy.scrollTo(id, anchor: .top) }
            }
        }
    }

    private func tab(_ title: LocalizedStringKey, symbol: String, selected: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 13))
            Text(title).font(.system(size: 10, weight: .semibold))
        }.foregroundStyle(selected ? CarPlayEditorTheme.accent : CarPlayEditorTheme.secondary)
    }

    private func blockView(_ block: CarPlayHomeBlock) -> some View {
        let selected = selectedID == block.id
        return VStack(alignment: .leading, spacing: 7) {
            if block.configuration.showsTitle && !editing {
                Text(block.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(CarPlayEditorTheme.secondary)
            }
            if block.items.isEmpty {
                Button { select(block.id) } label: {
                    Label("carplay_empty_module", systemImage: block.configuration.kind.symbol)
                        .font(.system(size: 14)).foregroundStyle(CarPlayEditorTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.disabled(!editing)
            } else if block.configuration.style == .list {
                VStack(spacing: 4) {
                    ForEach(block.items) { item in itemView(item, block: block) }
                }
            } else {
                let count = min(block.configuration.columns, 6)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: count), spacing: 7) {
                    ForEach(block.items) { item in itemView(item, block: block) }
                }
            }
        }
        .padding(editing ? 8 : 0)
        .background(selected && editing ? CarPlayEditorTheme.accent.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            if editing {
                RoundedRectangle(cornerRadius: 10).strokeBorder(
                    selected ? CarPlayEditorTheme.accent : CarPlayEditorTheme.border,
                    style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: selected ? [] : [4]))
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            if editing {
                Text(block.title).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selected ? CarPlayEditorTheme.background : CarPlayEditorTheme.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(selected ? CarPlayEditorTheme.accent : CarPlayEditorTheme.surface, in: RoundedRectangle(cornerRadius: 4))
                    .offset(x: 9, y: -9).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if editing && selected {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(CarPlayEditorTheme.background)
                    .frame(width: 22, height: 22).background(CarPlayEditorTheme.accent, in: Circle())
                    .offset(x: 5, y: -10).draggable("carplay-block:" + block.id)
                    .accessibilityLabel("carplay_move_module")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if editing { select(block.id) } }
        .dropDestination(for: String.self) { values, _ in drop(values, block.id, nil) }
    }

    private func itemView(_ item: CarPlayHomeItem, block: CarPlayHomeBlock) -> some View {
        Button {
            if editing { select(block.id) } else { open(item) }
        } label: {
            Group {
                if block.configuration.style == .list {
                    HStack(spacing: 9) {
                        CarPlayPreviewArtwork(item: item, pixelSize: 88).frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                            if let subtitle = item.subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(CarPlayEditorTheme.secondary).lineLimit(1) }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: block.configuration.playsImmediately ? "play.fill" : "chevron.right")
                            .font(.system(size: 11)).foregroundStyle(CarPlayEditorTheme.secondary)
                    }.padding(7).background(CarPlayEditorTheme.row, in: RoundedRectangle(cornerRadius: 6))
                } else if block.configuration.style == .capsules {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol).font(.system(size: 19))
                        Text(item.title).font(.system(size: 19, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).frame(height: 58)
                    .background(CarPlayEditorTheme.surface, in: Capsule())
                } else {
                    ZStack(alignment: .bottomLeading) {
                        CarPlayPreviewArtwork(item: item, pixelSize: 240)
                        LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                        Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(1).padding(9)
                    }
                    .frame(height: (screenHeight - (editing ? 115 : 92)) / CGFloat(block.configuration.rowsPerPage))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }.opacity(item.enabled ? 1 : 0.5)
        }
        .disabled(!editing && !item.enabled)
    }

    private func open(_ item: CarPlayHomeItem) {
        switch item.target {
        case .playlist(_, false), .album(_, false), .folder(_, false): detail = item
        default: localPlayer = item; activate(item)
        }
    }

    private func detailPage(_ item: CarPlayHomeItem) -> some View {
        VStack(spacing: 10) {
            HStack {
                Button { detail = nil } label: { Image(systemName: "chevron.left").padding(12) }
                Text(item.title).font(.system(size: 19, weight: .semibold)).lineLimit(1)
                Spacer()
                Button { localPlayer = item; activate(item) } label: { Image(systemName: "play.fill").padding(12) }
            }
            ScrollView {
                let rows = detailItems(item)
                if rows.isEmpty {
                    Text("carplay_no_content").font(.system(size: 16)).foregroundStyle(CarPlayEditorTheme.secondary).padding(30)
                }
                ForEach(rows) { entry in
                    Button { open(entry) } label: {
                        HStack {
                            Image(systemName: entry.symbol).frame(width: 24)
                            Text(entry.title).font(.system(size: 17)).lineLimit(1)
                            Spacer()
                            Image(systemName: "play.fill").font(.system(size: 12))
                        }.padding(12).background(CarPlayEditorTheme.row, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }.padding(.horizontal, 12)
        }
    }

    private func detailItems(_ item: CarPlayHomeItem) -> [CarPlayHomeItem] {
        if case .folder(let id, _) = item.target {
            let folders = CarPlayFolderLibrary.shared.index
            let children = (folders?.children(of: id) ?? []).prefix(30).map { CarPlayEditorCatalog.Snapshot.folder($0).configured(directly: false) }
            let songs = (folders?.songIDs(in: id, scope: .direct) ?? []).lazy.compactMap { catalog.lookup[.song]?[$0] }.prefix(30)
            return children + songs
        }
        return catalog.detail(for: item)
    }

    private var compactPlayer: some View {
        Button { localPlayer = previewItem ?? blocks.flatMap(\.items).first } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text("carplay_continue_listening").font(.system(size: 13)).foregroundStyle(CarPlayEditorTheme.secondary)
                CarPlayPreviewArtwork(item: displayedItem(previewItem)).frame(height: 118)
                Text(displayedItem(previewItem).title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Image(systemName: "play.fill").font(.system(size: 20)).frame(maxWidth: .infinity).padding(10)
            }.padding(12).background(CarPlayEditorTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func displayedItem(_ item: CarPlayHomeItem?) -> CarPlayHomeItem {
        if let item {
            if let first = catalog.detail(for: item).first { return first }
            return item
        }
        return CarPlayHomeItem(id: "empty", title: String(localized: "carplay_nothing_playing"), symbol: "music.note", target: .nowPlaying)
    }

    private func player(_ source: CarPlayHomeItem?) -> some View {
        let item = displayedItem(source)
        return VStack(spacing: 12) {
            HStack {
                if localPlayer != nil { Button { localPlayer = nil; detail = nil } label: { Image(systemName: "chevron.left") } }
                Text("carplay_now_playing").font(.system(size: 16, weight: .semibold))
                Spacer()
                Image(systemName: "list.bullet")
            }.padding(.horizontal, 20).padding(.top, 18)
            HStack(spacing: 24) {
                CarPlayPreviewArtwork(item: item).frame(width: 172, height: 172)
                VStack(alignment: .leading, spacing: 14) {
                    Text(item.title).font(.system(size: 23, weight: .semibold)).lineLimit(2)
                    if let subtitle = item.subtitle { Text(subtitle).font(.system(size: 15)).foregroundStyle(CarPlayEditorTheme.secondary).lineLimit(1) }
                    Capsule().fill(CarPlayEditorTheme.border).frame(height: 4)
                    HStack(spacing: 30) {
                        Image(systemName: "backward.fill")
                        Image(systemName: "play.fill").font(.system(size: 30))
                        Image(systemName: "forward.fill")
                    }.font(.system(size: 20)).frame(maxWidth: .infinity).padding(.top, 6)
                }
            }.padding(.horizontal, 24)
            if !configuration.minimalNowPlaying {
                HStack(spacing: 65) { Image(systemName: "shuffle"); Image(systemName: "repeat"); Image(systemName: "heart") }
                    .font(.system(size: 18)).foregroundStyle(CarPlayEditorTheme.secondary).padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
    }
}

struct CarPlayPreviewArtwork: View {
    let item: CarPlayHomeItem
    var pixelSize = 240
    @State private var image: UIImage?
    private var identity: String {
        let library = AppServices.shared.musicLibrary
        let artwork: String
        switch item.artwork {
        case .songReference(let id, let coverRef): artwork = id + (coverRef ?? "")
        case .song(let song): artwork = song.id + (song.coverArtFileName ?? "")
        case .album(let album): artwork = album.id + "\(library.albumArtworkLookupRevision):\(library.artworkOverrideRevision)"
        case .playlist(let playlist): artwork = playlist.id + "\(playlist.updatedAt):\(library.artworkOverrideRevision):\(library.albumArtworkLookupRevision)"
        case nil: artwork = item.id
        }
        return artwork + ":\(pixelSize)"
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CarPlayEditorTheme.artwork
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else {
                    Image(systemName: item.symbol)
                        .font(.system(size: max(10, min(42, geometry.size.width * 0.3)), weight: .medium))
                        .foregroundStyle(CarPlayEditorTheme.accent.opacity(0.7))
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: identity) {
            guard let artwork = item.artwork else { image = nil; return }
            let loaded = await CarPlayHomeContent.artwork(artwork, pixelSize: pixelSize)
            guard !Task.isCancelled else { return }
            image = loaded
        }
        .accessibilityHidden(true)
    }
}
#endif
