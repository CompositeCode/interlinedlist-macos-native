// AsyncSettle
//
// Shared waiting helpers for App-target tests (GitHub #82).
//
// The rule these encode: **never wait a fixed amount of wall-clock time for an
// asynchronous post-condition.** A `try await Task.sleep(100ms)` after a
// fire-and-forget `Task` passes on an idle machine and fails when the first run
// of a session competes with indexing or a cold build — which is exactly the
// profile of the two unattributable App-target failures that prompted this file.
// A `Task.yield()` is no better: it is not a barrier for work that suspends on
// the clock or on actor scheduling, so a fixed number of yields is just a sleep
// with extra steps.
//
// Poll for the post-condition instead, and fail loudly with the caller's own
// file and line when it never arrives — so the failure names the assertion that
// timed out rather than the assertion that ran too early.

import XCTest

/// Polls `condition` until it holds, then returns. Fails the test at the
/// caller's line if the deadline passes first.
///
/// The tick is deliberately small (1 ms) and the ceiling generous (5 s): a
/// satisfied condition exits on the first pass, so a long ceiling costs nothing
/// on a healthy run and buys tolerance on a loaded machine.
@MainActor
func settle(
    until condition: @MainActor () async -> Bool,
    timeout: Duration = .seconds(5),
    _ message: @autoclosure () -> String = "Condition never became true",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if await condition() { return }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
    // One last read: the loop can exit on the deadline in the same instant the
    // condition becomes true, and failing there would be its own flake.
    if await condition() { return }
    XCTFail("\(message()) within \(timeout)", file: file, line: line)
}

/// Waits a bounded, deliberately short window **without** a post-condition, for
/// assertions that something did *not* happen.
///
/// A negative assertion cannot exit early — there is no event to wait for — so
/// this one genuinely burns its whole budget and is kept small on purpose. Reach
/// for it only when the claim is an absence; every positive assertion belongs in
/// `settle(until:)`.
@MainActor
func settleQuiet(for duration: Duration = .milliseconds(50)) async {
    let deadline = ContinuousClock.now.advanced(by: duration)
    while ContinuousClock.now < deadline {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
}

/// Polls `sample` until two consecutive reads agree, then returns that value.
///
/// For "a loop was stopped" assertions: rather than sleeping past N intervals
/// and hoping no straggler lands between the two reads, wait for the value to
/// stop moving and only then take the baseline. `settleQuiet` afterwards proves
/// it stays put.
@MainActor
func settledValue<T: Equatable>(
    of sample: @MainActor () async -> T,
    timeout: Duration = .seconds(5),
    file: StaticString = #filePath,
    line: UInt = #line
) async -> T {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    var previous = await sample()
    while ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
        let current = await sample()
        if current == previous { return current }
        previous = current
    }
    XCTFail("Value never stopped changing within \(timeout)", file: file, line: line)
    return previous
}
