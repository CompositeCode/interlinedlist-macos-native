// VisibilityView
//
// The "Make Public" sheet for a list or a document (work-consolidation.md G3),
// mirroring the web sharing dialog's bottom section. Off means only invited
// people can access the resource; on lets anyone with the link view it. The
// toggle drives the resource's partial-update through `VisibilityViewModel`.
//
// One view serves both resources via `ShareTarget`. The starting value is
// passed in from the already-loaded document / list so the sheet paints the
// correct state immediately.

import SwiftUI
import InterlinedDomain

struct VisibilityView: View {

    let target: ShareTarget
    let environment: AppEnvironment
    let initialIsPublic: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: VisibilityViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
                    .accessibilityLabel("Loading visibility")
                    .padding()
            }
        }
        .frame(minWidth: 460, minHeight: 260)
        .task {
            if viewModel == nil {
                viewModel = VisibilityViewModel(
                    target: target,
                    documents: environment.documentsService,
                    lists: environment.lists,
                    isPublic: initialIsPublic
                )
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: VisibilityViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Toggle("Public", isOn: Binding(
                        get: { viewModel.isPublic },
                        set: { on in Task { await viewModel.setPublic(on) } }
                    ))
                    .toggleStyle(.switch)
                    .disabled(viewModel.isUpdating)
                    if viewModel.isUpdating {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                }
                Text(explanation(isPublic: viewModel.isPublic))
                    .font(.ilMono(11))
                    .foregroundStyle(.secondary)
                if let error = viewModel.error {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                        .font(.ilMono(11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            Spacer()
            Divider()
            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Make Public")
                .font(.ilTitle(20))
            Text("Control whether anyone with the link can view this \(target.noun).")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    // MARK: - Helpers

    private func explanation(isPublic: Bool) -> String {
        if isPublic {
            return "On: anyone with the link can view this \(target.noun), no account needed."
        }
        return "Off: only people you invite can access this \(target.noun). Turn on to let anyone with the link view it."
    }
}
