#if os(iOS)
import PrimuseKit
import SwiftUI

enum CarPlayEditorTheme {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let canvas = Color(uiColor: .systemBackground)
    static let sidebar = Color(uiColor: .secondarySystemBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let sheet = Color(uiColor: .systemBackground)
    static let row = Color(uiColor: .secondarySystemBackground)
    static let border = Color(uiColor: .separator).opacity(0.3)
    static let accent = Color.accentColor
    static let accentText = Color.accentColor
    static let text = Color.primary
    static let secondary = Color.secondary
    static let muted = Color.secondary.opacity(0.7)
    static let artwork = LinearGradient(colors: [Color(uiColor: .tertiarySystemFill), Color(uiColor: .secondarySystemFill)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct CarPlayEditorActivePreferenceKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

struct CarPlayMainMenuEditor: View {
    let model: CarPlayEditorModel
    let addCollection: () -> Void
    @State private var renaming: CarPlayMainTab?
    @State private var name = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("carplay_main_menu").font(.headline)
                Text("\(model.configuration.tabs.filter(\.isVisible).count)/\(model.maximumTabCount)").foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(CarPlayMainTab.Kind.allCases.filter { $0 != .collection }, id: \.self) { kind in
                        if !model.configuration.tabs.contains(where: { $0.kind == kind }) {
                            Button(LocalizedStringKey(kind.titleKey), systemImage: kind.symbol) { model.addTab(kind) }
                        }
                    }
                    Divider()
                    Button("carplay_content_sources", systemImage: "folder.badge.plus", action: addCollection)
                } label: { Label("carplay_add", systemImage: "plus") }
                    .disabled(!model.canAddTab).accessibilityIdentifier("carplay.addTab")
            }.font(.subheadline).padding(.horizontal, 16).padding(.top, 18)
            List {
                Section {
                    ForEach(model.configuration.tabs) { tab in
                        HStack(spacing: 12) {
                            Image(systemName: tab.symbol).frame(width: 26).foregroundStyle(.secondary)
                            Button {
                                model.selectTab(tab.id)
                            } label: {
                                HStack {
                                    Text(tab.displayTitle).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    if tab.kind == .home {
                                        Image(systemName: "chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                    }
                                }
                            }.buttonStyle(.plain).accessibilityIdentifier("carplay.editTab." + tab.id)
                            Button {
                                name = tab.displayTitle
                                renaming = tab
                            } label: {
                                Image(systemName: "pencil").frame(width: 28, height: 36)
                            }.buttonStyle(.borderless)
                                .accessibilityLabel("carplay_menu_name")
                                .accessibilityIdentifier("carplay.renameTab." + tab.id)
                            Button { model.toggleTab(tab) } label: {
                                Image(systemName: tab.isVisible ? "eye" : "eye.slash").frame(width: 32, height: 36)
                            }.buttonStyle(.borderless)
                                .disabled(tab.isVisible ? model.visibleTabs.count <= 1 : model.configuration.tabs.filter(\.isVisible).count >= model.maximumTabCount)
                                .accessibilityLabel(LocalizedStringKey(tab.isVisible ? "carplay_hide_module" : "carplay_show_module"))
                                .accessibilityIdentifier("carplay.tabVisibility." + tab.id)
                        }
                        .opacity(tab.isVisible ? 1 : 0.5)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("carplay.menuRow." + tab.id)
                        .contextMenu {
                            Button("carplay_menu_name", systemImage: "pencil") {
                                name = tab.displayTitle
                                renaming = tab
                            }
                            Button("carplay_move_up") { model.moveTab(tab.id, by: -1) }
                            Button("carplay_move_down") { model.moveTab(tab.id, by: 1) }
                            Button("delete", role: .destructive) { model.removeTab(tab.id) }
                                .disabled(tab.isVisible && model.visibleTabs.count <= 1)
                        }
                    }
                    .onMove { source, destination in
                        model.change { configuration in
                            var tabs = configuration.tabs
                            tabs.move(fromOffsets: source, toOffset: destination)
                            configuration.tabs = tabs
                        }
                    }
                }
                if model.configuration.showsSiri {
                    Section {
                        Picker("Siri", selection: Binding(get: { model.configuration.siriPresentation }, set: { value in
                            model.change { $0.siriPresentation = value }
                        })) {
                            Text("carplay_siri_button").tag(CarPlaySiriPresentation.button)
                            Text("carplay_siri_row").tag(CarPlaySiriPresentation.row)
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).contentMargins(.top, 12)
        }
        .alert("carplay_menu_name", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("carplay_menu_name", text: $name)
            Button("cancel", role: .cancel) { renaming = nil }
            Button("save") {
                if let renaming { model.renameTab(renaming.id, title: name) }
                renaming = nil
            }
        }
    }
}

struct CarPlaySegment<Value: Hashable>: View {
    let values: [(Value, String)]
    @Binding var selection: Value
    var body: some View {
        Picker("", selection: $selection) {
            ForEach(values.indices, id: \.self) { index in
                Text(LocalizedStringKey(values[index].1)).tag(values[index].0)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(minHeight: 32)
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
        HStack(spacing: 8) {
            VStack(spacing: 10) {
                Image(systemName: "music.note").foregroundStyle(.tint)
                Image(systemName: "map")
                Spacer(minLength: 0)
                Image(systemName: "square.grid.2x2")
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.vertical, 10).frame(width: 22)
            let columns = style == .wall ? 3 : style == .capsules ? 2 : 1
            let rows = style == .wall ? 2 : 3
            VStack(spacing: 6) {
                ForEach(0..<rows, id: \.self) { _ in
                    HStack(spacing: 6) {
                        ForEach(0..<columns, id: \.self) { _ in
                            if style == .wall {
                                RoundedRectangle(cornerRadius: 6).fill(CarPlayEditorTheme.artwork)
                                    .overlay { Image(systemName: "music.note").font(.caption).foregroundStyle(.secondary) }
                            } else {
                                HStack(spacing: 6) {
                                    Image(systemName: "music.note").font(.system(size: 10)).foregroundStyle(.secondary)
                                    Capsule().fill(.tertiary).frame(height: 4)
                                }.padding(8).frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(CarPlayEditorTheme.surface, in: RoundedRectangle(cornerRadius: style == .capsules ? 14 : 6))
                            }
                        }
                    }
                }
            }
        }.padding(8).background(CarPlayEditorTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }
}

struct CarPlayPresetLibrary: View {
    let model: CarPlayEditorModel
    let close: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Text("carplay_styles_subtitle").font(.system(size: 13)).foregroundStyle(CarPlayEditorTheme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 12)
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
                }.buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small).fixedSize()
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
