#if os(tvOS)
import SwiftUI
import PrimuseKit
import UIKit

struct TVLibraryReviewControl: View {
    @Environment(TVStore.self) private var store
    @AppStorage(LibraryReviewPreferences.enabledKey) private var isEnabled = false

    let subject: LibraryReviewSubject
    @State private var showsCommentEditor = false

    private var review: LibraryReview? {
        store.library.libraryReview(for: subject)
    }

    var body: some View {
        if isEnabled {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ForEach(1...5, id: \.self) { value in
                        Button {
                            store.library.updateLibraryReview(
                                for: subject,
                                rating: value == review?.rating ? nil : value,
                                comment: review?.comment ?? ""
                            )
                        } label: {
                            Image(systemName: value <= (review?.rating ?? 0) ? "star.fill" : "star")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(value <= (review?.rating ?? 0) ? TVColor.warn : TVColor.textMuted)
                                .frame(width: 54, height: 54)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(
                            Text(
                                String(
                                    format: String(localized: "library_review_star_format"),
                                    value
                                )
                            )
                        )
                    }

                    Button {
                        showsCommentEditor = true
                    } label: {
                        Image(systemName: review?.comment.isEmpty == false ? "text.bubble.fill" : "text.bubble")
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 54, height: 54)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(
                        Text(
                            review?.comment.isEmpty == false
                                ? "library_review_edit_comment"
                                : "library_review_add_comment"
                        )
                    )
                }

                if let comment = review?.comment, !comment.isEmpty {
                    Text(verbatim: comment)
                        .font(.system(size: 18))
                        .foregroundStyle(TVColor.textMuted)
                        .lineLimit(2)
                        .frame(maxWidth: 560, alignment: .leading)
                }
            }
            .fullScreenCover(isPresented: $showsCommentEditor) {
                TVLibraryReviewCommentEditor(subject: subject)
                    .environment(store)
            }
        }
    }
}

private struct TVLibraryReviewCommentEditor: View {
    @Environment(TVStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let subject: LibraryReviewSubject
    @State private var draft = ""

    private var currentReview: LibraryReview? {
        store.library.libraryReview(for: subject)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("library_review_comment_title", text: $draft)
                        .frame(minHeight: 90)
                        .onChange(of: draft) { _, value in
                            if value.count > LibraryReviewPreferences.maximumCommentLength {
                                draft = String(value.prefix(LibraryReviewPreferences.maximumCommentLength))
                            }
                        }
                } footer: {
                    Text(verbatim: "\(draft.count)/\(LibraryReviewPreferences.maximumCommentLength)")
                }
            }
            .navigationTitle("library_review_comment_title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save") {
                        store.library.updateLibraryReview(
                            for: subject,
                            rating: currentReview?.rating,
                            comment: draft
                        )
                        dismiss()
                    }
                }
            }
            .onAppear { draft = currentReview?.comment ?? "" }
        }
    }
}

// MARK: - 横向区块(Apple Music tvOS shelf 风)

struct TVRow<Content: View>: View {
    let label: String
    var sub: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(label).tvFont(.sectionTitle).foregroundStyle(TVColor.text)
                if let sub { Text(sub).tvFont(.caption).foregroundStyle(TVColor.textFaint) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 28) { content() }
                    // 为首尾卡片的焦点描边和放大保留空间。
                    .padding(.vertical, 30)
                    .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - 专辑卡片

struct TVAlbumCard: View {
    let album: TVAlbum
    var width: CGFloat = 240
    var titleOverride: String? = nil
    var subtitleOverride: String? = nil
    var action: () -> Void = {}
    @Environment(TVStore.self) private var store

    var body: some View {
        TVFocusButton(ring: false,
                      action: { store.play(album: album); action() }) { focused in
            VStack(alignment: .leading, spacing: 0) {
                TVArtworkView(album: album, size: width)
                    .tvFocusRing(focused, radius: TVRadius.cover, scale: 1.04, lift: 0)
                VStack(alignment: .leading, spacing: 6) {
                    Text(titleOverride ?? album.title)
                        .tvFont(.cardTitle)
                        .foregroundStyle(TVColor.text).lineLimit(2, reservesSpace: true)
                    Text(subtitleOverride ?? album.artist)
                        .tvFont(.caption)
                        .foregroundStyle(TVColor.textFaint).lineLimit(1)
                }
                .padding(.top, 12).padding(.horizontal, 2)
                .frame(width: width, alignment: .leading)
            }
            .frame(width: width, alignment: .leading)
        }
        .accessibilityLabel(Text(titleOverride ?? album.title))
        .accessibilityValue(Text(subtitleOverride ?? album.artist))
    }
}

// MARK: - 歌曲卡片(用所属专辑封面)

struct TVSongCard: View {
    @Environment(TVStore.self) private var store
    let song: TVSong
    var width: CGFloat = 240
    var reason: String? = nil
    var action: () -> Void = {}

    var body: some View {
        let album = store.albumOf(song)
        TVFocusButton(ring: false,
                      action: { store.play(song); action() }) { focused in
            VStack(alignment: .leading, spacing: 0) {
                TVArtworkView(coverKey: album?.id ?? "", artist: album?.artist ?? song.artist,
                              album: album?.title ?? "", songID: song.id, coverRef: song.coverRef,
                              tint: album?.tint ?? TVColor.brand,
                              tint2: album?.tint2 ?? .black, glyph: album?.glyph ?? "♪", size: width)
                    .tvFocusRing(focused, radius: TVRadius.cover, scale: 1.04, lift: 0)
                VStack(alignment: .leading, spacing: 6) {
                    if let reason {
                        Label(reason, systemImage: "sparkles")
                            .tvFont(.caption, weight: .semibold)
                            .foregroundStyle(TVColor.brand)
                            .lineLimit(1, reservesSpace: true)
                            .opacity(reason.isEmpty ? 0 : 1)
                    }
                    Text(song.title).tvFont(.cardTitle)
                        .foregroundStyle(TVColor.text).lineLimit(2, reservesSpace: true)
                    Text(song.artist).tvFont(.caption)
                        .foregroundStyle(TVColor.textFaint).lineLimit(1)
                }
                .padding(.top, 12).padding(.horizontal, 2)
                .frame(width: width, alignment: .leading)
            }
            .frame(width: width, alignment: .leading)
        }
    }
}

// MARK: - 电台卡片

struct TVRadioStationCard: View {
    @Environment(TVStore.self) private var store
    let station: RadioStation
    var width: CGFloat = 220
    var action: () -> Void = {}

    var body: some View {
        TVFocusButton(ring: false,
                      action: {
                          TVSiriMediaInteractionDonor.donate(station: station)
                          store.play(station)
                          action()
                      }) { focused in
            VStack(alignment: .leading, spacing: 0) {
                TVRadioArtworkView(station: station, size: width, radius: TVRadius.cover)
                    .tvFocusRing(focused, radius: TVRadius.cover, scale: 1.04, lift: 0)
                VStack(alignment: .leading, spacing: 6) {
                    Text(station.name)
                        .tvFont(.cardTitle)
                        .foregroundStyle(TVColor.text)
                        .lineLimit(2, reservesSpace: true)
                    Text(station.playbackSubtitle)
                        .tvFont(.caption)
                        .foregroundStyle(TVColor.textFaint)
                        .lineLimit(1)
                }
                .padding(.top, 12)
                .padding(.horizontal, 2)
                .frame(width: width, alignment: .leading)
            }
            .frame(width: width, alignment: .leading)
        }
    }
}

struct TVRadioArtworkView: View {
    let station: RadioStation
    let size: CGFloat
    var radius: CGFloat = TVRadius.cover

    @State private var logo: UIImage?

    private var logoIdentity: Int { station.logoData?.hashValue ?? 0 }

    var body: some View {
        Group {
            if let logo {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFill()
            } else {
                TVRadioPlaceholderArtwork()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(TVColor.cardBorder, lineWidth: 1)
        }
        .task(id: logoIdentity) {
            let identity = logoIdentity
            guard let data = station.logoData else {
                logo = nil
                return
            }
            let decoded = await Task.detached(priority: .utility) {
                UIImage(data: data)
            }.value
            guard !Task.isCancelled, identity == logoIdentity else { return }
            logo = decoded
        }
    }
}

private struct TVRadioPlaceholderArtwork: View {
    var body: some View {
        GeometryReader { proxy in
            let side = max(min(proxy.size.width, proxy.size.height), 1)

            ZStack {
                TVColor.brandSecondary

                LinearGradient(
                    colors: [TVColor.brand.opacity(0.84), TVColor.brand.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .stroke(.white.opacity(0.10), lineWidth: max(1, side * 0.008))
                    .frame(width: side * 0.82, height: side * 0.82)

                Circle()
                    .stroke(.white.opacity(0.14), lineWidth: max(1, side * 0.009))
                    .frame(width: side * 0.58, height: side * 0.58)

                Image(systemName: "radio.fill")
                    .font(.system(size: side * 0.31, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 艺术家卡片(圆形)

struct TVArtistCard: View {
    let artist: TVArtist
    var size: CGFloat = 180
    var action: () -> Void = {}

    var body: some View {
        TVFocusButton(ring: false, action: action) { focused in
            VStack(spacing: 12) {
                TVArtistArtworkView(artist: artist, size: size)
                    .tvFocusRing(focused, radius: size / 2, scale: 1.04, lift: 0)
                Text(artist.name).tvFont(.cardTitle)
                    .foregroundStyle(TVColor.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .frame(width: size + 32)
            }
        }
        .accessibilityLabel(Text(artist.name))
        .accessibilityValue(Text(PMString("ext.tv.search.artistMeta", artist.songCount)))
    }
}

// MARK: - 空态

struct TVEmptyState: View {
    let icon: String
    let title: String
    var subtitle: String = PMString("ext.tv.components.emptySubtitle")
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 80)).foregroundStyle(TVColor.textGhost)
            Text(title).tvFont(.sectionTitle).foregroundStyle(TVColor.text)
            if !subtitle.isEmpty {
                Text(subtitle).tvFont(.caption).foregroundStyle(TVColor.textMuted)
                    .multilineTextAlignment(.center).frame(maxWidth: 720)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 胶囊按钮(播放 / 随机 / 喜欢)

struct TVPillButton: View {
    enum Style { case solid, glass }
    let title: String
    let systemImage: String
    var style: Style = .glass
    var isSelected = false
    var action: () -> Void = {}

    var body: some View {
        TVFocusButton(radius: 14, scale: 1.04, lift: 6, action: action) { _ in
            HStack(spacing: 12) {
                Image(systemName: systemImage).font(.system(size: 22, weight: .semibold))
                Text(title).tvFont(.button, weight: style == .solid ? .bold : .semibold)
                    .lineLimit(1)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .foregroundStyle(style == .solid ? TVColor.onBrand : TVColor.text)
            .background(style == .solid ? AnyShapeStyle(TVColor.brand)
                                        : AnyShapeStyle(TVColor.surfaceStrong))
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

enum TVRemoteTransportCommand: Equatable {
    case togglePlayback
    case nextTrack
    case seek
}

struct TVRemoteTransportModifier: ViewModifier {
    var shortcutsEnabled: Bool
    var onCommand: (TVRemoteTransportCommand) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var assistiveNavigation = UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning

    private var capturesPresses: Bool {
        shortcutsEnabled && isVisible && scenePhase == .active && !assistiveNavigation
    }

    func body(content: Content) -> some View {
        content
            .background {
                TVRemoteTransportBridge(enabled: capturesPresses, onCommand: onCommand)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            .onPlayPauseCommand {
                // The UIKit recognizers arbitrate single/double/long presses.
                // Keep the native single-press route when shortcuts are unavailable.
                if !capturesPresses { onCommand(.togglePlayback) }
            }
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
                refreshAssistiveNavigation()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.switchControlStatusDidChangeNotification)) { _ in
                refreshAssistiveNavigation()
            }
    }

    private func refreshAssistiveNavigation() {
        assistiveNavigation = UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
    }
}

private struct TVRemoteTransportBridge: UIViewRepresentable {
    let enabled: Bool
    let onCommand: (TVRemoteTransportCommand) -> Void

    func makeCoordinator() -> TVRemoteTransportCoordinator { TVRemoteTransportCoordinator() }

    func makeUIView(context: Context) -> TVRemoteTransportAnchor {
        let view = TVRemoteTransportAnchor()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: TVRemoteTransportAnchor, context: Context) {
        context.coordinator.configure(enabled: enabled, onCommand: onCommand)
        view.attachToHostingView()
    }

    static func dismantleUIView(_ view: TVRemoteTransportAnchor, coordinator: TVRemoteTransportCoordinator) {
        coordinator.detach()
    }
}

private final class TVRemoteTransportAnchor: UIView {
    weak var coordinator: TVRemoteTransportCoordinator?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachToHostingView()
    }

    func attachToHostingView() {
        guard window != nil else { coordinator?.detach(); return }
        var responder: UIResponder? = next
        while let current = responder {
            if let controller = current as? UIViewController {
                // The hosting view contains the focused controls. An invisible
                // background view does not receive their remote presses.
                coordinator?.attach(to: controller)
                return
            }
            responder = current.next
        }
    }
}

@MainActor
final class TVRemoteTransportCoordinator: NSObject, UIGestureRecognizerDelegate {
    private(set) var enabled = false
    private weak var controller: UIViewController?
    private var onCommand: (TVRemoteTransportCommand) -> Void = { _ in }
    private(set) lazy var singlePress = UITapGestureRecognizer(target: self, action: #selector(singlePressed))
    private(set) lazy var doublePress = UITapGestureRecognizer(target: self, action: #selector(doublePressed))
    private(set) lazy var longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressed))

    override init() {
        super.init()
        doublePress.numberOfTapsRequired = 2
        longPress.minimumPressDuration = 0.7
        for gesture in recognizers {
            gesture.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]
            gesture.allowedTouchTypes = []
            gesture.delaysTouchesBegan = true
            gesture.cancelsTouchesInView = true
            gesture.delegate = self
            gesture.isEnabled = false
        }
        singlePress.require(toFail: doublePress)
        singlePress.require(toFail: longPress)
        doublePress.require(toFail: longPress)
    }

    private var recognizers: [UIGestureRecognizer] { [singlePress, doublePress, longPress] }

    func configure(enabled: Bool, onCommand: @escaping (TVRemoteTransportCommand) -> Void) {
        self.onCommand = onCommand
        self.enabled = enabled
        for gesture in recognizers { gesture.isEnabled = enabled && controller != nil }
    }

    func attach(to controller: UIViewController) {
        guard self.controller !== controller else { return }
        detach()
        self.controller = controller
        for gesture in recognizers {
            controller.view.addGestureRecognizer(gesture)
            gesture.isEnabled = enabled
        }
    }

    func detach() {
        for gesture in recognizers {
            gesture.isEnabled = false
            gesture.view?.removeGestureRecognizer(gesture)
        }
        controller = nil
    }

    private var canHandleCommand: Bool {
        guard enabled, let controller,
              controller.isViewLoaded, controller.view.window != nil,
              !controller.isBeingDismissed, controller.presentedViewController == nil,
              !UIAccessibility.isVoiceOverRunning, !UIAccessibility.isSwitchControlRunning else { return false }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool {
        canHandleCommand && press.type == .playPause
    }

    func perform(_ command: TVRemoteTransportCommand) {
        guard canHandleCommand else { return }
        onCommand(command)
    }

    @objc private func singlePressed(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        perform(.togglePlayback)
    }

    @objc private func doublePressed(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        perform(.nextTrack)
    }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        perform(.seek)
    }
}
#endif
