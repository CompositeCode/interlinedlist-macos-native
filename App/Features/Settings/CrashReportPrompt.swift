// CrashReportPrompt
//
// Hosts the next-launch crash sheet (GitHub issue #29, PR 1).
//
// The sheet has to appear at launch, but the Settings scene is not open at
// launch — so the prompt is packaged as a view modifier that the app's root
// view applies. Keeping it a modifier means the only change at the root is a
// single line, and every decision about *whether* to prompt stays here with
// the rest of the crash-reporting feature.
//
// SwiftUI-only. Per decision 0003 this file imports no Kit symbols.

import SwiftUI
import InterlinedDomain

private struct CrashReportPromptModifier: ViewModifier {

    let service: CrashReportServicing

    @State private var viewModel: CrashReportingViewModel?

    func body(content: Content) -> some View {
        content
            .task {
                // One shot per launch. `loadPendingReport()` is itself a no-op
                // when reporting is off or there is no breadcrumb, so there is
                // nothing to guard here beyond building the model once.
                guard viewModel == nil else { return }
                let model = CrashReportingViewModel(service: service)
                viewModel = model
                await model.loadPendingReport()
            }
            .sheet(item: crashBinding) { report in
                if let viewModel {
                    CrashReportSheet(viewModel: viewModel, report: report)
                }
            }
    }

    /// Drives `.sheet(item:)` off the pending report. The setter only ever
    /// receives `nil` (SwiftUI dismissing the sheet), and it is routed through
    /// `dismiss()` so a sheet closed with Escape or the window chrome still
    /// clears the breadcrumb — otherwise the same crash would prompt forever.
    private var crashBinding: Binding<CrashReport?> {
        Binding(
            get: { viewModel?.pendingReport },
            set: { newValue in
                guard newValue == nil, let viewModel, viewModel.pendingReport != nil else { return }
                Task { await viewModel.dismiss() }
            }
        )
    }
}

extension View {

    /// Offers to file a GitHub issue when the previous run crashed.
    ///
    /// Applied once, at the app's root view — the sheet must be able to appear
    /// on a cold launch, long before anyone opens Settings.
    func crashReportPrompt(service: CrashReportServicing) -> some View {
        modifier(CrashReportPromptModifier(service: service))
    }
}
