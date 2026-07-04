import Foundation
import InterlinedKit

// MARK: - ExportsServicing

/// The CSV export surface the App layer codes against (PLAN.md §1
/// "Data Exports", §6 M7). Covers the four export endpoints: messages,
/// lists, list-data-rows, and follows.
///
/// Each method calls `api.sendRaw` (not `send`) because the export endpoints
/// return a CSV file, not JSON. The raw bytes plus content-type tuple is
/// lifted into a domain `CSVExport` before crossing the seam so callers
/// above the domain layer never reference `InterlinedKit` directly
/// (Decision 0003).
///
/// Follows the same DI shape as all other domain services — takes its
/// `APIClientProtocol` as the sole parameter so unit tests run against a stub.
public protocol ExportsServicing: Sendable {
    /// Exports the signed-in user's messages (`GET /api/exports/messages`).
    func exportMessages() async throws -> CSVExport
    /// Exports the signed-in user's lists (`GET /api/exports/lists`).
    func exportLists() async throws -> CSVExport
    /// Exports list data rows across all lists (`GET /api/exports/list-data-rows`).
    func exportListDataRows() async throws -> CSVExport
    /// Exports follower and following relationships (`GET /api/exports/follows`).
    func exportFollows() async throws -> CSVExport
}

// MARK: - ExportsService

public final class ExportsService: ExportsServicing {

    private let api: APIClientProtocol

    public init(api: APIClientProtocol) {
        self.api = api
    }

    public func exportMessages() async throws -> CSVExport {
        let (data, contentType) = try await api.sendRaw(Exports.messages())
        return CSVExport(data: data, contentType: contentType)
    }

    public func exportLists() async throws -> CSVExport {
        let (data, contentType) = try await api.sendRaw(Exports.lists())
        return CSVExport(data: data, contentType: contentType)
    }

    public func exportListDataRows() async throws -> CSVExport {
        let (data, contentType) = try await api.sendRaw(Exports.listDataRows())
        return CSVExport(data: data, contentType: contentType)
    }

    public func exportFollows() async throws -> CSVExport {
        let (data, contentType) = try await api.sendRaw(Exports.follows())
        return CSVExport(data: data, contentType: contentType)
    }
}
