// ComposerWindowView
//
// The dedicated composer window opened via ⌘N or the File → New Post
// menu command (PLAN.md §5 — "Composer: separate `Window` scene, ⌘N
// anywhere, ⌘↩ to publish"). M2 surface: a plain-text body editor, a
// tag-token input, a visibility segment, and a publish button. M6 adds
// the subscriber-gated media / scheduled / cross-post controls
// (PLAN.md §6 M6) — rendered for new posts only, and disabled with an
// upsell hint for non-subscribers (never "enabled but broken").
//
// Media picking is SwiftUI-only (Decision 0005): `.fileImporter` +
// `.dropDestination` to add files, `AsyncImage(url:)` for the thumbnail
// strip on local file URLs. No AppKit (`NSOpenPanel` / `Image(nsImage:)`).
//
// All business logic lives in `ComposerViewModel`; this view binds
// observable state to controls and dismisses itself when `didFinish`
// flips true.

import SwiftUI
import UniformTypeIdentifiers
import InterlinedDomain

struct ComposerWindowView: View {

    /// The mode the window opens in. `.newPost` for a fresh draft,
    /// `.edit(...)` when reopened to edit an existing message.
    let mode: ComposerMode

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ComposerViewModel?

    /// Controls the `.fileImporter` sheet for picking media.
    @State private var isImporterPresented = false

    var body: some View {
        Group {
            if let viewModel {
                composerBody(viewModel: viewModel)
            } else {
                unconfiguredState
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .task {
            if viewModel == nil, let environment {
                viewModel = ComposerViewModel(
                    messages: environment.messages,
                    eventBus: environment.composerEventBus,
                    mode: mode,
                    // UI gate computed live from the current user (Deliverable
                    // B): a subscriber sees the M6 controls enabled, a free /
                    // signed-out account sees them disabled with an upsell.
                    entitlements: environment.liveEntitlements,
                    // PLAN.md §8 — a gated 403 mid-flow re-fetches the
                    // customerStatus so the composer re-gates.
                    onSubscriberLapse: { await environment.refreshEntitlements() }
                )
            }
        }
        .onChange(of: viewModel?.didFinish) { _, finished in
            if finished == true { dismiss() }
        }
    }

    // MARK: - Body

    @ViewBuilder
    private func composerBody(viewModel: ComposerViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Body editor — Markdown is just a body string here (no
                // toolbar, no preview). `TextEditor` gives us a native
                // multi-line plain-text field with macOS-standard
                // affordances (find/replace, system spellcheck).
                bodyEditor(viewModel: viewModel)
                    .frame(minHeight: 160)

                // Tag input. Comma- or space-separated tokens — the view
                // model normalises on submit.
                tagsField(viewModel: viewModel)

                visibilityPicker(viewModel: viewModel)

                // M6 — subscriber-gated controls, new posts only.
                if viewModel.showsSubscriberControls {
                    Divider()
                    if !viewModel.canUseSubscriberFeatures {
                        upsellHint
                    }
                    mediaSection(viewModel: viewModel)
                    scheduleSection(viewModel: viewModel)
                    crossPostSection(viewModel: viewModel)
                }

                if let error = viewModel.error {
                    errorBanner(error: error)
                }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            footer(viewModel: viewModel)
                .padding(16)
                .background(ILColor.surface2)
        }
        .navigationTitle(mode.windowTitle)
        // SwiftUI-only file picking (Decision 0005 — no NSOpenPanel).
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.image, .movie],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                viewModel.addAttachments(urls: urls)
            }
        }
        // Drag-and-drop of file URLs onto the whole composer body.
        .dropDestination(for: URL.self) { urls, _ in
            viewModel.addAttachments(urls: urls)
            return true
        }
    }

    // MARK: - Upsell

    private var upsellHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text("Media, scheduling, and cross-posting are available with a subscription.")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(8)
        .background(ILColor.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: ILMetric.radiusSm))
        .accessibilityLabel("Subscriber features require a subscription")
    }

    // MARK: - M6 sections

    @ViewBuilder
    private func mediaSection(viewModel: ComposerViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Media")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    isImporterPresented = true
                } label: {
                    Label("Add", systemImage: "photo.badge.plus")
                }
                .controlSize(.small)
                .disabled(!viewModel.canUseSubscriberFeatures)
            }

            if viewModel.attachments.isEmpty {
                Text(viewModel.canUseSubscriberFeatures
                     ? "Drop images or videos here, or use Add."
                     : "Attaching media requires a subscription.")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                thumbnailStrip(viewModel: viewModel)
            }
        }
        .help(viewModel.canUseSubscriberFeatures
              ? "Attach images or videos to your post."
              : "Attaching media requires an active subscription.")
    }

    @ViewBuilder
    private func thumbnailStrip(viewModel: ComposerViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        // SwiftUI-only thumbnail via AsyncImage on the local
                        // file URL (Decision 0005 — no Image(nsImage:)).
                        Group {
                            if attachment.kind == .image {
                                AsyncImage(url: attachment.url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().scaledToFill()
                                    default:
                                        placeholderTile(systemImage: "photo")
                                    }
                                }
                            } else {
                                placeholderTile(systemImage: "video")
                            }
                        }
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: ILMetric.radiusMd))
                        .overlay(
                            RoundedRectangle(cornerRadius: ILMetric.radiusMd)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        )

                        Button {
                            viewModel.removeAttachment(id: attachment.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .padding(2)
                        .accessibilityLabel("Remove attachment")
                    }
                }
            }
        }
    }

    private func placeholderTile(systemImage: String) -> some View {
        ZStack {
            Color.secondary.opacity(0.12)
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func scheduleSection(viewModel: ComposerViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { viewModel.isScheduled },
                set: { viewModel.isScheduled = $0 }
            )) {
                Text("Schedule for later")
            }
            .disabled(!viewModel.canUseSubscriberFeatures)
            .help(viewModel.canUseSubscriberFeatures
                  ? "Publish this post at a future time."
                  : "Scheduling posts requires an active subscription.")

            if viewModel.isScheduled {
                DatePicker(
                    "Publish at",
                    selection: Binding(
                        get: { viewModel.scheduledAt },
                        set: { viewModel.scheduledAt = $0 }
                    ),
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .disabled(!viewModel.canUseSubscriberFeatures)
            }
        }
    }

    @ViewBuilder
    private func crossPostSection(viewModel: ComposerViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cross-post")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)

            Toggle(isOn: Binding(
                get: { viewModel.crossPostToMastodon },
                set: { viewModel.crossPostToMastodon = $0 }
            )) { Text("Mastodon") }
                .disabled(!viewModel.canUseSubscriberFeatures)

            if viewModel.crossPostToMastodon {
                TextField("Provider IDs (comma- or space-separated)", text: Binding(
                    get: { viewModel.mastodonProviderIdsInput },
                    set: { viewModel.mastodonProviderIdsInput = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(!viewModel.canUseSubscriberFeatures)
                .accessibilityLabel("Mastodon provider IDs")
            }

            Toggle(isOn: Binding(
                get: { viewModel.crossPostToBluesky },
                set: { viewModel.crossPostToBluesky = $0 }
            )) { Text("Bluesky") }
                .disabled(!viewModel.canUseSubscriberFeatures)

            Toggle(isOn: Binding(
                get: { viewModel.crossPostToLinkedIn },
                set: { viewModel.crossPostToLinkedIn = $0 }
            )) { Text("LinkedIn") }
                .disabled(!viewModel.canUseSubscriberFeatures)
        }
        .help(viewModel.canUseSubscriberFeatures
              ? "Also publish to your linked social accounts."
              : "Cross-posting requires an active subscription.")
    }

    @ViewBuilder
    private func bodyEditor(viewModel: ComposerViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Body")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
            TextEditor(text: Binding(
                get: { viewModel.body },
                set: { viewModel.body = $0 }
            ))
            .font(.ilBody())
            .scrollContentBackground(.hidden)
            .background(ILColor.surface)
            .overlay(
                RoundedRectangle(cornerRadius: ILMetric.radiusSm)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
            .accessibilityLabel("Message body")
        }
    }

    @ViewBuilder
    private func tagsField(viewModel: ComposerViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tags")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
            TextField("Comma- or space-separated", text: Binding(
                get: { viewModel.tagsInput },
                set: { viewModel.tagsInput = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Tags")
        }
    }

    @ViewBuilder
    private func visibilityPicker(viewModel: ComposerViewModel) -> some View {
        Picker("Visibility", selection: Binding(
            get: { viewModel.visibility },
            set: { viewModel.setVisibility($0) }
        )) {
            Text("Public").tag(Visibility.public)
            Text("Private").tag(Visibility.private)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 280)
        .accessibilityLabel("Post visibility")
    }

    @ViewBuilder
    private func errorBanner(error: Error) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.accentColor)
            Text(error.localizedDescription)
                .font(.ilSubtitle())
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(8)
        .background(ILColor.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: ILMetric.radiusSm))
    }

    @ViewBuilder
    private func footer(viewModel: ComposerViewModel) -> some View {
        HStack {
            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if viewModel.isSubmitting {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 8)
            }

            Button(viewModel.publishButtonLabel) {
                Task { await viewModel.submit() }
            }
            .buttonStyle(.borderedProminent)
            // PLAN.md §5: "⌘↩ to publish".
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!viewModel.isPublishable || viewModel.isSubmitting)
        }
    }

    private var unconfiguredState: some View {
        // Reached only if the scene wasn't wired through `AppEnvironment`,
        // which is a programmer error rather than a runtime one — keep
        // the message diagnostic rather than user-facing.
        VStack(spacing: 8) {
            Image(systemName: "wrench.adjustable")
                .font(.ilDisplay(36))
                .foregroundStyle(.secondary)
            Text("Composer unavailable")
                .font(.ilSubtitle())
            Text("AppEnvironment is not injected into the view tree.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
