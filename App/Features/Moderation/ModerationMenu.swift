// ModerationMenu + ReportReasonSheet
//
// Reusable moderation affordances (work-consolidation.md G2). `ModerationMenu`
// renders the Block / Mute / Report buttons intended to sit inside an
// existing `contextMenu { … }` or overflow `Menu { … }`, so hosts can
// drop it into a profile header or a timeline row additively without
// disrupting their own actions. It owns a `ModerationActionViewModel`
// and drives block / mute directly; Report opens the `ReportReasonSheet`.
//
// Because a `contextMenu` closure cannot host a `.sheet` modifier
// reliably, the sheet presentation lives on a thin `ModerationMenuHost`
// wrapper the caller attaches to the row/header content. The typical
// usage is:
//
//     rowContent
//         .modifier(ModerationMenuHost(username: …, messageID: …))
//
// which installs both the context-menu items and the report sheet.
//
// Per decision 0003, this view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

// MARK: - ModerationMenuHost

/// View modifier that attaches the moderation context-menu items **and**
/// the report sheet to any content. Additive: it augments the host's own
/// context menu rather than replacing it (SwiftUI merges nested
/// `contextMenu` content when applied in sequence, and hosts that already
/// own a menu can instead embed `ModerationMenu` directly — see below).
struct ModerationMenuHost: ViewModifier {

    let username: String
    var messageID: String? = nil

    @Environment(\.appEnvironment) private var environment

    @State private var actionVM: ModerationActionViewModel?
    @State private var showReportSheet = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if let actionVM {
                    ModerationMenu(viewModel: actionVM, showReportSheet: $showReportSheet)
                }
            }
            .task {
                if actionVM == nil, let environment {
                    actionVM = ModerationActionViewModel(
                        username: username,
                        messageID: messageID,
                        service: environment.moderation
                    )
                }
            }
            .sheet(isPresented: $showReportSheet) {
                if let actionVM {
                    ReportReasonSheet(viewModel: actionVM)
                }
            }
    }
}

extension View {
    /// Attaches moderation affordances (Block / Mute / Report) to a row or
    /// header. Pass a `messageID` when the subject is a specific message so
    /// the "Report message" action is available.
    func moderationMenu(username: String, messageID: String? = nil) -> some View {
        modifier(ModerationMenuHost(username: username, messageID: messageID))
    }
}

// MARK: - ModerationMenu

/// The Block / Mute / Report buttons themselves, for hosts that already
/// own a `Menu` / `contextMenu` and want to compose the moderation items
/// into it. Needs a `showReportSheet` binding wired to a `.sheet` the
/// host presents (see `ModerationMenuHost`).
struct ModerationMenu: View {

    @Bindable var viewModel: ModerationActionViewModel
    @Binding var showReportSheet: Bool

    var body: some View {
        Group {
            if viewModel.isBlocked {
                Button {
                    Task { await viewModel.unblock() }
                } label: {
                    Label("Unblock @\(viewModel.username)", systemImage: "hand.raised.slash")
                }
            } else {
                Button {
                    Task { await viewModel.block() }
                } label: {
                    Label("Block @\(viewModel.username)", systemImage: "hand.raised")
                }
            }

            if viewModel.isMuted {
                Button {
                    Task { await viewModel.unmute() }
                } label: {
                    Label("Unmute @\(viewModel.username)", systemImage: "speaker.wave.2")
                }
            } else {
                Button {
                    Task { await viewModel.mute() }
                } label: {
                    Label("Mute @\(viewModel.username)", systemImage: "speaker.slash")
                }
            }

            Divider()

            Button(role: .destructive) {
                showReportSheet = true
            } label: {
                Label("Report\u{2026}", systemImage: "flag")
            }
        }
    }
}

// MARK: - ReportReasonSheet

/// Modal report form: a reason picker over `ReportReason.allCases` plus an
/// optional free-text detail field. Submits a user report or a message
/// report depending on whether the subject has a `messageID`.
struct ReportReasonSheet: View {

    @Bindable var viewModel: ModerationActionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var reason: ReportReason = .harassment
    @State private var detail: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(headline)
                .font(.ilTitle())

            Picker("Reason", selection: $reason) {
                ForEach(ReportReason.allCases) { reason in
                    Text(reason.label).tag(reason)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Report reason")

            VStack(alignment: .leading, spacing: 4) {
                Text("Details (optional)")
                    .font(.ilSubtitle())
                    .foregroundStyle(.secondary)
                TextEditor(text: $detail)
                    .frame(minHeight: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .accessibilityLabel("Report details")
            }

            if let error = viewModel.error {
                Text(error.localizedDescription)
                    .font(.ilSubtitle())
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Submit report") {
                    Task {
                        await submit()
                        if viewModel.didSubmitReport { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isBusy)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var headline: String {
        viewModel.canReportMessage
            ? "Report message"
            : "Report @\(viewModel.username)"
    }

    private func submit() async {
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let detailOrNil = trimmedDetail.isEmpty ? nil : trimmedDetail
        if viewModel.canReportMessage {
            await viewModel.reportMessage(reason: reason, detail: detailOrNil)
        } else {
            await viewModel.reportUser(reason: reason, detail: detailOrNil)
        }
    }
}
