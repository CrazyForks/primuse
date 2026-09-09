import SwiftUI

#if os(iOS)
struct ImmersiveLibraryDetailScrollView<Header: View, Content: View>: View {
    private let header: (CGFloat) -> Header
    private let content: Content

    init(
        @ViewBuilder header: @escaping (CGFloat) -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.header = header
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    header(geometry.safeAreaInsets.top)
                    content
                }
                // Horizontal artwork shelves must not determine the page width.
                .frame(width: geometry.size.width)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
#endif

struct LibraryDetailActionButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var emphasized = false
    var onArtwork = true
    var fillsWidth = false
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(emphasized || onArtwork ? Color.white : Color.accentColor)
                .padding(.horizontal, 20)
                .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 48)
                .background(
                    emphasized ? Color.accentColor
                        : (onArtwork ? Color.white.opacity(0.18) : Color.accentColor.opacity(0.12)),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

struct MediaDetailActionBar: View {
    let canPlay: Bool
    let canShuffle: Bool
    let playAction: () -> Void
    let shuffleAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: playAction) {
                Label("play_all", systemImage: "play.fill")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canPlay)

            Button(action: shuffleAction) {
                Label("shuffle", systemImage: "shuffle")
                    .frame(minWidth: 112)
            }
            .buttonStyle(.bordered)
            .disabled(!canShuffle)

            #if os(macOS)
            // macOS 详情区按钮靠左,不撑满。
            Spacer(minLength: 0)
            #endif
        }
        .controlSize(.regular)
        .labelStyle(.titleAndIcon)
        #if os(iOS)
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        #endif
    }
}

struct LibraryReviewSection: View {
    @Environment(MusicLibrary.self) private var library
    @AppStorage(LibraryReviewPreferences.enabledKey) private var isEnabled = false

    let subject: LibraryReviewSubject
    var compact = false
    var onArtwork = false

    @State private var showsCommentEditor = false

    private var review: LibraryReview? {
        library.libraryReview(for: subject)
    }

    var body: some View {
        if isEnabled {
            VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                if !compact {
                    Label("library_review_title", systemImage: "star.bubble")
                        .font(.headline)
                        .foregroundStyle(onArtwork ? Color.white : Color.primary)
                }

                HStack(spacing: compact ? 5 : 8) {
                    LibraryReviewRatingPicker(
                        rating: review?.rating,
                        foregroundStyle: onArtwork ? .white : .yellow
                    ) { rating in
                        library.updateLibraryReview(
                            for: subject,
                            rating: rating == review?.rating ? nil : rating,
                            comment: review?.comment ?? ""
                        )
                    }

                    Spacer(minLength: 8)

                    Button {
                        showsCommentEditor = true
                    } label: {
                        if compact {
                            Image(
                                systemName: review?.comment.isEmpty == false
                                    ? "text.bubble.fill"
                                    : "text.bubble"
                            )
                        } else {
                            Label(
                                review?.comment.isEmpty == false
                                    ? "library_review_edit_comment"
                                    : "library_review_add_comment",
                                systemImage: review?.comment.isEmpty == false
                                    ? "text.bubble.fill"
                                    : "text.bubble"
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(onArtwork ? Color.white : Color.accentColor)
                    .accessibilityHint(Text("library_review_comment_hint"))
                }

                if let comment = review?.comment, !comment.isEmpty {
                    Text(verbatim: comment)
                        .font(compact ? .caption : .subheadline)
                        .foregroundStyle(onArtwork ? Color.white.opacity(0.78) : Color.secondary)
                        .lineLimit(compact ? 2 : 4)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentShape(Rectangle())
                        .onTapGesture { showsCommentEditor = true }
                        .accessibilityAddTraits(.isButton)
                }
            }
            .padding(compact ? 10 : 14)
            .background(reviewBackground, in: RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous)
                    .strokeBorder(onArtwork ? Color.white.opacity(0.14) : Color.primary.opacity(0.06), lineWidth: 0.5)
            }
            .sheet(isPresented: $showsCommentEditor) {
                LibraryReviewCommentEditor(subject: subject)
            }
        }
    }

    private var reviewBackground: AnyShapeStyle {
        if onArtwork {
            return AnyShapeStyle(.ultraThinMaterial)
        }
        #if os(iOS)
        return AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
        #else
        return AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
        #endif
    }
}

struct LibraryReviewRatingPicker: View {
    let rating: Int?
    let foregroundStyle: Color
    var symbolSize: CGFloat = 17
    var buttonSize: CGFloat = 30
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    onSelect(value)
                } label: {
                    Image(systemName: value <= (rating ?? 0) ? "star.fill" : "star")
                        .font(.system(size: symbolSize, weight: .semibold))
                        .foregroundStyle(
                            value <= (rating ?? 0)
                                ? foregroundStyle
                                : foregroundStyle.opacity(0.35)
                        )
                        .frame(width: buttonSize, height: buttonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text(
                        String(
                            format: String(localized: "library_review_star_format"),
                            value
                        )
                    )
                )
                .accessibilityAddTraits(value == rating ? .isSelected : [])
            }
        }
    }
}

private struct LibraryReviewCommentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MusicLibrary.self) private var library

    let subject: LibraryReviewSubject
    @State private var draft = ""

    private var currentReview: LibraryReview? {
        library.libraryReview(for: subject)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $draft)
                        .frame(minHeight: 150)
                        .onChange(of: draft) { _, value in
                            if value.count > LibraryReviewPreferences.maximumCommentLength {
                                draft = String(value.prefix(LibraryReviewPreferences.maximumCommentLength))
                            }
                        }
                } footer: {
                    Text(verbatim:
                        "\(draft.count)/\(LibraryReviewPreferences.maximumCommentLength)"
                    )
                    .monospacedDigit()
                }
            }
            .navigationTitle("library_review_comment_title")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save") {
                        library.updateLibraryReview(
                            for: subject,
                            rating: currentReview?.rating,
                            comment: draft
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { draft = currentReview?.comment ?? "" }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 320)
        #endif
    }
}
