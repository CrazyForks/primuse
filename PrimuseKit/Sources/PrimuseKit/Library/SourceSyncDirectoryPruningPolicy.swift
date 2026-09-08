import Foundation

public enum SourceSyncDirectoryPruningPolicy {
    public static func confirmedDeletedDirectoryPaths(
        index: [String: SourceSyncIndexedItem],
        deletedKeys: Set<String>
    ) -> Set<String> {
        var pending = deletedKeys.compactMap { key -> String? in
            guard let item = index[key], item.isDirectory else { return nil }
            return item.path
        }
        var children: [String: [String]] = [:]
        for item in index.values where item.isDirectory {
            if let parent = item.parentPath { children[parent, default: []].append(item.path) }
        }
        var result = Set<String>()
        while let path = pending.popLast() {
            guard result.insert(path).inserted else { continue }
            pending.append(contentsOf: children[path] ?? [])
        }
        return result
    }

    /// Follow the current parent links after all authoritative listings have
    /// been applied. Entries moved to a surviving parent are retained.
    public static func orphanedDescendantKeys(
        baseline: [String: SourceSyncIndexedItem],
        current: [String: SourceSyncIndexedItem]
    ) -> Set<String> {
        let survivingDirectoryPaths = Set(current.values.lazy.filter(\.isDirectory).map(\.path))
        var pending = baseline.compactMap { key, item -> String? in
            guard item.isDirectory, current[key] == nil,
                  !survivingDirectoryPaths.contains(item.path) else { return nil }
            return item.path
        }
        var children: [String: [String]] = [:]
        for (key, item) in current {
            if let parent = item.parentPath { children[parent, default: []].append(key) }
        }
        var visited = Set<String>()
        var removed = Set<String>()
        while let path = pending.popLast() {
            guard visited.insert(path).inserted else { continue }
            for key in children[path] ?? [] {
                guard removed.insert(key).inserted, let item = current[key] else { continue }
                if item.isDirectory { pending.append(item.path) }
            }
        }
        return removed
    }
}
