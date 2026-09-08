#if os(iOS)
import PrimuseKit
import SwiftUI

struct CarPlayModuleInspector: View {
    let model: CarPlayEditorModel
    let block: CarPlayLayoutBlock
    let items: [CarPlayHomeItem]
    let add: () -> Void
    let preview: () -> Void
    @FocusState private var editingTitle: Bool

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(CarPlayEditorTheme.border).frame(width: 36, height: 4).padding(.top, 12)
            header.padding(.horizontal, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if block.kind == .siri {
                        NavigationLink { SiriSettingsView().toolbar(.visible, for: .navigationBar) } label: {
                            Label("carplay_siri_suggestions", systemImage: "waveform").font(.system(size: 14))
                        }
                    } else {
                    layoutOptions.settingsAnchor("carplay.style")
                    itemCount
                    VStack(alignment: .leading, spacing: 8) {
                        sectionTitle("carplay_tap_action")
                        CarPlaySegment(values: [(true, "carplay_action_play"), (false, "carplay_action_browse")], selection: binding(\.playsImmediately))
                    }.settingsAnchor("carplay.directPlay")
                    sources
                    HStack {
                        Text("carplay_show_title").font(.system(size: 12)).foregroundStyle(CarPlayEditorTheme.secondary)
                        Spacer()
                        Button { model.update(block.id) { $0.showsTitle.toggle() } } label: {
                            Image(systemName: block.showsTitle ? "text.badge.checkmark" : "textformat")
                                .frame(width: 36, height: 32).background(CarPlayEditorTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                        }.accessibilityValue(block.showsTitle ? String(localized: "carplay_visible") : String(localized: "carplay_hidden"))
                    }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 8)
            }.scrollIndicators(.hidden)
            HStack(spacing: 10) {
                Button { model.reset(block) } label: { Text("carplay_reset_module").frame(maxWidth: .infinity, minHeight: 44) }
                    .background(CarPlayEditorTheme.surface, in: Capsule())
                Button(action: preview) { Label("carplay_preview_in_car", systemImage: "eye.fill").frame(maxWidth: .infinity, minHeight: 44) }
                    .foregroundStyle(CarPlayEditorTheme.accentText)
                    .background(CarPlayEditorTheme.accent.opacity(0.12), in: Capsule())
                    .overlay { Capsule().strokeBorder(CarPlayEditorTheme.accent, lineWidth: 1) }
            }.font(.system(size: 14, weight: .medium)).buttonStyle(.plain)
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
                .background(CarPlayEditorTheme.sheet)
                .overlay(alignment: .top) { Rectangle().fill(CarPlayEditorTheme.border).frame(height: 1) }
        }
        .background(CarPlayEditorTheme.sheet)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
        .overlay(alignment: .top) { UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20).strokeBorder(CarPlayEditorTheme.border, lineWidth: 1).allowsHitTesting(false) }
        .onChange(of: editingTitle) { _, value in model.continuousChange(value) }
        .accessibilityIdentifier("carplay.inspector")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: block.kind.symbol).font(.system(size: 15)).foregroundStyle(CarPlayEditorTheme.accentText)
                .frame(width: 30, height: 30).background(CarPlayEditorTheme.border.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
            TextField("", text: binding(\.title), prompt: Text(LocalizedStringKey(block.kind.titleKey)).foregroundStyle(CarPlayEditorTheme.text))
                .font(.system(size: 17, weight: .semibold)).focused($editingTitle).submitLabel(.done)
                .onSubmit { editingTitle = false }.accessibilityLabel("carplay_module_name")
            Button { model.update(block.id) { $0.isVisible.toggle() } } label: {
                Label(block.isVisible ? "carplay_visible" : "carplay_hidden", systemImage: block.isVisible ? "eye.fill" : "eye.slash")
                    .font(.system(size: 12)).foregroundStyle(CarPlayEditorTheme.accentText).fixedSize()
            }
            Button { model.remove(block.id) } label: {
                Image(systemName: "trash").font(.system(size: 16)).foregroundStyle(CarPlayEditorTheme.secondary).frame(width: 32, height: 36)
            }.accessibilityLabel("delete")
        }.buttonStyle(.plain)
    }

    private var layoutOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("carplay_content_layout")
            HStack(spacing: 8) {
                layoutOption(.list, columns: 1, title: "carplay_style_list")
                layoutOption(.covers, columns: 2, title: "carplay_grid_2")
                layoutOption(.covers, columns: 3, title: "carplay_grid_3")
            }
            if block.style == .capsules || block.style == .cards || block.columns > 3 {
                HStack {
                    Text(LocalizedStringKey(block.style.titleKey)).font(.system(size: 11)).foregroundStyle(CarPlayEditorTheme.accentText)
                    Spacer()
                    if block.style != .list { Text("\(block.columns)").font(.system(size: 11)).foregroundStyle(CarPlayEditorTheme.secondary) }
                }
            }
        }
    }

    private func layoutOption(_ style: CarPlayBrowseStyle, columns: Int, title: String) -> some View {
        let selected = block.style == style && (style == .list || (block.columns == columns && block.rowsPerPage == columns))
        return Button {
            model.update(block.id) { $0.style = style; if columns > 1 { $0.columns = columns; $0.rowsPerPage = columns } }
        } label: {
            VStack(spacing: 7) {
                CarPlayLayoutGlyph(columns: columns, rows: columns == 2 ? 2 : 3, selected: selected).frame(height: 34)
                Text(LocalizedStringKey(title)).font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? CarPlayEditorTheme.accentText : CarPlayEditorTheme.secondary)
            }.padding(9).frame(maxWidth: .infinity)
                .background(selected ? CarPlayEditorTheme.accent.opacity(0.12) : CarPlayEditorTheme.surface, in: RoundedRectangle(cornerRadius: 11))
                .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? CarPlayEditorTheme.accent : CarPlayEditorTheme.border, lineWidth: selected ? 1.5 : 1) }
        }.buttonStyle(.plain).accessibilityIdentifier("carplay.layout.\(columns)")
    }

    private var itemCount: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("carplay_item_count")
                Spacer()
                Text("\(block.itemLimit) " + String(localized: "carplay_items_unit"))
                    .font(.system(size: 14, weight: .semibold)).monospacedDigit()
            }
            Slider(value: Binding(get: { Double(block.itemLimit) }, set: { value in model.update(block.id) { $0.itemLimit = Int(value) } }), in: 1...60, step: 1) { active in
                model.continuousChange(active)
            }.tint(CarPlayEditorTheme.accent).accessibilityLabel("carplay_item_count").accessibilityIdentifier("carplay.itemLimit")
            Text(String(format: String(localized: "carplay_pages_estimate"), max(1, Int(ceil(Double(block.itemLimit) / Double(block.style == .list ? 5 : block.columns * block.rowsPerPage))))))
                .font(.system(size: 11)).foregroundStyle(CarPlayEditorTheme.muted)
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("carplay_content_sources")
                Spacer()
                Button(action: add) { Label("carplay_add", systemImage: "plus").font(.system(size: 12, weight: .semibold)) }
                    .disabled(block.usesCustomContent && block.items.count >= 60)
            }
            if items.isEmpty {
                Button(action: add) {
                    Label("carplay_add_content", systemImage: "plus.circle").font(.system(size: 13))
                        .frame(maxWidth: .infinity, minHeight: 44).background(CarPlayEditorTheme.surface, in: RoundedRectangle(cornerRadius: 11))
                }.buttonStyle(.plain)
            }
            ForEach(items) { item in
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal").font(.system(size: 12)).foregroundStyle(CarPlayEditorTheme.muted)
                        .frame(width: 20, height: 34)
                        .draggable("carplay-source:" + item.id)
                    CarPlayPreviewArtwork(item: item, pixelSize: 88).frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(.system(size: 13)).lineLimit(1)
                        if let subtitle = item.subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(CarPlayEditorTheme.secondary).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                    Button { model.removeContent(item, from: block.id, resolved: items) } label: {
                        Image(systemName: "minus.circle").font(.system(size: 16)).foregroundStyle(CarPlayEditorTheme.muted).frame(width: 30, height: 34)
                    }.accessibilityLabel("carplay_remove_content")
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(CarPlayEditorTheme.surface, in: RoundedRectangle(cornerRadius: 11))
                .dropDestination(for: String.self) { values, _ in
                    guard let value = values.first, value.hasPrefix("carplay-source:") else { return false }
                    let source = String(value.dropFirst("carplay-source:".count))
                    guard source != item.id, items.contains(where: { $0.id == source }) else { return false }
                    var accepted = false
                    model.change { configuration in
                        var blocks = configuration.blocks
                        guard let index = blocks.firstIndex(where: { $0.id == block.id }) else { return }
                        if !blocks[index].usesCustomContent && blocks[index].kind != .custom {
                            blocks[index].items = Array(items.compactMap(\.layoutItem).prefix(60))
                        }
                        blocks[index].usesCustomContent = true
                        configuration.blocks = blocks
                        accepted = configuration.moveItem(source, from: block.id, to: block.id, before: item.id)
                    }
                    return accepted
                }
            }
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.system(size: 12)).foregroundStyle(CarPlayEditorTheme.secondary)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CarPlayLayoutBlock, Value>) -> Binding<Value> {
        Binding(get: { model.configuration.blocks.first { $0.id == block.id }?[keyPath: keyPath] ?? block[keyPath: keyPath] },
                set: { value in model.update(block.id) { $0[keyPath: keyPath] = value } })
    }
}
#endif
