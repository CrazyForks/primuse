#if os(iOS)
import PrimuseKit
import SwiftUI

struct CarPlaySettingsView: View {
    @Environment(\.settingsFocusedAnchor) private var focusedAnchor
    @State private var model: CarPlayEditorModel
    @State private var catalog = CarPlayEditorCatalog.shared
    @State private var folders = CarPlayFolderLibrary.shared
    @State private var showingLibrary = false
    @State private var addingModule = false
    @State private var addingContent = false
    @State private var fullScreen = false
    @State private var savingPreset = false
    @State private var presetName = ""
    @State private var owner = UUID()
    @State private var previewItem: CarPlayHomeItem?
    @State private var dropTargetID: String?

    init(settings: CarPlaySettingsStore = .shared, model: CarPlayEditorModel? = nil, showsLibrary: Bool = false) {
        _model = State(initialValue: model ?? CarPlayEditorModel(settings: settings))
        _showingLibrary = State(initialValue: showsLibrary)
    }

    private var nowPlaying: CarPlayHomeItem? {
        let player = AppServices.shared.playerService
        guard player.currentSong != nil || player.currentRadioStation != nil else { return nil }
        return CarPlayHomeItem(id: "nowPlaying", title: String(localized: "carplay_now_playing"),
            subtitle: player.currentSong?.title ?? player.currentRadioStation?.name, symbol: "play.circle.fill",
            artwork: player.currentSong.map(CarPlayContentArtwork.song), target: .nowPlaying)
    }

    private var blocks: [CarPlayHomeBlock] {
        catalog.snapshot.blocks(for: model.configuration, folders: folders.index, nowPlaying: nowPlaying)
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if showingLibrary {
                    CarPlayPresetLibrary(model: model) { showingLibrary = false }
                } else {
                    VStack(spacing: 0) {
                        if !model.inspectorVisible {
                            presetStrip.padding(.top, 8)
                            screenSelector.padding(.horizontal, 16).padding(.top, 12)
                        }
                        canvas
                            .frame(maxWidth: model.inspectorVisible ? min(600, max(300, (geometry.size.height - 330) * 16 / 9)) : 760)
                            .padding(.horizontal, 16).padding(.top, 12)
                        if model.inspectorVisible, let block = model.selected, !model.playerPage {
                            Spacer(minLength: 0)
                            CarPlayModuleInspector(model: model, block: block,
                                items: blocks.first(where: { $0.id == block.id })?.items ?? [],
                                add: { addingContent = true }, preview: { fullScreen = true })
                                .frame(maxHeight: 492).padding(.top, 16)
                        } else if model.playerPage {
                            playbackInspector
                        } else {
                            if !model.preview {
                                Label("carplay_canvas_hint", systemImage: "hand.tap")
                                    .font(.system(size: 11)).foregroundStyle(CarPlayEditorTheme.muted)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 10)
                                moduleList
                            } else { Spacer(minLength: 0) }
                        }
                    }
                }
            }
            .frame(maxWidth: 800).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CarPlayEditorTheme.background)
        }
        .foregroundStyle(CarPlayEditorTheme.text)
        .navigationTitle(LocalizedStringKey(showingLibrary ? "carplay_styles_title" : "carplay_editor_title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(showingLibrary || model.inspectorVisible)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { editorToolbar }
        .toolbar(.hidden, for: .tabBar)
        .preference(key: CarPlayEditorActivePreferenceKey.self, value: true)
        .sheet(isPresented: $addingModule) {
            CarPlayModulePicker(model: model) { addingModule = false }
                .presentationDetents([.large])
        }
        .sheet(isPresented: $addingContent) {
            CarPlayContentPicker(catalog: catalog, initialKind: focusedAnchor == "carplay.folders" ? .folder : .playlist) { item in
                if model.selectedID == nil { model.add(.custom) }
                guard let id = model.selectedID else { return false }
                return model.addContent(item, to: id, resolved: blocks.first(where: { $0.id == id })?.items ?? [])
            }.presentationDetents([.large])
        }
        .fullScreenCover(isPresented: $fullScreen) { expandedPreview }
        .alert("carplay_save_preset", isPresented: $savingPreset) {
            TextField("carplay_preset_name", text: $presetName)
            Button("cancel", role: .cancel) {}
            Button("save") {
                model.flush()
                let saved = CarPlaySavedLayout(name: presetName, configuration: model.configuration)
                if !saved.name.isEmpty { model.settings.savedLayouts.append(saved) }
            }.disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onAppear {
            catalog.acquire(owner)
            updateFolderAccess()
        }
        .onDisappear { model.continuousChange(false); model.flush(); catalog.release(owner); folders.release(owner) }
        .onChange(of: model.configuration.folderIDs) { updateFolderAccess() }
        .onChange(of: model.configuration.blocks) { updateFolderAccess() }
        .task(id: focusedAnchor) {
            if ["carplay.onConnect", "carplay.afterPlay", "carplay.minimal"].contains(focusedAnchor ?? "") {
                model.playerPage = true
            } else if focusedAnchor == "carplay.folders" || focusedAnchor == "carplay.playlists" {
                addingContent = true
            }
        }
    }

    @ToolbarContentBuilder private var editorToolbar: some ToolbarContent {
        if showingLibrary || model.inspectorVisible {
            ToolbarItem(placement: .topBarLeading) {
                Button("back", systemImage: "chevron.backward") {
                    showingLibrary = false
                    model.inspectorVisible = false
                    model.continuousChange(false)
                }.labelStyle(.iconOnly)
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if model.inspectorVisible {
                Button("done") { model.inspectorVisible = false; model.continuousChange(false) }
            } else if !showingLibrary {
                Button { model.preview.toggle() } label: { Text(LocalizedStringKey(model.preview ? "carplay_edit" : "carplay_preview")) }
                    .accessibilityIdentifier("carplay.previewMode")
                Menu {
                    Button("carplay_undo", action: model.undo).disabled(!model.history.canUndo)
                        .accessibilityIdentifier("carplay.undo")
                    Button("carplay_redo", action: model.redo).disabled(!model.history.canRedo)
                        .accessibilityIdentifier("carplay.redo")
                    Divider()
                    Button("carplay_save_preset_short", systemImage: "square.and.arrow.down") { presetName = ""; savingPreset = true }
                } label: { Image(systemName: "ellipsis") }
                    .accessibilityIdentifier("carplay.actions")
            }
        }
    }

    private var presetStrip: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    Button { showingLibrary = true } label: {
                        Image(systemName: "square.grid.2x2").frame(width: 30, height: 30)
                            .background(CarPlayEditorTheme.surface, in: Circle())
                    }.accessibilityLabel("carplay_styles_title").accessibilityIdentifier("carplay.styles")
                    ForEach(CarPlayVisualStyle.allCases) { style in
                        Button { model.apply(style) } label: {
                            Text(LocalizedStringKey(style.titleKey)).font(.system(size: 11, weight: .medium))
                                .foregroundStyle(model.configuration.visualStyle == style ? CarPlayEditorTheme.accentText : CarPlayEditorTheme.secondary)
                                .padding(.horizontal, 10).frame(height: 30)
                                .background(model.configuration.visualStyle == style ? CarPlayEditorTheme.accent.opacity(0.18) : CarPlayEditorTheme.surface, in: Capsule())
                        }.accessibilityIdentifier("carplay.style." + style.rawValue)
                    }
                    ForEach(model.settings.savedLayouts) { saved in
                        Button(saved.name) { model.apply(saved) }.font(.system(size: 11)).buttonStyle(.bordered).buttonBorderShape(.capsule)
                    }
                    Button { presetName = ""; savingPreset = true } label: {
                        Label("carplay_save_preset_short", systemImage: "plus").font(.system(size: 11))
                            .padding(.horizontal, 10).frame(height: 30)
                            .overlay { Capsule().strokeBorder(CarPlayEditorTheme.border, style: StrokeStyle(lineWidth: 1, dash: [3])) }
                    }
                }.padding(.leading, 16)
            }.scrollIndicators(.hidden).accessibilityIdentifier("carplay.presets")
            HStack(spacing: 4) {
                Button { cycleStyle(-1) } label: { Image(systemName: "arrow.left").frame(width: 32, height: 32) }
                    .accessibilityLabel("back").accessibilityIdentifier("carplay.previousStyle")
                Button { cycleStyle(1) } label: { Image(systemName: "arrow.right").frame(width: 32, height: 32) }
                    .accessibilityLabel("next").accessibilityIdentifier("carplay.nextStyle")
            }.font(.body).padding(.trailing, 16)
        }.buttonStyle(.plain).settingsAnchor("carplay.preset")
    }

    private var screenSelector: some View {
        HStack(spacing: 8) {
            CarPlaySegment(values: [(false, "carplay_home_title"), (true, "carplay_now_playing")], selection: $model.playerPage)
            Button { fullScreen = true } label: {
                Image(systemName: "arrow.up.right.and.arrow.down.left").font(.system(size: 13))
                    .frame(width: 34, height: 34).background(CarPlayEditorTheme.surface, in: RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain).accessibilityLabel("carplay_expand_preview").accessibilityIdentifier("carplay.expand")
        }
    }

    private var canvas: some View {
        CarPlayEditorCanvas(blocks: blocks, configuration: model.configuration, selectedID: model.selectedID,
            editing: !model.preview, playerPage: model.playerPage, wide: false, previewItem: previewItem ?? nowPlaying,
            select: model.select, activate: { previewItem = $0 },
            drop: { values, id, _ in model.drop(values, before: id) },
            addContent: { _ in addingModule = true }, catalog: catalog.snapshot)
            .settingsAnchor("carplay.sections")
    }

    private var moduleList: some View {
        VStack(spacing: 10) {
            HStack {
                Text("carplay_home_modules").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { addingModule = true } label: { Label("carplay_add", systemImage: "plus").font(.system(size: 12, weight: .semibold)) }
                    .accessibilityIdentifier("carplay.addModule")
            }.padding(.horizontal, 16).padding(.top, 16)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.configuration.blocks) { block in moduleRow(block) }
                    if model.configuration.blocks.isEmpty {
                        Button { addingModule = true } label: {
                            Label("carplay_add_module", systemImage: "plus").frame(maxWidth: .infinity).padding(30)
                        }.buttonStyle(.plain)
                    }
                    Color.clear.frame(height: 14).dropDestination(for: String.self) { values, _ in model.drop(values, before: nil) }
                }.padding(.horizontal, 16).padding(.bottom, 12)
            }.scrollIndicators(.hidden)
        }
    }

    private func moduleRow(_ block: CarPlayLayoutBlock) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").font(.system(size: 13)).foregroundStyle(CarPlayEditorTheme.muted)
                .frame(width: 18, height: 36)
                .draggable("carplay-block:" + block.id) {
                    Label(block.title.isEmpty ? NSLocalizedString(block.kind.titleKey, comment: "") : block.title, systemImage: block.kind.symbol)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(CarPlayEditorTheme.text)
                        .frame(width: 260, height: 54).background(CarPlayEditorTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                }.accessibilityLabel("carplay_move_module").accessibilityIdentifier("carplay.drag." + block.id)
            Button { model.select(block.id) } label: {
                HStack(spacing: 10) {
                    Image(systemName: block.kind.symbol).font(.system(size: 15)).foregroundStyle(CarPlayEditorTheme.accentText)
                        .frame(width: 28, height: 28).background(CarPlayEditorTheme.border.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(block.title.isEmpty ? NSLocalizedString(block.kind.titleKey, comment: "") : block.title).font(.system(size: 14, weight: .semibold))
                        Text(moduleSummary(block)).font(.system(size: 11)).foregroundStyle(CarPlayEditorTheme.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("carplay.module." + block.id)
            Button { model.update(block.id) { $0.isVisible.toggle() } } label: {
                Image(systemName: block.isVisible ? "eye.fill" : "eye.slash").font(.system(size: 15))
                    .foregroundStyle(block.isVisible ? CarPlayEditorTheme.accent : CarPlayEditorTheme.muted)
                    .frame(width: 32, height: 36)
            }.buttonStyle(.plain).accessibilityLabel(block.isVisible ? "carplay_hide_module" : "carplay_show_module")
                .accessibilityIdentifier("carplay.visibility." + block.id)
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(CarPlayEditorTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder((model.selectedID == block.id || dropTargetID == block.id) ? CarPlayEditorTheme.accent.opacity(0.65) : CarPlayEditorTheme.border, lineWidth: 1) }
        .opacity(block.isVisible ? 1 : 0.5)
        .dropDestination(for: String.self) { values, _ in
            dropTargetID = nil
            return model.drop(values, before: block.id)
        } isTargeted: { targeted in
            if targeted { dropTargetID = block.id }
            else if dropTargetID == block.id { dropTargetID = nil }
        }
        .accessibilityAction(named: Text("carplay_move_up")) { model.move(block.id, by: -1) }
        .accessibilityAction(named: Text("carplay_move_down")) { model.move(block.id, by: 1) }
    }

    private func moduleSummary(_ block: CarPlayLayoutBlock) -> String {
        guard block.isVisible else { return String(localized: "carplay_module_hidden") }
        let style = block.style == .list || block.style == .capsules ? NSLocalizedString(block.style.titleKey, comment: "") : "\(block.columns)×\(block.rowsPerPage) " + String(localized: "carplay_style_covers")
        return style + " · \(block.itemLimit) " + String(localized: "carplay_items_unit") + " · " + String(localized: block.playsImmediately ? "carplay_action_play" : "carplay_action_browse")
    }

    private var playbackInspector: some View {
        Form {
            Picker("carplay_player_style", selection: configurationBinding(\.minimalNowPlaying)) {
                Text("carplay_player_standard").tag(false)
                Text("carplay_preset_focus").tag(true)
            }
            Picker("carplay_connection_page", selection: configurationBinding(\.opensNowPlayingOnConnect)) {
                Text("carplay_home_title").tag(false)
                Text("carplay_now_playing").tag(true)
            }
            Picker("carplay_after_selection", selection: configurationBinding(\.opensNowPlayingAfterSelection)) {
                Text("carplay_stay_here").tag(false)
                Text("carplay_now_playing").tag(true)
            }
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 16)
        .accessibilityIdentifier("carplay.playbackOptions")
    }

    private func configurationBinding(_ keyPath: WritableKeyPath<CarPlayLayoutConfiguration, Bool>) -> Binding<Bool> {
        Binding(get: { model.configuration[keyPath: keyPath] }, set: { value in model.change { $0[keyPath: keyPath] = value } })
    }

    private var expandedPreview: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                CarPlayEditorTheme.canvas.ignoresSafeArea()
                CarPlayEditorCanvas(blocks: blocks, configuration: model.configuration, selectedID: nil,
                    editing: false, playerPage: model.playerPage, wide: geometry.size.width > 700,
                    previewItem: previewItem ?? nowPlaying, select: { _ in }, activate: { previewItem = $0 },
                    drop: { _, _, _ in false }, addContent: { _ in }, catalog: catalog.snapshot)
                    .frame(maxWidth: min(geometry.size.width, geometry.size.height * 16 / 9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 12) {
                    Button { cycleStyle(-1) } label: { Image(systemName: "arrow.left").frame(width: 32, height: 36) }
                    Text(LocalizedStringKey(model.configuration.visualStyle.titleKey)).font(.system(size: 12, weight: .semibold))
                    Button { cycleStyle(1) } label: { Image(systemName: "arrow.right").frame(width: 32, height: 36) }
                    Spacer()
                    Button { fullScreen = false; model.preview = false } label: { Label("carplay_edit", systemImage: "pencil").font(.system(size: 13, weight: .semibold)) }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule)
                }.padding(.horizontal, 16).padding(.vertical, 8).background(CarPlayEditorTheme.background.opacity(0.94), in: Capsule()).padding(16)
            }
        }.foregroundStyle(CarPlayEditorTheme.text)
    }

    private func cycleStyle(_ offset: Int) {
        let styles = CarPlayVisualStyle.allCases
        let index = styles.firstIndex(of: model.configuration.visualStyle) ?? 0
        model.apply(styles[(index + offset + styles.count) % styles.count])
    }

    private func updateFolderAccess() {
        let needed = !model.configuration.folderIDs.isEmpty || model.configuration.blocks.contains { $0.kind == .folders || $0.items.contains { $0.kind == .folder } }
        if needed { folders.acquire(owner) } else { folders.release(owner) }
    }
}
#endif

#if os(iOS) && DEBUG
struct CarPlayEditorTestHost: View {
    @State private var settings: CarPlaySettingsStore
    init() {
        let defaults = UserDefaults(suiteName: "CarPlayEditorUITests")!
        if ProcessInfo.processInfo.environment["PRIMUSE_CARPLAY_RESET"] == "1" {
            defaults.removePersistentDomain(forName: "CarPlayEditorUITests")
        }
        _settings = State(initialValue: CarPlaySettingsStore(defaults: defaults))
    }
    var body: some View {
        NavigationStack { CarPlaySettingsView(settings: settings) }
    }
}
#endif
