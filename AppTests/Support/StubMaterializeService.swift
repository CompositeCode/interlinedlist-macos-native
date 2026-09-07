// StubMaterializeService
//
// Deterministic `MaterializeServicing` stub for App-layer tests of the
// "Create from…" sheet (work-consolidation.md G16). Records the whole spec, so
// tests can assert the form the user built rather than just the outcome.

import Foundation
import InterlinedDomain

actor StubMaterializeService: MaterializeServicing {

    private var outcomes: [Result<MaterializeOutcome, Error>] = []
    private(set) var recordedSpecs: [MaterializeSpec] = []

    func enqueue(_ value: MaterializeOutcome) { outcomes.append(.success(value)) }
    func enqueue(failure error: Error) { outcomes.append(.failure(error)) }

    func create(_ spec: MaterializeSpec) async throws -> MaterializeOutcome {
        recordedSpecs.append(spec)
        guard !outcomes.isEmpty else { throw UnprogrammedMaterializeCall() }
        return try outcomes.removeFirst().get()
    }
}

/// Thrown when a test exercises a create the stub was not programmed for.
struct UnprogrammedMaterializeCall: Error, CustomStringConvertible {
    var description: String { "StubMaterializeService: no queued outcome" }
}
