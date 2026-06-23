// NewListSheetView
//
// The "New List" sheet (PLAN.md §6 M3 list CRUD). SwiftUI form
// with title, description, optional schema DSL, parent picker for
// nested lists, visibility, and optional GitHub-source fields.
// Submission goes through `NewListViewModel`.

import SwiftUI
import InterlinedDomain

struct NewListSheetView: View {

    let environment: AppEnvironment
    let parentCandidates: [OwnedList]

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: NewListViewModel?

    var body: some View {
        Group {
            if let viewModel {
                form(viewModel: viewModel)
            } else {
                ProgressView()
                    .padding()
            }
        }
        .frame(minWidth: 460, minHeight: 460)
        .onAppear {
            if viewModel == nil {
                viewModel = NewListViewModel(
                    lists: environment.lists,
                    eventBus: environment.listsEventBus,
                    parentCandidates: parentCandidates
                )
            }
        }
        .onChange(of: viewModel?.didFinish) { _, finished in
            if finished == true { dismiss() }
        }
    }

    @ViewBuilder
    private func form(viewModel: NewListViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Basics") {
                    TextField("Title", text: Binding(
                        get: { viewModel.title },
                        set: { viewModel.title = $0 }
                    ))
                    TextField("Description (optional)", text: Binding(
                        get: { viewModel.descriptionText },
                        set: { viewModel.descriptionText = $0 }
                    ))
                }
                Section("Schema") {
                    TextField("Schema DSL (e.g. Title:text, Year:number)", text: Binding(
                        get: { viewModel.schemaDSL },
                        set: { viewModel.schemaDSL = $0 }
                    ))
                    Text("You can also edit this later from the schema editor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Organization") {
                    Picker("Parent list", selection: Binding(
                        get: { viewModel.parentID },
                        set: { viewModel.parentID = $0 }
                    )) {
                        Text("None").tag(String?.none)
                        ForEach(viewModel.parentCandidates) { candidate in
                            Text(candidate.title).tag(String?.some(candidate.id))
                        }
                    }
                    Picker("Visibility", selection: Binding(
                        get: { viewModel.visibility },
                        set: { viewModel.visibility = $0 }
                    )) {
                        Text("Private").tag(Visibility.private)
                        Text("Public").tag(Visibility.public)
                    }
                    .pickerStyle(.segmented)
                }
                Section("GitHub source (optional)") {
                    TextField("owner/repo", text: Binding(
                        get: { viewModel.gitHubRepository },
                        set: { viewModel.gitHubRepository = $0 }
                    ))
                    TextField("Path within repo", text: Binding(
                        get: { viewModel.gitHubPath },
                        set: { viewModel.gitHubPath = $0 }
                    ))
                    TextField("Branch", text: Binding(
                        get: { viewModel.gitHubBranch },
                        set: { viewModel.gitHubBranch = $0 }
                    ))
                    Text("GitHub source fields will be sent in a future update.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = viewModel.error {
                    Section {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.primary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            footer(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func footer(viewModel: NewListViewModel) -> some View {
        HStack {
            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Spacer()
            if viewModel.isSubmitting {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }
            Button("Create") {
                Task { await viewModel.submit() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.isPublishable || viewModel.isSubmitting)
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }
}
