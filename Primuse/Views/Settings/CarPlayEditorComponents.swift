#if os(iOS)
import PrimuseKit
import SwiftUI

// Shared with the supplied Nocturne CarPlay reference.
enum CarPlayEditorTheme {
    static let background = Color(red: 22/255, green: 24/255, blue: 38/255)
    static let canvas = Color(red: 15/255, green: 16/255, blue: 24/255)
    static let sidebar = Color(red: 20/255, green: 21/255, blue: 31/255)
    static let surface = Color(red: 30/255, green: 32/255, blue: 51/255)
    static let sheet = Color(red: 27/255, green: 29/255, blue: 44/255)
    static let row = Color(red: 26/255, green: 28/255, blue: 40/255)
    static let border = Color(red: 46/255, green: 49/255, blue: 73/255)
    static let accent = Color(red: 145/255, green: 132/255, blue: 217/255)
    static let accentText = Color(red: 195/255, green: 187/255, blue: 236/255)
    static let text = Color(red: 233/255, green: 233/255, blue: 237/255)
    static let secondary = Color(red: 154/255, green: 156/255, blue: 176/255)
    static let muted = Color(red: 107/255, green: 109/255, blue: 133/255)
    static let artwork = LinearGradient(colors: [Color(red: 59/255, green: 51/255, blue: 88/255), Color(red: 29/255, green: 26/255, blue: 43/255)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct CarPlayEditorActivePreferenceKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

struct CarPlayCompactAccessory: View {
    let onTap: () -> Void
    @Environment(AudioPlayerService.self) private var player
    var body: some View {
        HStack(spacing: 4) {
            MiniPlayerSwipeContent(onTap: onTap, artworkSize: 22, artworkCornerRadius: 5,
                artworkTrailingSpacing: 8, titleFont: .system(size: 12, weight: .medium), contentHeight: 28)
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14)).frame(width: 36, height: 36)
            }.buttonStyle(.plain).accessibilityLabel(player.isPlaying ? "pause" : "play")
        }
        .padding(.leading, 8).frame(height: 36)
        .foregroundStyle(CarPlayEditorTheme.text)
        .background(CarPlayEditorTheme.surface, in: Capsule())
        .overlay { Capsule().strokeBorder(CarPlayEditorTheme.border, lineWidth: 1) }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(CarPlayEditorTheme.background)
    }
}

struct CarPlayEditorButton: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? CarPlayEditorTheme.background : CarPlayEditorTheme.accentText)
            .padding(.horizontal, 15).frame(minHeight: 32)
            .background(prominent ? CarPlayEditorTheme.accent : CarPlayEditorTheme.accent.opacity(0.12), in: Capsule())
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

struct CarPlaySegment<Value: Equatable>: View {
    let values: [(Value, String)]
    @Binding var selection: Value
    var height: CGFloat = 32
    var prominent = false
    var body: some View {
        HStack(spacing: 3) {
            ForEach(values.indices, id: \.self) { index in
                let option = values[index]
                Button { selection = option.0 } label: {
                    Text(LocalizedStringKey(option.1)).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == option.0 ? (prominent ? CarPlayEditorTheme.background : CarPlayEditorTheme.text) : CarPlayEditorTheme.secondary)
                        .frame(maxWidth: .infinity).frame(height: height)
                        .background(selection == option.0 ? (prominent ? CarPlayEditorTheme.accent : CarPlayEditorTheme.border) : .clear, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)
            }
        }.padding(3).background(CarPlayEditorTheme.surface, in: RoundedRectangle(cornerRadius: 9))
    }
}

struct CarPlayLayoutGlyph: View {
    var columns: Int
    var rows: Int
    var selected = false
    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: 3) {
                    ForEach(0..<columns, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2).fill(selected ? CarPlayEditorTheme.accent : CarPlayEditorTheme.border)
                    }
                }
            }
        }
    }
}

struct CarPlayStyleThumbnail: View {
    let style: CarPlayVisualStyle
    var body: some View {
        Image("CarPlayStyle" + style.rawValue.capitalized)
            .resizable().scaledToFit()
            .frame(maxWidth: .infinity)
            .background(CarPlayEditorTheme.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }
}

struct CarPlayPresetLibrary: View {
    let model: CarPlayEditorModel
    let close: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: close) { Image(systemName: "chevron.left").frame(width: 32, height: 32).background(CarPlayEditorTheme.surface, in: Circle()) }
                    .accessibilityLabel("back")
                Text("carplay_styles_title").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("carplay_customize", action: close).font(.system(size: 14, weight: .semibold)).foregroundStyle(CarPlayEditorTheme.accent)
            }.padding(.horizontal, 16).padding(.vertical, 8)
            Text("carplay_styles_subtitle").font(.system(size: 13)).foregroundStyle(CarPlayEditorTheme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 60).padding(.trailing, 16).padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(CarPlayVisualStyle.allCases) { style in
                        card(title: style.titleKey, subtitle: style.subtitleKey, style: style, current: model.configuration.visualStyle == style) {
                            model.apply(style)
                        }
                    }
                    if !model.settings.savedLayouts.isEmpty {
                        Text("carplay_my_presets").font(.system(size: 13, weight: .semibold)).foregroundStyle(CarPlayEditorTheme.secondary).padding(.top, 8)
                        ForEach(model.settings.savedLayouts) { saved in
                            card(title: saved.name, subtitle: "carplay_saved_layout", style: saved.configuration.visualStyle,
                                 current: model.configuration == saved.configuration) { model.apply(saved) }
                                .contextMenu {
                                    Button("delete", role: .destructive) { model.settings.savedLayouts.removeAll { $0.id == saved.id } }
                                }
                        }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 16)
            }.scrollIndicators(.hidden)
        }.background(CarPlayEditorTheme.background).foregroundStyle(CarPlayEditorTheme.text)
    }

    private func card(title: String, subtitle: String, style: CarPlayVisualStyle, current: Bool, apply: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            CarPlayStyleThumbnail(style: style).frame(height: 110)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(LocalizedStringKey(title)).font(.system(size: 15, weight: .semibold))
                        if current {
                            Text("carplay_in_use").font(.system(size: 10, weight: .bold)).foregroundStyle(CarPlayEditorTheme.background)
                                .padding(.horizontal, 7).padding(.vertical, 1).background(CarPlayEditorTheme.accent, in: Capsule())
                        }
                    }
                    Text(LocalizedStringKey(subtitle)).font(.system(size: 12)).foregroundStyle(CarPlayEditorTheme.secondary)
                }
                Spacer()
                Button {
                    if current { close() } else { apply() }
                } label: {
                    if current { Label("carplay_fine_tune", systemImage: "pencil") }
                    else { Text("carplay_use") }
                }.buttonStyle(CarPlayEditorButton(prominent: !current)).fixedSize()
                    .overlay { Capsule().strokeBorder(current ? CarPlayEditorTheme.accent : .clear, lineWidth: 1) }
                    .accessibilityIdentifier("carplay.preset." + style.rawValue)
            }
        }
        .padding(12)
        .background(current ? CarPlayEditorTheme.accent.opacity(0.10) : CarPlayEditorTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(current ? CarPlayEditorTheme.accent : CarPlayEditorTheme.border, lineWidth: current ? 1.5 : 1) }
    }
}

struct CarPlayModulePicker: View {
    let model: CarPlayEditorModel
    let close: () -> Void
    @State private var query = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(CarPlayEditorTheme.border).frame(width: 36, height: 4).frame(maxWidth: .infinity)
            HStack {
                Text("carplay_add_module").font(.system(size: 19, weight: .semibold))
                Spacer()
                Button("done", action: close).foregroundStyle(CarPlayEditorTheme.accent).font(.system(size: 14, weight: .semibold))
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(CarPlayEditorTheme.muted)
                TextField("", text: $query, prompt: Text("carplay_search_modules").foregroundStyle(CarPlayEditorTheme.muted)).autocorrectionDisabled()
            }.font(.system(size: 13)).padding(10).background(CarPlayEditorTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(CarPlayEditorTheme.border, lineWidth: 1) }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("carplay_play_entries").font(.system(size: 12)).foregroundStyle(CarPlayEditorTheme.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach([CarPlayLayoutBlockKind.shortcuts, .custom].filter(matches)) { kind in tile(kind) }
                    }
                    Text("library_title").font(.system(size: 12)).foregroundStyle(CarPlayEditorTheme.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach([CarPlayLayoutBlockKind.folders, .playlists, .albums, .ranking, .recentlyAdded, .radio, .siri].filter(matches)) { kind in tile(kind) }
                    }
                }.padding(.bottom, 20)
            }.scrollIndicators(.hidden)
        }
        .padding(16).background(CarPlayEditorTheme.sheet).foregroundStyle(CarPlayEditorTheme.text)
        .presentationBackground(CarPlayEditorTheme.sheet).presentationCornerRadius(20)
    }

    private func matches(_ kind: CarPlayLayoutBlockKind) -> Bool {
        query.isEmpty || NSLocalizedString(kind.titleKey, comment: "").localizedStandardContains(query)
    }
    private func add(_ kind: CarPlayLayoutBlockKind) { model.add(kind) }
    private func added(_ kind: CarPlayLayoutBlockKind) -> Bool { model.configuration.blocks.contains { $0.kind == kind } }
    private func tile(_ kind: CarPlayLayoutBlockKind) -> some View {
        Button { add(kind) } label: {
            VStack(alignment: .leading, spacing: 9) {
                moduleGlyph(kind)
                    .padding(7).frame(height: 52).background(CarPlayEditorTheme.canvas, in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Text(LocalizedStringKey(kind == .custom ? "carplay_cover_wall" : kind.titleKey)).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: added(kind) ? "checkmark.circle.fill" : "plus.circle").foregroundStyle(CarPlayEditorTheme.accent)
                }
                Text(LocalizedStringKey("carplay_module_" + kind.rawValue + "_detail")).font(.system(size: 11)).foregroundStyle(CarPlayEditorTheme.secondary)
            }.padding(10).background(CarPlayEditorTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(added(kind) ? CarPlayEditorTheme.accent.opacity(0.7) : CarPlayEditorTheme.border, lineWidth: 1) }
        }.buttonStyle(.plain).disabled(model.configuration.blocks.count >= CarPlayLayoutConfiguration.maximumBlockCount)
            .accessibilityIdentifier("carplay.add." + kind.rawValue)
    }
    @ViewBuilder private func moduleGlyph(_ kind: CarPlayLayoutBlockKind) -> some View {
        switch kind {
        case .ranking:
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 4) {
                    ForEach([0.8, 0.6, 0.4], id: \.self) { fraction in
                        Capsule().fill(CarPlayEditorTheme.accent.opacity(fraction))
                            .frame(width: geometry.size.width * fraction, height: 6)
                    }
                }.frame(maxHeight: .infinity)
            }
        case .shortcuts, .playlists, .recentlyAdded:
            CarPlayLayoutGlyph(columns: 1, rows: 3)
        case .folders:
            CarPlayLayoutGlyph(columns: 3, rows: 1)
        case .albums:
            CarPlayLayoutGlyph(columns: 3, rows: 2)
        case .custom, .radio, .siri:
            CarPlayLayoutGlyph(columns: 2, rows: 2)
        }
    }
}
#endif
