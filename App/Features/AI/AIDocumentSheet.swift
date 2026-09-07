// AIDocumentSheet
//
// "Draft a document with AI" (work-consolidation.md G15, `powered_document`).
// Four modes, matching the web app: a standalone article from a topic, a
// document derived from one of your lists, one derived from an existing
// document, or one researched from a web page.
//
// The mode determines which second input is required, so the form shows exactly
// one and the Draft button gates on it — a mode with a missing `listId` or `url`
// would otherwise fail server-side after spending a quota unit.
//
// Per Decision 0003 this view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct AIDocumentSheet: View {

    let environment: AppEnvironment
    /// Lists the user owns, offered when deriving from a list. Loaded from the
    /// on-disk cache when the sheet appears — a free read, so the picker is
    /// populated without the host having to hold lists it does not otherwise need.
    @State private var lists: [OwnedList] = []
    /// Documents the user owns, offered when deriving from an article.
    var documents: [Document] = []
    /// Called after a drafted document is created, so the host can reload it.
    var onCreated: (() async -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var assistant: AIAssistantViewModel?

    @State private var mode: Mode = .article
    @State private var prompt: String = ""
    @State private var selectedListID: String?
    @State private var selectedDocumentID: String?
    @State private var urlText: String = ""

    /// The sheet's own mode enum: `AIDocumentMode` carries its associated value,
    /// which a `Picker` selection cannot.
    enum Mode: String, CaseIterable, Identifiable {
        case article, fromList, fromArticle, researchURL
        var id: String { rawValue }

        var label: String {
            switch self {
            case .article: return "Article"
            case .fromList: return "From a list"
            case .fromArticle: return "From a document"
            case .researchURL: return "From a URL"
            }
        }

        var promptHint: String {
            switch self {
            case .article: return "What should the document be about?"
            case .fromList: return "How should the list be written up? (optional)"
            case .fromArticle: return "How should the source be rewritten? (optional)"
            case .researchURL: return "What should be taken from the page? (optional)"
            }
        }

        /// Whether the prompt alone is enough, or a second input is required.
        var requiresPrompt: Bool { self == .article }

        /// The domain mode for this selection, or `nil` when the second input
        /// this mode requires is missing or unusable.
        ///
        /// Pure so the gate can be tested without a view: a mode that reaches
        /// the service without its `listId` / `documentId` / `url` fails
        /// server-side *after* spending a quota unit, which is exactly the kind
        /// of mistake worth catching in the button's disabled state.
        func domainMode(listID: String?, documentID: String?, urlText: String) -> AIDocumentMode? {
            switch self {
            case .article:
                return .article
            case .fromList:
                return listID.map { .fromList(listId: $0) }
            case .fromArticle:
                return documentID.map { .fromArticle(documentId: $0) }
            case .researchURL:
                let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else { return nil }
                return .researchURL(url)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Picker("Source", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Document source")

            sourceInput

            VStack(alignment: .leading, spacing: 4) {
                Text(mode.promptHint)
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                TextEditor(text: $prompt)
                    .font(.ilBody())
                    .frame(minHeight: 90)
                    .overlay(
                        RoundedRectangle(cornerRadius: ILMetric.radiusSm)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .accessibilityLabel("Prompt")
            }

            if let assistant {
                AIAvailabilityNote(viewModel: assistant)
            }

            Spacer(minLength: 0)
            Divider()
            footer
        }
        .padding(18)
        .frame(minWidth: 560, minHeight: 440)
        .task {
            if assistant == nil {
                let assistant = AIAssistantViewModel(ai: environment.aiService)
                self.assistant = assistant
                await assistant.refreshAvailability()
            }
            if lists.isEmpty {
                // Cache first (free, already warm from launch prefetch); only
                // reach for the network if this account has never loaded lists.
                let cached = await environment.lists.cachedMyLists()
                if cached.isEmpty {
                    lists = (try? await environment.lists.myLists(limit: 50, offset: 0))?.lists ?? []
                } else {
                    lists = cached
                }
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
            guard message != nil else { return }
            Task {
                await onCreated?()
                dismiss()
            }
        }
    }

    // MARK: - Source input

    @ViewBuilder
    private var sourceInput: some View {
        switch mode {
        case .article:
            EmptyView()

        case .fromList:
            if lists.isEmpty {
                emptySourceNote("You don't have any lists to derive from yet.")
            } else {
                Picker("List", selection: $selectedListID) {
                    Text("Choose a list").tag(String?.none)
                    ForEach(lists, id: \.id) { list in
                        Text(list.title).tag(String?.some(list.id))
                    }
                }
                .accessibilityLabel("Source list")
            }

        case .fromArticle:
            if documents.isEmpty {
                emptySourceNote("You don't have any documents to derive from yet.")
            } else {
                Picker("Document", selection: $selectedDocumentID) {
                    Text("Choose a document").tag(String?.none)
                    ForEach(documents, id: \.id) { document in
                        Text(document.title).tag(String?.some(document.id))
                    }
                }
                .accessibilityLabel("Source document")
            }

        case .researchURL:
            TextField("https://example.com/article", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Source URL")
        }
    }

    private func emptySourceNote(_ text: String) -> some View {
        Text(text)
            .font(.ilSubtitle())
            .foregroundStyle(.secondary)
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Label("Draft a document with AI", systemImage: "sparkles")
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
                guard let domainMode else { return }
                Task { await assistant?.draftDocument(prompt: prompt, mode: domainMode) }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canDraft)
        }
    }

    private var finishedMessage: String? {
        guard case .finished(let message, _) = assistant?.phase else { return nil }
        return message
    }

    // MARK: - Gating

    private var domainMode: AIDocumentMode? {
        mode.domainMode(listID: selectedListID, documentID: selectedDocumentID, urlText: urlText)
    }

    private var canDraft: Bool {
        guard let assistant, assistant.isAvailable, !assistant.isBusy else { return false }
        guard domainMode != nil else { return false }
        if mode.requiresPrompt {
            return !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }
}
