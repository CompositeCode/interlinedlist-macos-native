// AIListTemplateSheet
//
// "Draft a list with AI" (work-consolidation.md G15, `powered_template`).
// Describe the list you want; the model drafts a schema plus a few starter
// rows, and the existing preview sheet handles the accept-or-discard decision.
//
// This sheet only collects the description and starts the run. It deliberately
// does not create anything itself — confirming the preview is what persists,
// and that path already lives in `AIAssistantViewModel`.
//
// Per Decision 0003 this view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct AIListTemplateSheet: View {

    let environment: AppEnvironment
    /// Called after a drafted list is created, so the host can reload and select it.
    var onCreated: (() async -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var assistant: AIAssistantViewModel?
    @State private var description: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Text("Describe the list you want. Include the columns you care about — the model drafts the schema and a few starter rows.")
                .font(.ilSubtitle())
                .foregroundStyle(.secondary)

            TextEditor(text: $description)
                .font(.ilBody())
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: ILMetric.radiusSm)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .accessibilityLabel("List description")

            if let assistant {
                AIAvailabilityNote(viewModel: assistant)
            }

            Spacer(minLength: 0)
            Divider()
            footer
        }
        .padding(18)
        .frame(minWidth: 520, minHeight: 380)
        .task {
            if assistant == nil {
                let assistant = AIAssistantViewModel(ai: environment.aiService)
                self.assistant = assistant
                await assistant.refreshAvailability()
            }
        }
        .sheet(isPresented: Binding(
            get: { assistant?.pendingSuggestion != nil },
            set: { presented in if !presented { assistant?.reset() } }
        )) {
            if let assistant, let suggestion = assistant.pendingSuggestion {
                AIPreviewSheet(suggestion: suggestion, viewModel: assistant)
            }
        }
        .onChange(of: finishedMessage) { _, message in
            // The confirm persisted the list; hand control back to the host so it
            // can reload and reveal what was just created.
            guard message != nil else { return }
            Task {
                await onCreated?()
                dismiss()
            }
        }
    }

    private var finishedMessage: String? {
        guard case .finished(let message, _) = assistant?.phase else { return nil }
        return message
    }

    private var header: some View {
        HStack {
            Label("Draft a list with AI", systemImage: "sparkles")
                .font(.ilTitle())
            Spacer()
            if assistant?.isBusy == true {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Drafting")
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)

            if let message = assistant?.errorMessage {
                Text(message)
                    .font(.ilMono(10))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(2)
            }

            Spacer()

            Button("Draft") {
                Task { await assistant?.draftListTemplate(describing: description) }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canDraft)
        }
    }

    private var canDraft: Bool {
        guard let assistant, assistant.isAvailable, !assistant.isBusy else { return false }
        return !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Availability note

/// Explains an unavailable assistant in place. Shared by the two generative
/// sheets, which — unlike the composer menu — have room to say it in full.
struct AIAvailabilityNote: View {

    let viewModel: AIAssistantViewModel

    var body: some View {
        if let reason = viewModel.unavailableReason {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.accentColor)
                Text(reason)
                    .font(.ilSubtitle())
                Spacer()
            }
            .padding(8)
            .background(ILColor.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: ILMetric.radiusSm))
            .accessibilityElement(children: .combine)
        } else if let quota = viewModel.quotaSummary {
            Text(quota)
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
        }
    }
}
