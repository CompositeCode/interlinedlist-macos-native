// CrashReportingSettingsView
//
// The Settings tab added by GitHub issue #29: the opt-in "help development"
// toggle, plus an honest description of what a report contains and where the
// full log stays.
//
// The toggle defaults **off** and gates only the *prompt and submission* —
// capture runs unconditionally, so switching this on after a crash still has
// something to offer rather than reporting "nothing was recorded".
//
// SwiftUI-only (no AppKit / NSViewRepresentable). Per decision 0003 this file
// imports no Kit symbols.

import SwiftUI
import InterlinedDomain

struct CrashReportingSettingsView: View {

    @Environment(\.appEnvironment) private var environment
    @State private var viewModel: CrashReportingViewModel?

    var body: some View {
        Form {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .task {
            guard viewModel == nil, let environment else { return }
            viewModel = CrashReportingViewModel(service: environment.crashReports)
        }
        .onAppear { viewModel?.refreshFromPreferences() }
    }

    @ViewBuilder
    private func content(viewModel: CrashReportingViewModel) -> some View {
        @Bindable var model = viewModel

        Section {
            Toggle(isOn: $model.isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Help development by reporting crashes")
                    Text("If InterlinedList quits unexpectedly, you'll be asked on the next launch whether to file a report.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Crash Reporting")
        } footer: {
            Text("Reports are filed as public GitHub issues on the InterlinedList repository. Nothing is ever sent automatically — you see the exact text first, can edit it, and press Submit on GitHub yourself.")
                .font(.caption)
        }

        Section {
            Label {
                Text("Bearer tokens, JWTs, email addresses, account handles and document or list content are removed before the report is shown to you.")
            } icon: {
                Image(systemName: "lock.shield")
            }
            .font(.callout)

            if let path = viewModel.logFilePath {
                LabeledContent("Full log") {
                    // Selectable so a user can copy the path and inspect the
                    // file themselves — the claim above should be checkable.
                    Text(path)
                        .font(.caption)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("What's in a report")
        }

        #if DEBUG
        // Debug-only verification affordance (issue #29). The signal handler
        // ends the process by design and so cannot be unit tested in-process;
        // this is how the crash → relaunch → sheet loop gets exercised by
        // hand. Never compiled into a release build.
        Section {
            ForEach(CrashSignalHandler.SimulatedCrash.allCases) { kind in
                Button("Crash now: \(kind.title)", role: .destructive) {
                    CrashSignalHandler.simulateCrash(kind)
                }
            }
        } header: {
            Text("Debug")
        } footer: {
            Text("Debug builds only. Quits the app immediately so the next launch can show the crash sheet.")
                .font(.caption)
        }
        #endif
    }
}

#Preview {
    CrashReportingSettingsView()
}
