import Foundation

/// A preference or thermal event can resize a live queue without cancelling
/// reads, replaying completed files, or waiting for a whole snapshot to drain.
@MainActor
public final class MetadataReadScheduler<Item: Sendable, Outcome: Sendable> {
    private enum Event: Sendable {
        case completed(Item, Outcome)
        case configurationChanged
        case cancelled
    }

    public private(set) var inFlightCount = 0
    private var signal: (@Sendable () -> Void)?

    public init() {}

    public func configurationChanged() { signal?() }

    @discardableResult
    public func run(
        items: [Item],
        limits: @escaping @MainActor () -> MetadataBackfillExecutionLimits,
        shouldRead: @escaping @MainActor (Item) -> Bool = { _ in true },
        priority: TaskPriority = .utility,
        read: @escaping @MainActor @Sendable (Item) async -> Outcome,
        completed: @escaping @MainActor (Item, Outcome) async -> Void
    ) async -> Bool {
        let (events, continuation) = AsyncStream<Event>.makeStream()
        signal = { continuation.yield(.configurationChanged) }
        defer {
            signal = nil
            inFlightCount = 0
            continuation.finish()
        }
        var didCancel = false
        await withTaskGroup(of: Void.self) { group in
            defer { group.cancelAll() }
            var nextIndex = 0
            continuation.yield(.configurationChanged)
            for await event in events {
                guard !Task.isCancelled else { break }
                if case .cancelled = event { didCancel = true; break }
                if case .completed(let item, let outcome) = event {
                    inFlightCount -= 1
                    await completed(item, outcome)
                }
                let budget = limits()
                while !Task.isCancelled,
                      inFlightCount < budget.workerCount,
                      nextIndex < items.count {
                    let item = items[nextIndex]
                    nextIndex += 1
                    guard shouldRead(item) else { continue }
                    inFlightCount += 1
                    group.addTask(priority: priority) {
                        if budget.interRequestDelay > 0 {
                            do {
                                try await Task.sleep(for: .seconds(budget.interRequestDelay))
                            } catch { return }
                        }
                        guard !Task.isCancelled else { return }
                        let outcome = await read(item)
                        continuation.yield(Task.isCancelled ? .cancelled : .completed(item, outcome))
                    }
                }
                if nextIndex == items.count && inFlightCount == 0 { break }
            }
        }
        return didCancel || Task.isCancelled
    }
}
