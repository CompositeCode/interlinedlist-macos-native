import Foundation
import CoreServices

/// Something that reports batches of changed file URLs.
public protocol FileWatching: Sendable {
    var changes: AsyncStream<[URL]> { get }
    func start()
    func stop()
}

/// Watches the sync folder recursively via FSEvents and yields batched changed
/// URLs. Rapid edits are coalesced by the stream latency.
public final class FSEventsWatcher: FileWatching, @unchecked Sendable {

    public let changes: AsyncStream<[URL]>
    private let continuation: AsyncStream<[URL]>.Continuation
    private let path: String
    private let latency: TimeInterval
    private let queue = DispatchQueue(label: "com.interlinedlist.macos.sync.fsevents")
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private var retainedSelf: UnsafeMutableRawPointer?

    public init(url: URL, latency: TimeInterval = 0.3) {
        self.path = url.path
        self.latency = latency
        var capturedContinuation: AsyncStream<[URL]>.Continuation!
        self.changes = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { capturedContinuation = $0 }
        self.continuation = capturedContinuation
    }

    deinit {
        stop()
        continuation.finish()
    }

    public func start() {
        lock.lock(); defer { lock.unlock() }
        guard stream == nil else { return }

        let info = Unmanaged.passRetained(self).toOpaque()
        retainedSelf = info
        var context = FSEventStreamContext(
            version: 0, info: info, retain: nil, release: nil, copyDescription: nil
        )
        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
        )
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            fsEventsCallback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            Unmanaged<FSEventsWatcher>.fromOpaque(info).release()
            retainedSelf = nil
            return
        }
        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        if let info = retainedSelf {
            Unmanaged<FSEventsWatcher>.fromOpaque(info).release()
            retainedSelf = nil
        }
    }

    fileprivate func emit(paths: [String]) {
        let urls = paths.map { URL(fileURLWithPath: $0) }
        continuation.yield(urls)
    }
}

/// C callback bridge. `eventPaths` is a `CFArray` of `CFString` because the
/// stream is created with `kFSEventStreamCreateFlagUseCFTypes`.
private func fsEventsCallback(
    _ stream: ConstFSEventStreamRef,
    _ clientInfo: UnsafeMutableRawPointer?,
    _ count: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ flags: UnsafePointer<FSEventStreamEventFlags>,
    _ ids: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientInfo else { return }
    let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
    let cfArray = unsafeBitCast(eventPaths, to: CFArray.self)
    let paths = (cfArray as? [String]) ?? []
    guard !paths.isEmpty else { return }
    watcher.emit(paths: paths)
}

/// Test double: a watcher whose changes are pushed manually.
public final class ManualFileWatcher: FileWatching, @unchecked Sendable {
    public let changes: AsyncStream<[URL]>
    private let continuation: AsyncStream<[URL]>.Continuation

    public init() {
        var captured: AsyncStream<[URL]>.Continuation!
        self.changes = AsyncStream { captured = $0 }
        self.continuation = captured
    }

    public func start() {}
    public func stop() { continuation.finish() }
    public func push(_ urls: [URL]) { continuation.yield(urls) }
}
