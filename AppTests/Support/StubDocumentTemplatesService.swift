// StubDocumentTemplatesService
//
// Deterministic `DocumentTemplatesServicing` stub for App-layer view-model
// tests of the server document-templates feature (the-gaps.md G12). Mirrors the
// project's other stubs: an actor with one FIFO outcome queue per call site plus
// a recorded-call log so tests can assert both the surfaced result and that the
// right calls were (or were not) made.

import Foundation
import InterlinedDomain

struct RecordedDocumentTemplatesCall: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case templates
        case createFromTemplate(templateDocumentId: String)
        case seedDefaultTemplates
    }
    let kind: Kind
}

actor StubDocumentTemplatesService: DocumentTemplatesServicing {

    private var templatesOutcomes: [Result<[DocumentTemplateRef], Error>] = []
    private var createOutcomes: [Result<Void, Error>] = []
    private var seedOutcomes: [Result<Void, Error>] = []

    private(set) var recorded: [RecordedDocumentTemplatesCall] = []

    // MARK: Programmable enqueue helpers

    func enqueueTemplates(success value: [DocumentTemplateRef]) { templatesOutcomes.append(.success(value)) }
    func enqueueTemplates(failure error: Error) { templatesOutcomes.append(.failure(error)) }

    func enqueueCreateSuccess() { createOutcomes.append(.success(())) }
    func enqueueCreate(failure error: Error) { createOutcomes.append(.failure(error)) }

    func enqueueSeedSuccess() { seedOutcomes.append(.success(())) }
    func enqueueSeed(failure error: Error) { seedOutcomes.append(.failure(error)) }

    // MARK: DocumentTemplatesServicing

    func templates() async throws -> [DocumentTemplateRef] {
        recorded.append(.init(kind: .templates))
        return try take(&templatesOutcomes, label: "templates")
    }

    func createFromTemplate(templateDocumentId: String) async throws {
        recorded.append(.init(kind: .createFromTemplate(templateDocumentId: templateDocumentId)))
        let _: Void = try take(&createOutcomes, label: "createFromTemplate")
    }

    func seedDefaultTemplates() async throws {
        recorded.append(.init(kind: .seedDefaultTemplates))
        let _: Void = try take(&seedOutcomes, label: "seedDefaultTemplates")
    }

    private func take<T>(_ queue: inout [Result<T, Error>], label: String) throws -> T {
        guard !queue.isEmpty else { throw StubError.noOutcome(label: label) }
        switch queue.removeFirst() {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    enum StubError: Error, Equatable {
        case noOutcome(label: String)
    }
}
