// OnboardingView
//
// The sign-in / register / forgot-password window (M7 Onboarding).
// The view is a thin shell over `OnboardingViewModel`: it observes
// state, routes button taps to `submit()` / `switchMode(to:)`, and
// leaves all validation and network logic in the view model.
//
// Layout is fixed at 380 pt wide and pads its content by 32 pt so the
// window chrome looks deliberate on macOS. Height is content-driven.
//
// Per Decision 0003 this file consumes only `InterlinedDomain` and
// the App-layer theme tokens — no `import InterlinedKit`.

import SwiftUI
import InterlinedDomain

struct OnboardingView: View {

    @Environment(\.appEnvironment) private var environment

    /// Lazy view model — created once the environment is available and
    /// held in `@State` so it survives view-tree rebuilds.
    @State private var viewModel: OnboardingViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm: vm)
            } else {
                ProgressView()
                    .frame(width: 380, height: 260)
            }
        }
        .onAppear {
            guard viewModel == nil, let env = environment else { return }
            viewModel = OnboardingViewModel(session: env.session)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(vm: OnboardingViewModel) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                logoSection
                formSection(vm: vm)
                actionSection(vm: vm)
                modeLinks(vm: vm)
            }
            .padding(32)
        }
        .frame(width: 380)
        .background(ILColor.surface)
    }

    // MARK: - Logo

    private var logoSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.indent")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(ILColor.teal)
                .accessibilityHidden(true)

            Text("InterlinedList")
                .font(.ilDisplay(28))
                .foregroundStyle(ILColor.text)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Form fields

    @ViewBuilder
    private func formSection(vm: OnboardingViewModel) -> some View {
        VStack(spacing: 12) {
            // Email — present in all modes
            TextField("Email address", text: Binding(
                get: { vm.email },
                set: { vm.email = $0 }
            ))
            .textContentType(.emailAddress)
            .textFieldStyle(.roundedBorder)
            .disabled(vm.isLoading)

            // Username — register only
            if vm.mode == .register {
                TextField("Username (optional)", text: Binding(
                    get: { vm.username },
                    set: { vm.username = $0 }
                ))
                .textContentType(.username)
                .textFieldStyle(.roundedBorder)
                .disabled(vm.isLoading)
            }

            // Password — sign-in and register
            if vm.mode == .signIn || vm.mode == .register {
                SecureField("Password", text: Binding(
                    get: { vm.password },
                    set: { vm.password = $0 }
                ))
                .textContentType(vm.mode == .register ? .newPassword : .password)
                .textFieldStyle(.roundedBorder)
                .disabled(vm.isLoading)
            }

            // Confirm password — register only
            if vm.mode == .register {
                SecureField("Confirm password", text: Binding(
                    get: { vm.confirmPassword },
                    set: { vm.confirmPassword = $0 }
                ))
                .textContentType(.newPassword)
                .textFieldStyle(.roundedBorder)
                .disabled(vm.isLoading)
            }
        }
    }

    // MARK: - Primary action

    @ViewBuilder
    private func actionSection(vm: OnboardingViewModel) -> some View {
        VStack(spacing: 12) {
            // Forgot-password success banner
            if vm.mode == .forgotPassword && vm.didSendReset {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.badge.checkmark")
                        .foregroundStyle(ILColor.primary)
                    Text("Reset email sent. Check your inbox.")
                        .font(.ilBody())
                        .foregroundStyle(ILColor.textBody)
                }
                .padding(12)
                .background(ILColor.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: ILMetric.radiusMd))
            }

            // Error message
            if let msg = vm.errorMessage {
                Text(msg)
                    .font(.ilBody())
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(ILColor.amber.opacity(0.15), in: Capsule())
            }

            // Primary button + inline progress
            HStack(spacing: 8) {
                Button {
                    Task { await vm.submit() }
                } label: {
                    Text(primaryLabel(for: vm.mode))
                        .font(.ilBodyMedium())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isLoading)

                if vm.isLoading {
                    ProgressView()
                        .scaleEffect(0.75)
                }
            }
        }
    }

    // MARK: - Mode switch links

    @ViewBuilder
    private func modeLinks(vm: OnboardingViewModel) -> some View {
        switch vm.mode {
        case .signIn:
            VStack(spacing: 6) {
                Button("Forgot password?") {
                    vm.switchMode(to: .forgotPassword)
                }
                .buttonStyle(.plain)
                .font(.ilBody())
                .foregroundStyle(ILColor.link)

                Button("Create account") {
                    vm.switchMode(to: .register)
                }
                .buttonStyle(.plain)
                .font(.ilBody())
                .foregroundStyle(ILColor.link)
            }

        case .register:
            Button("Already have an account? Sign in") {
                vm.switchMode(to: .signIn)
            }
            .buttonStyle(.plain)
            .font(.ilBody())
            .foregroundStyle(ILColor.link)

        case .forgotPassword:
            Button("Back to sign in") {
                vm.switchMode(to: .signIn)
            }
            .buttonStyle(.plain)
            .font(.ilBody())
            .foregroundStyle(ILColor.link)
        }
    }

    // MARK: - Helpers

    private func primaryLabel(for mode: OnboardingMode) -> String {
        switch mode {
        case .signIn:         return "Sign In"
        case .register:       return "Create Account"
        case .forgotPassword: return "Send Reset Email"
        }
    }
}
