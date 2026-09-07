// CrashReportSheet
//
// The next-launch crash confirmation (GitHub issue #29, PR 1).
//
// The whole point of this sheet is informed consent, so it is built around
// showing rather than summarising: the user sees the **exact, redacted text**
// that will be posted, in an editable field, before anything happens. That
// preview is a genuine second line of defence behind `CrashReportRedactor`,
// not decoration — the destination repository is public and permanent.
//
// Nothing is transmitted from here. "Send" opens a prefilled GitHub
// `issues/new` page; the user still presses Submit there.
//
// SwiftUI-only (no AppKit / NSViewRepresentable). Per decision 0003 this file
// imports no Kit symbols.

import SwiftUI
import InterlinedDomain

struct CrashReportSheet: View {

    @Bindable var viewModel: CrashReportingViewModel
    let report: CrashReport

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summary
                    noteField
                    payloadPreview
                    if let path = viewModel.logFilePath {
                        privacyFootnote(logPath: path)
                    }
                    if let error = viewModel.submissionError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 520, idealHeight: 640)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "ladybug")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("InterlinedList quit unexpectedly")
                    .font(.headline)
                Text("You can send this report to help fix it. Nothing is sent until you choose to.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    // MARK: - Summary

    private var summary: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Type", value: report.name)
                LabeledContent("Version", value: "\(report.appVersion) (\(report.build))")
                LabeledContent("macOS", value: report.osVersion)
                LabeledContent("When", value: report.occurredAt.formatted(date: .abbreviated, time: .standard))
                if let reason = report.reason, !reason.isEmpty {
                    LabeledContent("Reason", value: reason)
                }
            }
            .font(.callout)
            .padding(4)
        }
    }

    // MARK: - Note

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What were you doing? (optional)")
                .font(.subheadline)
                .fontWeight(.medium)
            TextField("e.g. saving a document after editing a list", text: $viewModel.userNote, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
        }
    }

    // MARK: - Payload preview

    private var payloadPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Exactly what will be posted")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("Editable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Monospaced because this is literal Markdown the user is being
            // asked to audit, not prose.
            TextEditor(text: $viewModel.editableBody)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3))
                )
                .onChange(of: viewModel.editableBody) { _, _ in
                    // Stop the note field from rewriting text the user has
                    // taken ownership of.
                    viewModel.markBodyEdited()
                }
        }
    }

    private func privacyFootnote(logPath: String) -> some View {
        Label {
            Text("Tokens, email addresses and document content were removed above. The full log stays on this Mac at \(logPath).")
        } icon: {
            Image(systemName: "lock.shield")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Never Ask Again") {
                Task { await viewModel.neverAskAgain() }
            }
            .help("Turns off crash reporting in Settings. You can switch it back on there at any time.")

            Spacer()

            Button("Don't Send") {
                Task { await viewModel.dismiss() }
            }
            .keyboardShortcut(.cancelAction)

            Button("Send…") {
                Task {
                    await viewModel.submit { url in
                        // `openURL` reports whether the system accepted the
                        // URL; a refusal keeps the breadcrumb so the user can
                        // retry rather than losing the report.
                        await withCheckedContinuation { continuation in
                            openURL(url) { accepted in
                                continuation.resume(returning: accepted)
                            }
                        }
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            .help("Opens GitHub with this report filled in. You still press Submit there.")
        }
        .padding(20)
    }
}
