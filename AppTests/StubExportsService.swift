// StubExportsService
//
// Deterministic `ExportsServicing` stub for App-layer ExportViewModelTests.
// Follows the same FIFO-queue, lock-guarded pattern as the project's other
// service stubs. Returns only `InterlinedDomain` values — no InterlinedKit.

import Foundation
import InterlinedDomain

enum RecordedExportCall: Sendable, Equatable {
    case messages
    case lists
    case listDataRows
    case follows
}

enum StubExportsError: Error, Equatable {
    case noOutcome(label: String)
}

final class StubExportsService: ExportsServicing, @unchecked Sendable {

    private let lock = NSLock()
    private var messagesOutcomes:    [Result<CSVExport, Error>] = []
    private var listsOutcomes:       [Result<CSVExport, Error>] = []
    private var listDataRowsOutcomes:[Result<CSVExport, Error>] = []
    private var followsOutcomes:     [Result<CSVExport, Error>] = []
    private var _recorded: [RecordedExportCall] = []

    var recorded: [RecordedExportCall] {
        lock.lock(); defer { lock.unlock() }
        return _recorded
    }

    // MARK: Test programming

    func enqueueMessages(success csv: CSVExport = .stub()) { enqueue(csv, into: &messagesOutcomes) }
    func enqueueMessages(failure error: Error) { enqueueFailure(error, into: &messagesOutcomes) }

    func enqueueLists(success csv: CSVExport = .stub()) { enqueue(csv, into: &listsOutcomes) }
    func enqueueLists(failure error: Error) { enqueueFailure(error, into: &listsOutcomes) }

    func enqueueListDataRows(success csv: CSVExport = .stub()) { enqueue(csv, into: &listDataRowsOutcomes) }
    func enqueueListDataRows(failure error: Error) { enqueueFailure(error, into: &listDataRowsOutcomes) }

    func enqueueFollows(success csv: CSVExport = .stub()) { enqueue(csv, into: &followsOutcomes) }
    func enqueueFollows(failure error: Error) { enqueueFailure(error, into: &followsOutcomes) }

    // MARK: ExportsServicing

    func exportMessages() async throws -> CSVExport {
        try dequeue(label: "exportMessages", kind: .messages, from: &messagesOutcomes)
    }

    func exportLists() async throws -> CSVExport {
        try dequeue(label: "exportLists", kind: .lists, from: &listsOutcomes)
    }

    func exportListDataRows() async throws -> CSVExport {
        try dequeue(label: "exportListDataRows", kind: .listDataRows, from: &listDataRowsOutcomes)
    }

    func exportFollows() async throws -> CSVExport {
        try dequeue(label: "exportFollows", kind: .follows, from: &followsOutcomes)
    }

    // MARK: - Internals

    private func enqueue(_ csv: CSVExport, into queue: inout [Result<CSVExport, Error>]) {
        lock.lock(); defer { lock.unlock() }
        queue.append(.success(csv))
    }

    private func enqueueFailure(_ error: Error, into queue: inout [Result<CSVExport, Error>]) {
        lock.lock(); defer { lock.unlock() }
        queue.append(.failure(error))
    }

    private func dequeue(
        label: String,
        kind: RecordedExportCall,
        from queue: inout [Result<CSVExport, Error>]
    ) throws -> CSVExport {
        lock.lock()
        _recorded.append(kind)
        guard !queue.isEmpty else {
            lock.unlock()
            throw StubExportsError.noOutcome(label: label)
        }
        let outcome = queue.removeFirst()
        lock.unlock()
        switch outcome {
        case .success(let csv): return csv
        case .failure(let error): throw error
        }
    }
}

private extension CSVExport {
    static func stub(content: String = "id,title\n1,test") -> CSVExport {
        CSVExport(data: Data(content.utf8), contentType: "text/csv")
    }
}
