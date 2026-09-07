// AIPreviewSheet
//
// Renders an AI preview and the decision that goes with it
// (work-consolidation.md G15). One sheet serves every feature because the
// decision is always the same shape: look at what the model produced, then
// accept it or discard it.
//
// Nothing here writes. An accepted assistant result is handed back through
// `onAccept` for the composer to apply; an accepted generative result is
// confirmed through the view model, which is the only path that persists.
//
// Per Decision 0003 this view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct AIPreviewSheet: View {

    let suggestion: AISuggestion
    let viewModel: AIAssistantViewModel
    /// Applies an assistant result to the composer. Absent for the generative
    /// features, whose results are persisted server-side instead.
    var onAccept: ((AIAssistantOutcome) -> Void)?

    @Environment(\.dismiss) private var dismiss

    /// Message series only: post on a schedule instead of collecting the parts
    /// into a list. Mirrors the web app's own checkbox.
    @State private var scheduleImmediately = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
            if case .messageSeries = suggestion.artifact {
                scheduleToggle
            }
            usageFooter
            Divider()
            actions
        }
        .padding(18)
        .frame(minWidth: 520, minHeight: 380)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.ilTitle())
            Spacer()
            if viewModel.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Working")
            }
        }
    }

    private var title: String {
        switch suggestion.artifact {
        case .message: return "Suggested rewrite"
        case .thread(let parts): return "Thread (\(parts.count) parts)"
        case .tags: return "Suggested tags"
        case .messageSeries: return "Message series preview"
        case .articleSeries: return "Article series preview"
        case .listTemplate: return "Drafted list"
        case .document: return "Drafted document"
        case .unknown: return "Preview unavailable"
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch suggestion.artifact {
        case .message(let text):
            Text(text)
                .font(.ilBody())
                .textSelection(.enabled)

        case .thread(let parts):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    numbered(index + 1, part)
                }
            }

        case .tags(let tags):
            FlowingTags(tags: tags)

        case .messageSeries(let listTitle, let items):
            VStack(alignment: .leading, spacing: 10) {
                if let listTitle {
                    Text(listTitle)
                        .font(.ilSubtitle())
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    numbered(item.order, item.content)
                }
            }

        case .articleSeries(let documents):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(documents.enumerated()), id: \.offset) { index, document in
                    numbered(index + 1, document.title, emphasised: true)
                }
            }

        case .listTemplate(let draft):
            listTemplatePreview(draft)

        case .document(let draft):
            VStack(alignment: .leading, spacing: 8) {
                Text(draft.title).font(.ilSubtitle())
                if !draft.outline.isEmpty {
                    ForEach(Array(draft.outline.enumerated()), id: \.offset) { index, heading in
                        numbered(index + 1, heading)
                    }
                }
                Text(draft.markdown)
                    .font(.ilMono(11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

        case .unknown(let kind):
            // A server that adds a feature or renames a kind lands here. Saying so
            // beats an empty sheet that looks like a bug in the model's output.
            VStack(alignment: .leading, spacing: 6) {
                Text("This version of InterlinedList can't display this result\(kind.map { " (\($0))" } ?? "").")
                    .font(.ilBody())
                Text("Update the app to use it.")
                    .font(.ilSubtitle())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func numbered(_ number: Int, _ text: String, emphasised: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.ilMono(11))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            Text(text)
                .font(emphasised ? .ilSubtitle() : .ilBody())
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func listTemplatePreview(_ draft: AIListTemplateDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(draft.title).font(.ilSubtitle())
            if let description = draft.description {
                Text(description)
                    .font(.ilBody())
                    .foregroundStyle(.secondary)
            }
            ForEach(draft.fields) { field in
                HStack(spacing: 8) {
                    Text(field.label).font(.ilBody())
                    Text(field.type)
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                    if field.isRequired {
                        Text("required")
                            .font(.ilMono(10))
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer(minLength: 0)
                }
            }
            if !draft.rows.isEmpty {
                Text("\(draft.rows.count) starter row\(draft.rows.count == 1 ? "" : "s")")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Series scheduling

    private var scheduleToggle: some View {
        Toggle(isOn: $scheduleImmediately) {
            Text("Schedule these posts instead of creating a list")
                .font(.ilSubtitle())
        }
        .toggleStyle(.checkbox)
        .accessibilityHint("Posts the series on a schedule, first in about 30 to 45 minutes, then every 5 to 10 minutes")
    }

    // MARK: - Usage

    @ViewBuilder
    private var usageFooter: some View {
        if let usage = suggestion.usage, usage.model != nil || usage.outputTokens != nil {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.secondary)
                Text(usageLine(usage))
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func usageLine(_ usage: AIUsage) -> String {
        var parts: [String] = []
        if let model = usage.model { parts.append(model) }
        if let output = usage.outputTokens { parts.append("\(output) tokens out") }
        if let quota = suggestion.quota, quota.dailyLimit > 0 {
            parts.append("\(quota.usedToday)/\(quota.dailyLimit) today")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    private var actions: some View {
        HStack {
            Button("Cancel", role: .cancel) {
                viewModel.reset()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if let label = acceptLabel {
                Button(label) { accept() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.isBusy)
            }
        }
    }

    /// `nil` for `.unknown`, where there is nothing meaningful to accept.
    private var acceptLabel: String? {
        switch suggestion.artifact {
        case .message: return "Replace draft"
        case .thread: return "Use in draft"
        case .tags: return "Add tags"
        case .messageSeries: return scheduleImmediately ? "Schedule" : "Create list"
        case .articleSeries, .listTemplate, .document: return "Create"
        case .unknown: return nil
        }
    }

    private func accept() {
        switch suggestion.artifact {
        case .message(let text):
            onAccept?(.replaceDraft(text))
            viewModel.reset()
            dismiss()
        case .thread(let parts):
            onAccept?(.useThread(parts))
            viewModel.reset()
            dismiss()
        case .tags(let tags):
            onAccept?(.addTags(tags))
            viewModel.reset()
            dismiss()
        case .messageSeries:
            Task {
                await viewModel.confirmPending(scheduleImmediately: scheduleImmediately)
                dismiss()
            }
        case .articleSeries, .listTemplate, .document:
            Task {
                await viewModel.confirmPending()
                dismiss()
            }
        case .unknown:
            break
        }
    }
}

// MARK: - Tag chips

/// Suggested tags as chips. Kept local to the sheet — it is the only place that
/// renders a tag set that is not yet part of a draft.
private struct FlowingTags: View {

    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.ilMono(11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(ILColor.primary.opacity(0.12), in: Capsule())
            }
        }
    }
}
