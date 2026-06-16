import Foundation

/// Iterates over a paginated list endpoint page-by-page, driving the
/// `limit`/`offset` cursor based on each response's `pagination` envelope.
///
/// The fetcher is a closure so the iterator stays endpoint-agnostic: callers
/// hand in something that fetches a given `(limit, offset)` and yields a
/// `Paginated<Item>`. The iterator stops when `pagination.hasMore == false`
/// or the returned page is empty.
///
/// ```swift
/// let iterator = PageIterator<MessageDTO>(pageSize: 50) { limit, offset in
///     try await api.fetchMessages(limit: limit, offset: offset)
/// }
/// for try await page in iterator {
///     for message in page { … }
/// }
/// ```
public struct PageIterator<Item: Decodable & Sendable>: AsyncSequence, Sendable {
    public typealias Element = [Item]

    public let pageSize: Int
    public let fetch: @Sendable (_ limit: Int, _ offset: Int) async throws -> Paginated<Item>

    public init(
        pageSize: Int = 50,
        fetch: @Sendable @escaping (_ limit: Int, _ offset: Int) async throws -> Paginated<Item>
    ) {
        self.pageSize = pageSize
        self.fetch = fetch
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(pageSize: pageSize, fetch: fetch)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        public typealias Element = [Item]

        let pageSize: Int
        let fetch: @Sendable (_ limit: Int, _ offset: Int) async throws -> Paginated<Item>
        var offset: Int = 0
        var done: Bool = false

        public mutating func next() async throws -> [Item]? {
            if done { return nil }
            let page = try await fetch(pageSize, offset)
            if page.items.isEmpty {
                done = true
                return nil
            }
            offset += page.items.count
            if !page.pagination.hasMore {
                done = true
            }
            return page.items
        }
    }
}
