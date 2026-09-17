// ProfileSettingsView
//
// Settings ▸ Profile (GitHub #46 / G34) — the identity half of the account.
//
// Until this pane existed **you could not edit your own display name or bio from
// the macOS app at all**, even though `UpdateUserRequest` had carried
// `displayName`, `bio` and `theme` since it was written and nothing called them.
//
// Three things here are the result of a probe rather than a guess, and each is
// noted where it bites:
//
//  - **Theme is unvalidated server-side.** The picker offers three values and
//    also surfaces whatever the account actually holds, so an unrecognised value
//    is preserved rather than silently rewritten.
//  - **The message cap is the account's, not the platform's.** The pane shows
//    both numbers, because the account range (1–10000) reaches past the platform
//    ceiling (5000) and the composer honours the lower one.
//  - **A published profile location cannot be cleared through any route.** So it
//    is shown and not editable, with the reason stated — see GitHub #57 / #91.
//
// Pure SwiftUI; the file picker is SwiftUI's `.fileImporter`, no AppKit panel.
// Per Decision 0003 this view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain
import UniformTypeIdentifiers

struct ProfileSettingsView: View {

    @Environment(\.appEnvironment) private var environment
    @State private var viewModel: ProfileSettingsViewModel?
    @State private var isImportingAvatar = false

    var body: some View {
        Form {
            if let viewModel {
                identitySection(viewModel)
                avatarSection(viewModel)
                appearanceSection(viewModel)
                composingSection(viewModel)
                locationSection(viewModel)
                securitySection(viewModel)
                statusSection(viewModel)
            }
        }
        .formStyle(.grouped)
        .task {
            guard viewModel == nil, let environment else { return }
            let model = ProfileSettingsViewModel(
                userService: environment.userService,
                contentLimits: environment.contentLimits,
                currentUserStore: environment.currentUserStore
            )
            viewModel = model
            await model.load()
        }
    }

    // MARK: - Identity

    @ViewBuilder
    private func identitySection(_ viewModel: ProfileSettingsViewModel) -> some View {
        Section("Profile") {
            LabeledContent("Display name") {
                TextField("", text: Binding(
                    get: { viewModel.settings.displayName },
                    set: { viewModel.settings.displayName = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
            Text("How you appear to others. Leave it empty to use your username.")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Bio")
                TextEditor(text: Binding(
                    get: { viewModel.settings.bio },
                    set: { viewModel.settings.bio = $0 }
                ))
                .font(.ilBody())
                .frame(minHeight: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: ILMetric.radiusSm)
                        .stroke(Color.secondary.opacity(0.3))
                )
                HStack {
                    Text("Shown on your public profile.")
                    Spacer()
                    Text("\(viewModel.settings.bio.count)/\(ProfileSettings.bioLengthLimit)")
                        .monospacedDigit()
                        .foregroundStyle(
                            viewModel.settings.bio.count > ProfileSettings.bioLengthLimit
                                ? Color.red : Color.secondary
                        )
                }
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Avatar

    @ViewBuilder
    private func avatarSection(_ viewModel: ProfileSettingsViewModel) -> some View {
        Section("Avatar") {
            HStack(spacing: 12) {
                if let url = viewModel.settings.avatarURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView().controlSize(.small)
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .accessibilityLabel("Current avatar")
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.ilDisplay(40))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("No avatar set")
                }
                // Both halves the web offers: a file and a URL.
                Button("Choose File…") { isImportingAvatar = true }
                    .disabled(viewModel.isUpdatingAvatar)
                if viewModel.isUpdatingAvatar {
                    ProgressView().controlSize(.small)
                }
            }

            LabeledContent("From a URL") {
                HStack(spacing: 6) {
                    TextField("https://…", text: Binding(
                        get: { viewModel.avatarURLInput },
                        set: { viewModel.avatarURLInput = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Button("Set") {
                        Task { await viewModel.setAvatarFromURL() }
                    }
                    .disabled(
                        viewModel.isUpdatingAvatar
                            || viewModel.avatarURLInput.trimmingCharacters(in: .whitespaces).isEmpty
                    )
                }
            }
        }
        .fileImporter(
            isPresented: $isImportingAvatar,
            allowedContentTypes: [.png, .jpeg, .gif, .webP]
        ) { result in
            guard case .success(let url) = result else { return }
            Task { await importAvatar(from: url, into: viewModel) }
        }
    }

    /// Reads the picked file and hands the bytes to the view model.
    ///
    /// The security-scoped bookmark dance is required for a sandboxed app: the
    /// URL `fileImporter` returns is only readable between `startAccessing…` and
    /// `stopAccessing…`, and skipping it fails at runtime in a signed build
    /// while working fine in a debug one.
    private func importAvatar(from url: URL, into viewModel: ProfileSettingsViewModel) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        await viewModel.uploadAvatar(imageData: data, contentType: contentType)
    }

    // MARK: - Appearance

    @ViewBuilder
    private func appearanceSection(_ viewModel: ProfileSettingsViewModel) -> some View {
        Section("Appearance") {
            Picker("Theme", selection: Binding(
                get: { viewModel.settings.theme },
                set: { viewModel.settings.theme = $0 }
            )) {
                ForEach(viewModel.themeOptions, id: \.self) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            Text("Your theme is stored on your account and applies on the web too. The Mac app follows your system appearance.")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Composing

    @ViewBuilder
    private func composingSection(_ viewModel: ProfileSettingsViewModel) -> some View {
        Section("Composing") {
            Stepper(
                value: Binding(
                    get: { viewModel.settings.maxMessageLength },
                    set: { viewModel.settings.maxMessageLength = $0 }
                ),
                in: ProfileSettings.maxMessageLengthRange,
                step: 50
            ) {
                LabeledContent("Maximum message length") {
                    Text(viewModel.settings.maxMessageLength.formatted())
                        .monospacedDigit()
                }
            }
            // Both numbers, named. Showing only the account's would be a number
            // the composer does not honour when it sits above the ceiling.
            VStack(alignment: .leading, spacing: 2) {
                Text("Your own limit. InterlinedList also caps messages at \(viewModel.limits.messageMaxContentLength.formatted()) characters.")
                if viewModel.accountCapExceedsPlatform {
                    Text("Your limit is above the platform cap, so the composer uses \(viewModel.effectiveMessageLength.formatted()).")
                        .foregroundStyle(.orange)
                }
            }
            .font(.ilMono(10))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Profile location (read-only — GitHub #57 / #91)

    @ViewBuilder
    private func locationSection(_ viewModel: ProfileSettingsViewModel) -> some View {
        Section("Profile location") {
            if let location = viewModel.settings.location {
                LabeledContent("Coordinates") {
                    Text(location.displayText).monospacedDigit()
                }
                Text("This location is published on your public profile.")
                    .font(.ilMono(10))
                    .foregroundStyle(.orange)
                Text("It can't be changed or removed from this app: InterlinedList has no route that clears a profile location — every form of \"unset\" is rejected. Tracked as issue #91.")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
            } else {
                Text("No location is published on your profile.")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                Text("Setting one isn't offered here yet. A location set through InterlinedList can't currently be removed again, so this app doesn't give you a way to publish one — see issue #91.")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Security

    @ViewBuilder
    private func securitySection(_ viewModel: ProfileSettingsViewModel) -> some View {
        Section("Password") {
            Button("Send password reset email") {
                Task { await viewModel.requestPasswordReset() }
            }
            Text("InterlinedList doesn't offer a change-password form — you reset your password by email. We'll send a link to the address on your account.")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Save / status

    @ViewBuilder
    private func statusSection(_ viewModel: ProfileSettingsViewModel) -> some View {
        Section {
            HStack(spacing: 8) {
                Button("Save") {
                    Task { await viewModel.save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.hasChanges || viewModel.isSaving)

                Button("Revert") { viewModel.revert() }
                    .disabled(!viewModel.hasChanges || viewModel.isSaving)

                if viewModel.isSaving || viewModel.isLoading {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                if let confirmation = viewModel.confirmation {
                    Text(confirmation)
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                }
            }
            if let error = viewModel.error {
                Text(error.localizedDescription)
                    .font(.ilMono(10))
                    .foregroundStyle(.orange)
            }
        }
    }
}
