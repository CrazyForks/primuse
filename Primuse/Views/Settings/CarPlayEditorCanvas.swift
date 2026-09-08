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
    @State private var detail: CarPlayHomeItem?

    private var referenceWidth: CGFloat { wide ? 1120 : 800 }

    var body: some View {
        GeometryReader { geometry in
            screen
                .frame(width: referenceWidth, height: 480)
                .environment(\.dynamicTypeSize, .large)
                .scaleEffect(geometry.size.width / referenceWidth, anchor: .topLeading)
        }
        .aspectRatio(referenceWidth / 480, contentMode: .fit)
        .background(Color(white: 0.035))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.12), lineWidth: 1) }
        .environment(\.colorScheme, .dark)
        .onChange(of: playerPage) { detail = nil }
        .onChange(of: editing) { detail = nil }
    }

    private var screen: some View {
        HStack(spacing: 0) {
            VStack(spacing: 28) {
                Text("9:41").font(.system(size: 19, weight: .semibold))
                Image(systemName: "wifi").font(.system(size: 18))
                Spacer()
                Image(systemName: "music.note").font(.system(size: 25)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                Image(systemName: "map.fill").font(.system(size: 25)).foregroundStyle(.gray)
                Spacer()
                Image(systemName: "square.grid.2x2.fill").font(.system(size: 25))
            }
            .padding(.vertical, 22).frame(width: 70)
            .background(.white.opacity(0.055))
            VStack(spacing: 0) {
                if playerPage {
                    player
                } else if let detail {
                    detailPage(detail)
                } else {
                    home
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .background(Color(white: 0.035))
    }

    private var home: some View {
        VStack(spacing: 0) {
            HStack(spacing: 30) {
                tab("carplay_home_title", symbol: "house.fill", selected: true)
                tab("library_title", symbol: "music.note.house", selected: false)
                tab("radio_title", symbol: "radio.fill", selected: false)
                tab("playlists_title", symbol: "music.note.list", selected: false)
            }
            .padding(.vertical, 14)
            Divider().overlay(.white.opacity(0.1))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform").font(.system(size: 24))
                        Text("carplay_ask_siri").font(.system(size: 21, weight: .medium))
                        Spacer()
                    }.padding(14).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    ForEach(blocks) { block in blockView(block) }
                    if editing {
                        Button { addContent(nil) } label: {
                            Label("carplay_drop_content", systemImage: "plus")
                                .font(.system(size: 18, weight: .medium))
                                .frame(maxWidth: .infinity, minHeight: 58)
                                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6])) }
                        }
                        .dropDestination(for: String.self) { values, _ in drop(values, nil, nil) }
                    }
                    navigationRows
                }.padding(14)
            }.scrollIndicators(.visible)
        }
    }

    private func tab(_ title: LocalizedStringKey, symbol: String, selected: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 22))
            Text(title).font(.system(size: 16, weight: .semibold))
        }.foregroundStyle(selected ? Color.accentColor : .white.opacity(0.55))
    }

    @ViewBuilder private func blockView(_ block: CarPlayHomeBlock) -> some View {
        if editing || !block.items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if editing || block.configuration.showsTitle {
                    HStack {
                        if editing {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.white.opacity(0.45))
                                .padding(.vertical, 6)
                                .draggable("carplay-block:" + block.id)
                                .accessibilityLabel("carplay_move_module")
                        }
                        Text(block.title).font(.system(size: 18, weight: .semibold))
                            .opacity(block.configuration.showsTitle ? 1 : 0.4)
                        Spacer()
                        if editing && block.configuration.kind == .custom {
                            Button { addContent(block.id) } label: { Image(systemName: "plus").padding(6) }
                                .accessibilityLabel("carplay_add_content")
                        }
                    }
                }
                if block.items.isEmpty {
                    Label("carplay_empty_module", systemImage: block.configuration.kind.symbol)
                        .font(.system(size: 19)).foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity, minHeight: 78)
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                } else if block.configuration.style == .list {
                    VStack(spacing: 1) {
                        ForEach(block.items) { item in itemView(item, in: block, size: 48) }
                    }.clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    let count = CarPlayHomeContent.rowSize(for: block.configuration)
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(block.items) { item in
                            itemView(item, in: block, size: (referenceWidth - 130 - CGFloat(count - 1) * 12) / CGFloat(count))
                        }
                    }
                }
            }
            .padding(editing ? 10 : 0)
            .background(editing && selectedID == block.id ? Color.accentColor.opacity(0.09) : .clear,
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                if editing {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(selectedID == block.id ? Color.accentColor : .white.opacity(0.1), lineWidth: selectedID == block.id ? 2 : 1)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if editing { select(block.id) } }
            .dropDestination(for: String.self) { values, _ in drop(values, block.id, nil) }
        }
    }

    private func itemView(_ item: CarPlayHomeItem, in block: CarPlayHomeBlock, size: CGFloat) -> some View {
        Button {
            if editing { select(block.id) }
            else { open(item) }
        } label: {
            Group {
                if block.configuration.style == .list {
                    HStack(spacing: 14) {
                        CarPlayPreviewArtwork(item: item).frame(width: size, height: size)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.system(size: 21, weight: .medium)).lineLimit(1)
                            if let subtitle = item.subtitle { Text(subtitle).font(.system(size: 16)).foregroundStyle(.white.opacity(0.55)).lineLimit(1) }
                        }
                        Spacer()
                        Image(systemName: block.configuration.playsImmediately ? "play.fill" : "chevron.right").font(.system(size: 16)).foregroundStyle(.white.opacity(0.45))
                    }.padding(12).background(.white.opacity(0.075))
                } else {
                    let cards = usesCards(block.configuration.style)
                    VStack(alignment: .leading, spacing: 8) {
                        CarPlayPreviewArtwork(item: item)
                            .frame(width: min(size - (cards ? 24 : 0), cards ? 124 : 156),
                                   height: min(size - (cards ? 24 : 0), cards ? 124 : 156))
                        Text(item.title).font(.system(size: 18, weight: .medium))
                            .lineLimit(cards ? 2 : 1)
                        if let subtitle = item.subtitle {
                            Text(subtitle).font(.system(size: 15)).foregroundStyle(.white.opacity(0.55)).lineLimit(cards ? 2 : 1)
                        }
                    }
                    .padding(cards ? 12 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cards ? Color.white.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 12))
                }
            }.opacity(item.enabled ? 1 : 0.4)
        }
        .disabled(!editing && !item.enabled)
        .modifier(CarPlayItemDrag(enabled: editing && block.configuration.kind == .custom,
                                   value: "carplay-item:\(block.id):\(item.id)"))
        .dropDestination(for: String.self) { values, _ in drop(values, block.id, item.id) }
    }

    private func usesCards(_ style: CarPlayBrowseStyle) -> Bool {
        if #available(iOS 26.0, *) { return style == .cards }
        return false
    }

    private var navigationRows: some View {
        VStack(spacing: 1) {
            navigationRow("library_browse_folder", symbol: "folder")
            navigationRow("library_title", symbol: "music.note.house")
            navigationRow("carplay_layout_title", symbol: "rectangle.3.group")
        }.clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func navigationRow(_ title: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).frame(width: 32)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.45))
        }.font(.system(size: 21)).padding(16).background(.white.opacity(0.075))
    }

    private func open(_ item: CarPlayHomeItem) {
        switch item.target {
        case .playlist(_, false), .album(_, false), .folder(_, false): detail = item
        default: activate(item)
        }
    }

    private func detailPage(_ item: CarPlayHomeItem) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { detail = nil } label: { Image(systemName: "chevron.left").padding(8) }
                Text(item.title).lineLimit(1)
                Spacer()
            }.font(.system(size: 24, weight: .semibold)).padding(16)
            ScrollView {
                VStack(spacing: 1) {
                    Button { activate(item) } label: { navigationRow("carplay_play_all", symbol: "play.fill") }
                    Button { activate(item) } label: { navigationRow("carplay_shuffle_all", symbol: "shuffle") }
                    if case .folder(let id, _) = item.target {
                        ForEach(Array((CarPlayFolderLibrary.shared.index?.children(of: id) ?? []).prefix(100))) { node in
                            Button {
                                detail = CarPlayHomeItem(id: HomeFolderPinStorage.encode([node.id]), title: HomeDiscoveryText.folderTitle(node),
                                                         symbol: "folder", target: .folder(node.id, directly: false))
                            } label: {
                                HStack {
                                    Image(systemName: "folder")
                                    Text(HomeDiscoveryText.folderTitle(node)).lineLimit(1)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }.font(.system(size: 21)).padding(18).background(.white.opacity(0.075))
                            }
                        }
                    }
                    ForEach(Array(detailSongs(item).prefix(100))) { song in
                        Button {
                            activate(CarPlayHomeItem(id: song.id, title: song.title, artwork: .song(song), target: .song(song.id, queue: [song.id])))
                        } label: {
                            HStack {
                                Text(song.title).lineLimit(1)
                                Spacer()
                                Image(systemName: "play.fill").font(.system(size: 15))
                            }.font(.system(size: 21)).padding(18).background(.white.opacity(0.075))
                        }
                    }
                }.padding(14)
            }
        }
    }

    private func detailSongs(_ item: CarPlayHomeItem) -> [Song] {
        if case .folder(let id, _) = item.target { return CarPlayFolderLibrary.shared.songs(in: id, scope: .direct) }
        return CarPlayHomeContent.songs(for: item.target)
    }

    private var player: some View {
        let item = playerItem
        return VStack(spacing: 0) {
            HStack {
                Text("carplay_now_playing").font(.system(size: 23, weight: .semibold))
                Spacer()
                Image(systemName: "list.bullet").font(.system(size: 23))
            }.padding(22)
            HStack(spacing: 36) {
                CarPlayPreviewArtwork(item: item).frame(width: 236, height: 236)
                VStack(alignment: .leading, spacing: 18) {
                    Text(item.title).font(.system(size: 28, weight: .semibold)).lineLimit(2)
                    if let subtitle = item.subtitle { Text(subtitle).font(.system(size: 20)).foregroundStyle(.white.opacity(0.6)).lineLimit(1) }
                    Capsule().fill(.white.opacity(0.15)).frame(height: 5)
                        .overlay(alignment: .leading) { Capsule().fill(.white.opacity(0.6)).frame(width: 50, height: 5) }
                    HStack(spacing: 40) {
                        Image(systemName: "backward.fill")
                        Image(systemName: "play.fill").font(.system(size: 42))
                        Image(systemName: "forward.fill")
                    }.font(.system(size: 28)).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            }.padding(.horizontal, 26)
            Spacer()
            if !configuration.minimalNowPlaying {
                HStack(spacing: 80) {
                    Image(systemName: "shuffle")
                    Image(systemName: "repeat")
                    Image(systemName: "heart")
                }.font(.system(size: 25)).padding(.bottom, 28)
            }
        }
    }

    private var playerItem: CarPlayHomeItem {
        if let previewItem {
            let songs = CarPlayHomeContent.songs(for: previewItem.target)
            let selectedSong: Song?
            if case .song(let id, _) = previewItem.target { selectedSong = songs.first { $0.id == id } }
            else { selectedSong = songs.first }
            if let song = selectedSong {
                return CarPlayHomeItem(id: song.id, title: song.title,
                                       subtitle: AppServices.shared.musicLibrary.artistDisplayName(for: song),
                                       artwork: .song(song), target: previewItem.target)
            }
            return previewItem
        }
        let player = AppServices.shared.playerService
        if let song = player.currentSong {
            return CarPlayHomeItem(id: song.id, title: song.title, subtitle: AppServices.shared.musicLibrary.artistDisplayName(for: song),
                                   artwork: .song(song), target: .nowPlaying)
        }
        return CarPlayHomeItem(id: "empty", title: player.currentRadioStation?.name ?? String(localized: "carplay_nothing_playing"),
                               symbol: player.currentRadioStation == nil ? "music.note" : "radio", target: .nowPlaying)
    }
}

private struct CarPlayItemDrag: ViewModifier {
    let enabled: Bool
    let value: String
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.draggable(value) }
        else { content }
    }
}

struct CarPlayPreviewArtwork: View {
    let item: CarPlayHomeItem
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08))
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else { Image(systemName: item.symbol).font(.system(size: max(18, min(52, geometry.size.width * 0.3)))).foregroundStyle(.white.opacity(0.5)) }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .task(id: item.id) {
            image = nil
            if let artwork = item.artwork { image = await CarPlayHomeContent.artwork(artwork, pixelSize: 320) }
        }
        .accessibilityHidden(true)
    }
}
#endif
