// AccountSettingsView
//
// The Settings > "Account" pane (PLAN.md §5 — M7 account management:
// avatar, email change, account deletion). Replaces the M6 stub in
// `SettingsRootView`.
//
// Three sections:
//   1. "Avatar"  — current avatar display + file-importer picker.
//   2. "Email"   — read-only current address with verified badge;
//                  text field + send-verification button.
//   3. "Danger Zone" — destructive delete-account flow with a
//                      password-confirmation alert.
//
// Per decision 0003 the view consumes only `InterlinedDomain`.
// SwiftUI-only — no AppKit.

import SwiftUI
import InterlinedDomain
import UniformTypeIdentifiers

struct AccountSettingsView: View {

    @Environment(\.appEnvironment) private var environment

    @State private var viewModel: AccountViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard viewModel == nil, let environment else { return }
            viewModel = AccountViewModel(
                userService: environment.userService,
                session: environment.session,
                currentUserStore: environment.currentUserStore
            )
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(viewModel: AccountViewModel) -> some View {
        @Bindable var vm = viewModel
        Form {
            // Error banner — shown above everything else when a mutation fails.
            if let errorMessage = vm.errorMessage {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(ILColor.amber)
                        Text(errorMessage)
                            .font(.ilBody())
                            .foregroundStyle(ILColor.text)
                    }
                    .padding(.vertical, 2)
                }
            }

            // MARK: Section — Avatar
            Section("Avatar") {
                HStack(spacing: 16) {
                    avatarImage(for: vm.currentUser?.avatarURL)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vm.currentUser?.displayName ?? "–")
                            .font(.ilBodyMedium())
                        Text("@\(vm.currentUser?.username ?? "–")")
                            .font(.ilMono(10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        vm.avatarPickerVisible = true
                    } label: {
                        Label("Change Photo…", systemImage: "photo.badge.plus")
                    }
                    .disabled(vm.isLoadingAvatar)
                    if vm.isLoadingAvatar {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Uploading avatar")
                    }
                }
                .padding(.vertical, 4)
            }
            .fileImporter(
                isPresented: $vm.avatarPickerVisible,
                allowedContentTypes: [.jpeg, .png]
            ) { result in
                guard let url = try? result.get() else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { return }
                let contentType = url.pathExtension.lowercased() == "png"
                    ? "image/png" : "image/jpeg"
                Task { await vm.pickAndUploadAvatar(data: data, contentType: contentType) }
            }

            // MARK: Section — Email
            Section("Email") {
                HStack {
                    Text("Current address")
                        .font(.ilBody())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(vm.currentUser?.email ?? "–")
                        .font(.ilBodyMedium())
                    if let isVerified = vm.currentUser.map(\.isEmailVerified) {
                        Text(isVerified ? "(Verified)" : "(Unverified)")
                            .font(.ilMono(9))
                            .foregroundStyle(isVerified ? ILColor.primary : ILColor.amber)
                    }
                }

                TextField("New email address", text: $vm.newEmail)
                    .font(.ilBody())
                    .textFieldStyle(.roundedBorder)

                HStack {
                    if vm.emailChangeSuccess {
                        Label("Verification email sent!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(ILColor.primary)
                            .font(.ilBody())
                    }
                    Spacer()
                    Button {
                        Task { await vm.requestEmailChange() }
                    } label: {
                        if vm.isLoadingEmailChange {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Send Verification Email")
                        }
                    }
                    .accessibilityLabel(vm.isLoadingEmailChange ? "Sending verification email" : "Send Verification Email")
                    .disabled(vm.isLoadingEmailChange || vm.newEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            // MARK: Section — Session
            Section("Session") {
                Button {
                    Task { await vm.signOut() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            // MARK: Section — Danger Zone
            Section("Danger Zone") {
                Button(role: .destructive) {
                    vm.showDeleteConfirm = true
                } label: {
                    Label("Delete Account…", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .alert("Delete account?", isPresented: $vm.showDeleteConfirm) {
            SecureField("Password", text: $vm.confirmDeletePassword)
            Button("Permanently Delete", role: .destructive) {
                Task { await vm.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {
                vm.confirmDeletePassword = ""
            }
        } message: {
            Text("Enter your password to permanently delete your account. This action cannot be undone.")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func avatarImage(for url: URL?) -> some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color(ILColor.surface3)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())
            .accessibilityHidden(true)
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: 64, height: 64)
                .foregroundStyle(ILColor.primary)
                .accessibilityHidden(true)
        }
    }
}
