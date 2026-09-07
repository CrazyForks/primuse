#if os(macOS)
import SwiftUI

/// Keep high-frequency volume observation out of the artwork and lyrics views.
struct PMVolumeSymbol: View {
    @Environment(AudioEngine.self) private var engine

    var body: some View {
        Image(systemName: symbol)
    }

    private var symbol: String {
        let volume = engine.volume
        if volume <= 0.001 { return "speaker.slash.fill" }
        if volume < 0.4 { return "speaker.wave.1.fill" }
        if volume < 0.75 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

struct PMVolumePercentage: View {
    @Environment(AudioEngine.self) private var engine

    var body: some View {
        Text(verbatim: "\(Int((engine.volume * 100).rounded()))")
    }
}

struct PMPlaybackVolumeSlider: View {
    @Environment(AudioPlayerService.self) private var player
    @Environment(AudioEngine.self) private var engine
    @State private var isEditing = false

    private var isEnabled: Bool {
        player.isLiveRadio || player.playbackSettings.outputMode == .effects
    }

    var body: some View {
        PMVolumeSlider(
            value: Binding(
                get: { Double(engine.volume) },
                set: { player.setPlaybackVolume(Float($0), persist: !isEditing) }
            ),
            isEnabled: isEnabled,
            accessibilityHelp: isEnabled ? nil : String(localized: "volume_high_fidelity_system_hint"),
            onEditingChanged: { editing in
                isEditing = editing
                if !editing { engine.persistVolume() }
            }
        )
        .help(isEnabled ? Text("volume") : Text("volume_high_fidelity_system_hint"))
        .transaction {
            $0.animation = nil
            $0.disablesAnimations = true
        }
    }
}
#endif
