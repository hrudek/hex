import Foundation

/// A single serial writer with one replaceable pending snapshot. The lock protects only
/// the mailbox; no I/O or callbacks run while it is held. All payloads crossing it are Sendable.
final class DictationLogStorage: @unchecked Sendable {
    static let maximumBytes = 1_000_000
    let url: URL
    private let queue = DispatchQueue(label: "hexplus.dictation-log", qos: .utility)
    private let lock = NSLock()
    private struct Request: Sendable {
        let data: Data? // nil means delete
        let epoch: UInt64
        let completion: @Sendable (UInt64, Bool) -> Void
    }
    private var latest: Request?
    private var newestEpoch: UInt64 = 0
    private var draining = false

    init(url: URL) { self.url = url }

    /// Only called once by a new store, before it can submit writes. Bounded synchronous
    /// launch read deliberately avoids an async load/clear/merge race.
    func load(enabled: Bool) -> (entries: [DictationLogEntry], problem: Bool) {
        let fm = FileManager.default
        guard enabled else { return ([], !delete()) }
        guard fm.fileExists(atPath: url.path) else { return ([], false) }
        do {
            let attributes = try fm.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber,
                  size.intValue <= Self.maximumBytes else { return ([], !delete()) }
            // A capped read even if a file grew between stat and open.
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
            guard data.count <= Self.maximumBytes,
                  let document = try? JSONDecoder().decode(DictationLogDocument.self, from: data),
                  document.schemaVersion == DictationLogDocument.version,
                  document.entries.allSatisfy({ $0.schemaVersion == DictationLogDocument.version }) else {
                return ([], !delete())
            }
            return (document.entries, false)
        } catch {
            // An unreadable/corrupt log must never prevent launch or leak error descriptions.
            return ([], !delete())
        }
    }

    func submit(_ data: Data?, epoch: UInt64, completion: @escaping @Sendable (UInt64, Bool) -> Void) {
        lock.lock()
        guard epoch >= newestEpoch else { lock.unlock(); return }
        newestEpoch = epoch
        latest = Request(data: data, epoch: epoch, completion: completion)
        let start = !draining
        draining = true
        lock.unlock()
        if start { queue.async { self.drain() } }
    }

    private func next() -> Request? {
        lock.lock()
        defer { lock.unlock() }
        guard let request = latest else { draining = false; return nil }
        latest = nil
        return request
    }

    private func isCurrent(_ epoch: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return epoch == newestEpoch
    }

    private func drain() {
        while let request = next() {
            guard isCurrent(request.epoch) else { continue }
            // A clear racing a write already in progress queues a delete after that write.
            // Nothing can execute out of order or put an old snapshot back after the delete.
            let success = request.data.map(write) ?? delete()
            request.completion(request.epoch, success)
        }
    }

    private func delete() -> Bool {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return true
        } catch { return false }
    }

    private func write(_ data: Data) -> Bool {
        let fm = FileManager.default
        do {
            let directory = url.deletingLastPathComponent()
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var excludedDirectory = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try excludedDirectory.setResourceValues(values)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            // Atomic replacement creates a new inode; re-apply protection and backup exclusion.
            try fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
            var excludedFile = url
            try excludedFile.setResourceValues(values)
            return true
        } catch { return false }
    }

    /// Test barrier only; dictation never waits for disk.
    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }
}
