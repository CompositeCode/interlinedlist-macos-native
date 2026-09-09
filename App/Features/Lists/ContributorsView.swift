// ContributorsView
//
// The ranked contributor panel for a list (work-consolidation.md G23 /
// issue #48), presented as a sheet from the Lists toolbar. Shows who added
// and edited rows, in the server's ranking order.
//
// Per Decision 0003 the view imports only InterlinedDomain.

import SwiftUI
import InterlinedDomain

struct ContributorsView: View {

    let listId: String
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ContributorsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
                    .accessibilityLabel("Loading contributors")
                    .padding()
            }
        }
        .frame(minWidth: 440, minHeight: 340)
        .task {
            if viewModel == nil {
                let model = ContributorsViewModel(lists: environment.lists, listId: listId)
                viewModel = model
                await model.load()
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: ContributorsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if viewModel.isLoading, viewModel.contributors.isEmpty {
                ProgressView()
                    .accessibilityLabel("Loading contributors")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error, viewModel.contributors.isEmpty {
                errorState(error: error, viewModel: viewModel)
            } else if viewModel.contributors.isEmpty {
                Text("No contributions yet — nobody has added or edited a row.")
                    .font(.ilMono(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List {
                    ForEach(Array(viewModel.contributors.enumerated()), id: \.element.id) { index, contributor in
                        row(rank: index + 1, contributor: contributor, total: viewModel.totalScore)
                    }
                }
            }

            Divider()
            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Contributors")
                .font(.ilTitle(20))
            Text("Everyone who has added or edited rows on this list, most active first.")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private func row(rank: Int, contributor: ListContributor, total: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.ilMono(11))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
                .accessibilityHidden(true)

            Image(systemName: "person.crop.circle")
                .font(.ilMono(24))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(contributor.displayLabel)
                    .font(.ilBody())
                if let username = contributor.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(contributor.addedCount) added · \(contributor.editedCount) edited")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                // Guarded: `total` is 0 only when the list has no
                // contributors, in which case this row does not render.
                if total > 0 {
                    Text("\(Int((Double(contributor.score) / Double(total) * 100).rounded()))% of edits")
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(contributor.displayLabel), rank \(rank), \(contributor.addedCount) rows added, \(contributor.editedCount) rows edited"
        )
    }

    private func errorState(error: Error, viewModel: ContributorsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Couldn't load contributors", systemImage: "exclamationmark.triangle")
                .font(.ilBody().weight(.semibold))
            Text(error.localizedDescription)
                .font(.ilMono(11))
                .foregroundStyle(.secondary)
            Button("Try Again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(16)
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
}
