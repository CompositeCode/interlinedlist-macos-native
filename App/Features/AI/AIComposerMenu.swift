// AIComposerMenu
//
// The composer's AI entry point (work-consolidation.md G15): the six writing
// assistant actions plus the two series planners, in one menu.
//
// The menu is always visible but disables itself with a *reason* when AI is off,
// because "greyed out with no explanation" is the worst version of a gated
// feature — a subscriber with no provider key would otherwise have no way to
// learn what is missing. The reason comes from the server, not from a local
// guess at entitlements.
//
// Per Decision 0003 this view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct AIComposerMenu: View {

    let viewModel: AIAssistantViewModel
    /// The current draft — the assistant's input, and what a rewrite replaces.
    let draft: String
    /// Cross-post destinations selected in the composer, so a planned series is
    /// sized to the smallest one's character limit.
    let channels: [String]

    var body: some View {
        Menu {
            if viewModel.isAvailable {
                Section("Rewrite this draft") {
                    ForEach(AIWritingAction.allCases) { action in
                        Button(action.label) {
                            Task { await viewModel.assist(action: action, draft: draft) }
                        }
                    }
                }
                Section("Plan a series") {
                    Button("Message series") {
                        Task { await viewModel.planMessageSeries(brief: draft, channels: channels) }
                    }
                    Button("Article series") {
                        Task { await viewModel.planArticleSeries(brief: draft) }
                    }
                }
                if let quota = viewModel.quotaSummary {
                    Section { Text(quota) }
                }
            } else if let reason = viewModel.unavailableReason {
                // Shown inside the menu rather than as a tooltip: a disabled
                // control the user cannot hover-discover explains nothing.
                Text(reason)
            } else {
                Text("Checking availability…")
            }
        } label: {
            Label("AI", systemImage: "sparkles")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(viewModel.isBusy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .help(menuHelp)
        .accessibilityLabel("AI assistant")
        .accessibilityHint(menuHelp)
    }

    private var menuHelp: String {
        if let reason = viewModel.unavailableReason { return reason }
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Write a draft first, then AI can rewrite it or plan a series from it."
        }
        if viewModel.isBusy { return "Working…" }
        return "Rewrite the draft or plan a series"
    }
}
