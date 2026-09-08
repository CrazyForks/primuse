#if os(iOS)
import PrimuseKit
import SwiftUI

struct CarPlaySettingsView: View {
    @Environment(\.settingsFocusedAnchor) private var focusedAnchor
    @State private var settings: CarPlaySettingsStore
    @State private var history = CarPlayLayoutHistory()
    @State private var selectedID: String?
    @State private var preview = false
    @State private var playerPage = false
    @State private var wideScreen = false
    @State private var showingContent = false
    @State private var savingPreset = false
    @State private var presetName = ""
    @State private var owner = UUID()
    @State private var previewItem: CarPlayHomeItem?

    init(settings: CarPlaySettingsStore = .shared) {
        _settings = State(initialValue: settings)
        _selectedID = State(initialValue: settings.configuration.blocks.first?.id)
    }

    private var selected: CarPlayLayoutBlock? {
        settings.configuration.blocks.first { $0.id == selectedID }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    editorToolbar
                    if geometry.size.width > 980 {
                        HStack(alignment: .top, spacing: 24) {
                            workspace
                            inspector.frame(width: 280)
                        }
                    } else {
                        workspace
                        inspector
                    }
                }
                .padding(geometry.size.width > 600 ? 24 : 16)
                .frame(maxWidth: 1440)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .navigationTitle("CarPlay")
        .navigationBarTitleDisplayMode(.inline)
        .alert("carplay_save_preset", isPresented: $savingPreset) {
            TextField("carplay_preset_name", text: $presetName)
            Button("cancel", role: .cancel) {}
            Button("save") {
                let saved = CarPlaySavedLayout(name: presetName, configuration: settings.configuration)
                if !saved.name.isEmpty { settings.savedLayouts.append(saved) }
            }
            .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onAppear {
            CarPlayFolderLibrary.shared.acquire(owner)
            if selectedID == nil { selectedID = settings.configuration.blocks.first?.id }
        }
        .onDisappear { CarPlayFolderLibrary.shared.release(owner) }
        .task(id: focusedAnchor) {
            if ["carplay.onConnect", "carplay.afterPlay", "carplay.minimal"].contains(focusedAnchor ?? "") {
                playerPage = true
                showingContent = false
            } else if focusedAnchor == "carplay.folders" || focusedAnchor == "carplay.playlists" {
                playerPage = false
                showingContent = true
            }
        }
    }

    private var editorToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack { presetMenu; Spacer(); historyButtons; modePicker }
            VStack(alignment: .leading, spacing: 12) {
                HStack { presetMenu; Spacer(); historyButtons }
                modePicker
            }
        }
    }

    private var presetMenu: some View {
        Menu {
            ForEach(CarPlayLayoutPreset.allCases) { preset in
                Button(LocalizedStringKey(preset.titleKey)) {
                    change { $0.apply(preset) }
                    selectedID = settings.configuration.blocks.first?.id
                    playerPage = preset == .focus
                }
            }
            if !settings.savedLayouts.isEmpty {
                Section("carplay_my_presets") {
                    ForEach(settings.savedLayouts) { saved in
                        Menu(saved.name) {
                            Button("carplay_apply_preset") {
                                change { $0 = saved.configuration }
                                selectedID = settings.configuration.blocks.first?.id
                                playerPage = saved.configuration.opensNowPlayingOnConnect
                            }
                            Button("delete", role: .destructive) {
                                settings.savedLayouts.removeAll { $0.id == saved.id }
                            }
                        }
                    }
                }
            }
            Divider()
            Button("carplay_save_preset", systemImage: "plus") {
                presetName = ""
                savingPreset = true
            }
        } label: {
            Label("carplay_layout_title", systemImage: "rectangle.3.group")
                .font(.subheadline.weight(.semibold))
        }
        .settingsAnchor("carplay.preset")
    }

    private var historyButtons: some View {
        HStack(spacing: 4) {
            Button("carplay_undo", systemImage: "arrow.uturn.backward") {
                if let value = history.undo(settings.configuration) { settings.configuration = value }
            }.disabled(!history.canUndo)
            Button("carplay_redo", systemImage: "arrow.uturn.forward") {
                if let value = history.redo(settings.configuration) { settings.configuration = value }
            }.disabled(!history.canRedo)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.large)
    }

    private var modePicker: some View {
        Picker("carplay_editor_mode", selection: $preview) {
            Text("carplay_edit").tag(false)
            Text("carplay_preview").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 220)
    }

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("carplay_screen", selection: $playerPage) {
                    Text("carplay_home_title").tag(false)
                    Text("carplay_now_playing").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
                Spacer(minLength: 8)
                Button {
                    wideScreen.toggle()
                } label: {
                    Image(systemName: wideScreen ? "rectangle" : "arrow.left.and.right")
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(wideScreen ? "carplay_standard_screen" : "carplay_wide_screen")
            }
            CarPlayEditorCanvas(
                blocks: CarPlayHomeContent.resolve(settings.configuration),
                configuration: settings.configuration, selectedID: selectedID,
                editing: !preview, playerPage: playerPage, wide: wideScreen,
                previewItem: previewItem,
                select: { selectedID = $0 },
                activate: { item in
                    previewItem = item
                    if case .nowPlaying = item.target { playerPage = true }
                    else { playerPage = settings.configuration.opensNowPlayingAfterSelection }
                },
                drop: handleDrop,
                addContent: { selectedID = $0; showingContent = true }
            )
            .settingsAnchor("carplay.sections")
            if !preview && !playerPage { moduleShelf }
        }
    }

    private var moduleShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("carplay_add_module").font(.subheadline.weight(.semibold))
                Spacer()
                Button("carplay_add_content", systemImage: "plus") { showingContent = true }
                    .font(.subheadline.weight(.semibold))
                    .settingsAnchor("carplay.playlists")
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(CarPlayLayoutBlockKind.allCases) { kind in
                        Button { addBlock(kind) } label: {
                            VStack(alignment: .leading, spacing: 18) {
                                Image(systemName: kind.symbol).font(.title3)
                                Text(LocalizedStringKey(kind.titleKey)).font(.caption.weight(.medium))
                            }
                            .frame(width: 112, height: 68, alignment: .leading)
                            .padding(12)
                            .background(.background, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .draggable("carplay-add:" + kind.rawValue)
                        .disabled(settings.configuration.blocks.count >= CarPlayLayoutConfiguration.maximumBlockCount)
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }

    @ViewBuilder private var inspector: some View {
        if !preview {
            VStack(alignment: .leading, spacing: 18) {
                if showingContent {
                    CarPlayContentPicker(embedded: true, initialKind: focusedAnchor == "carplay.folders" ? .folder : .playlist,
                                         close: { showingContent = false }) { item in
                        addContent(item, to: selectedID)
                    }
                    .frame(height: 440)
                    .settingsAnchor("carplay.folders")
                } else if playerPage { playbackInspector }
                else if let block = selected { blockInspector(block) }
                else {
                    Label("carplay_select_module", systemImage: "cursorarrow.click")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func blockInspector(_ block: CarPlayLayoutBlock) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(LocalizedStringKey(block.kind.titleKey), systemImage: block.kind.symbol)
                    .font(.headline)
                Spacer()
                Menu {
                    Button("carplay_move_up", systemImage: "arrow.up") { moveSelected(up: true) }
                    Button("carplay_move_down", systemImage: "arrow.down") { moveSelected(up: false) }
                    Button("carplay_duplicate", systemImage: "plus.square.on.square") { duplicate(block) }
                        .disabled(settings.configuration.blocks.count >= CarPlayLayoutConfiguration.maximumBlockCount)
                    Button("delete", systemImage: "trash", role: .destructive) {
                        change { $0.blocks.removeAll { $0.id == block.id } }
                        selectedID = settings.configuration.blocks.first?.id
                    }
                } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                .accessibilityLabel("carplay_module_actions")
            }
            HStack {
                TextField(LocalizedStringKey(block.kind.titleKey), text: blockBinding(\.title, fallback: ""))
                    .textFieldStyle(.roundedBorder)
                Button {
                    updateSelected { $0.showsTitle.toggle() }
                } label: { Image(systemName: block.showsTitle ? "eye" : "eye.slash") }
                .accessibilityLabel("carplay_show_title")
                .accessibilityValue(block.showsTitle ? String(localized: "carplay_visible") : String(localized: "carplay_hidden"))
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("carplay_browse_style").font(.caption).foregroundStyle(.secondary)
                Picker("carplay_browse_style", selection: blockBinding(\.style, fallback: .covers)) {
                    ForEach(CarPlayBrowseStyle.allCases) { style in
                        Image(systemName: style == .list ? "list.bullet" : (style == .covers ? "square.grid.2x2" : "rectangle.grid.3x2"))
                            .accessibilityLabel(LocalizedStringKey(style.titleKey)).tag(style)
                    }
                }.pickerStyle(.segmented)
                Text(LocalizedStringKey(block.style.titleKey)).font(.caption).foregroundStyle(.secondary)
            }.settingsAnchor("carplay.style")
            if block.style != .list {
                VStack(alignment: .leading, spacing: 8) {
                    Text("carplay_columns").font(.caption).foregroundStyle(.secondary)
                    Picker("carplay_columns", selection: blockBinding(\.columns, fallback: 3)) {
                        ForEach(2...6, id: \.self) { Text("\($0)").tag($0) }
                    }.pickerStyle(.segmented)
                }
            }
            Stepper(value: blockBinding(\.itemLimit, fallback: 6), in: 1...24) {
                HStack { Text("carplay_item_count"); Text("\(block.itemLimit)").monospacedDigit().foregroundStyle(.secondary) }
            }.font(.subheadline)
            if block.kind != .recentlyAdded && block.kind != .radio {
                VStack(alignment: .leading, spacing: 8) {
                    Text("carplay_tap_action").font(.caption).foregroundStyle(.secondary)
                    Picker("carplay_tap_action", selection: blockBinding(\.playsImmediately, fallback: true)) {
                        Text("carplay_action_play").tag(true)
                        Text("carplay_action_browse").tag(false)
                    }.pickerStyle(.segmented)
                }.settingsAnchor("carplay.directPlay")
            }
            if block.kind == .custom {
                Divider()
                ForEach(block.items) { item in
                    HStack {
                        Text(item.title).font(.subheadline).lineLimit(2)
                        Spacer()
                        Menu {
                            Button("carplay_move_up", systemImage: "arrow.up") { moveContent(item.id, up: true) }
                            Button("carplay_move_down", systemImage: "arrow.down") { moveContent(item.id, up: false) }
                            Button("delete", systemImage: "trash", role: .destructive) {
                                updateSelected { $0.items.removeAll { $0.id == item.id } }
                            }
                        } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                        .accessibilityLabel("carplay_content_actions")
                    }
                    .draggable("carplay-item:\(block.id):\(item.id)")
                    .dropDestination(for: String.self) { values, _ in handleDrop(values, block.id, item.id) }
                }
                Button("carplay_add_content", systemImage: "plus") { showingContent = true }
                    .disabled(block.items.count >= 24)
            }
        }
    }

    private var playbackInspector: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("carplay_now_playing", systemImage: "play.rectangle").font(.headline)
            playbackChoice("carplay_player_style", keyPath: \.minimalNowPlaying,
                           off: "carplay_player_standard", on: "carplay_preset_focus")
                .settingsAnchor("carplay.minimal")
            playbackChoice("carplay_connection_page", keyPath: \.opensNowPlayingOnConnect,
                           off: "carplay_home_title", on: "carplay_now_playing")
                .settingsAnchor("carplay.onConnect")
            playbackChoice("carplay_after_selection", keyPath: \.opensNowPlayingAfterSelection,
                           off: "carplay_stay_here", on: "carplay_now_playing")
                .settingsAnchor("carplay.afterPlay")
            Divider()
            NavigationLink { SiriSettingsView() } label: { Label("Siri", systemImage: "waveform") }
        }
    }

    private func playbackChoice(_ title: LocalizedStringKey, keyPath: WritableKeyPath<CarPlayLayoutConfiguration, Bool>,
                                off: LocalizedStringKey, on: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Picker(title, selection: Binding(get: { settings.configuration[keyPath: keyPath] },
                                             set: { value in change { $0[keyPath: keyPath] = value } })) {
                Text(off).tag(false)
                Text(on).tag(true)
            }.pickerStyle(.segmented)
        }
    }

    private func change(_ action: (inout CarPlayLayoutConfiguration) -> Void) {
        var next = settings.configuration
        action(&next)
        history.record(settings.configuration, replacing: next)
        settings.configuration = next
    }

    private func updateSelected(_ action: (inout CarPlayLayoutBlock) -> Void) {
        guard let selectedID else { return }
        change { config in
            var blocks = config.blocks
            guard let index = blocks.firstIndex(where: { $0.id == selectedID }) else { return }
            action(&blocks[index])
            config.blocks = blocks
        }
    }

    private func blockBinding<Value>(_ keyPath: WritableKeyPath<CarPlayLayoutBlock, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { selected?[keyPath: keyPath] ?? fallback },
                set: { value in updateSelected { $0[keyPath: keyPath] = value } })
    }

    private func addBlock(_ kind: CarPlayLayoutBlockKind, before: String? = nil) {
        guard settings.configuration.blocks.count < CarPlayLayoutConfiguration.maximumBlockCount else { return }
        let block = CarPlayLayoutBlock(kind: kind)
        change {
            var blocks = $0.blocks
            let index = before.flatMap { id in blocks.firstIndex { $0.id == id } } ?? blocks.count
            blocks.insert(block, at: index)
            $0.blocks = blocks
        }
        selectedID = block.id
        playerPage = false
    }

    private func addContent(_ item: CarPlayLayoutItem, to blockID: String?, before itemID: String? = nil) {
        if let block = settings.configuration.blocks.first(where: { $0.id == blockID && $0.kind == .custom }) {
            guard block.items.count < 24 else { return }
            selectedID = block.id
            updateSelected { block in
                var copy = item
                copy.id = UUID().uuidString
                let index = itemID.flatMap { id in block.items.firstIndex { $0.id == id } } ?? block.items.count
                block.items.insert(copy, at: index)
                block.itemLimit = max(block.itemLimit, block.items.count)
            }
        } else {
            guard settings.configuration.blocks.count < CarPlayLayoutConfiguration.maximumBlockCount else { return }
            var block = CarPlayLayoutBlock(kind: .custom)
            var copy = item
            copy.id = UUID().uuidString
            block.items = [copy]
            change {
                var blocks = $0.blocks
                let index = blockID.flatMap { id in blocks.firstIndex { $0.id == id } } ?? blocks.count
                blocks.insert(block, at: index)
                $0.blocks = blocks
            }
            selectedID = block.id
        }
        playerPage = false
    }

    private func handleDrop(_ values: [String], _ blockID: String?, _ itemID: String?) -> Bool {
        guard let value = values.first, !preview else { return false }
        if value.hasPrefix("carplay-block:") {
            var accepted = false
            change { accepted = $0.moveBlock(String(value.dropFirst("carplay-block:".count)), before: blockID) }
            return accepted
        }
        if value.hasPrefix("carplay-add:"), let kind = CarPlayLayoutBlockKind(rawValue: String(value.dropFirst("carplay-add:".count))) {
            guard settings.configuration.blocks.count < CarPlayLayoutConfiguration.maximumBlockCount else { return false }
            addBlock(kind, before: blockID)
            return true
        }
        if value.hasPrefix("carplay-item:"), let blockID {
            let components = value.dropFirst("carplay-item:".count).split(separator: ":").map(String.init)
            guard components.count == 2 else { return false }
            var accepted = false
            change { accepted = $0.moveItem(components[1], from: components[0], to: blockID, before: itemID) }
            return accepted
        }
        if let item = CarPlayLayoutItem.fromDragValue(value) {
            let target = settings.configuration.blocks.first { $0.id == blockID && $0.kind == .custom }
            guard target.map({ $0.items.count < 24 }) ?? (settings.configuration.blocks.count < CarPlayLayoutConfiguration.maximumBlockCount) else { return false }
            addContent(item, to: blockID, before: itemID)
            return true
        }
        return false
    }

    private func moveSelected(up: Bool) {
        let blocks = settings.configuration.blocks
        guard let selectedID, let index = blocks.firstIndex(where: { $0.id == selectedID }),
              up ? index > 0 : index < blocks.count - 1 else { return }
        let before = up ? blocks[index - 1].id : (index + 2 < blocks.count ? blocks[index + 2].id : nil)
        change { $0.moveBlock(selectedID, before: before) }
    }

    private func moveContent(_ id: String, up: Bool) {
        guard let block = selected, let index = block.items.firstIndex(where: { $0.id == id }),
              up ? index > 0 : index < block.items.count - 1 else { return }
        let before = up ? block.items[index - 1].id : (index + 2 < block.items.count ? block.items[index + 2].id : nil)
        change { $0.moveItem(id, from: block.id, to: block.id, before: before) }
    }

    private func duplicate(_ block: CarPlayLayoutBlock) {
        guard settings.configuration.blocks.count < CarPlayLayoutConfiguration.maximumBlockCount else { return }
        var copy = block
        copy.id = UUID().uuidString
        copy.items = copy.items.map { item in var next = item; next.id = UUID().uuidString; return next }
        change {
            var blocks = $0.blocks
            let index = blocks.firstIndex { $0.id == block.id } ?? (blocks.count - 1)
            blocks.insert(copy, at: index + 1)
            $0.blocks = blocks
        }
        selectedID = copy.id
    }
}
#endif
