import Foundation

/// Where Typr keeps the Whisper model and how it decides "installed": Application Support (not
/// Documents, not the App Group: the keyboard never needs it), excluded from backup. The layout
/// under `root` is the Hugging Face Hub cache layout, so the downloader writes files in place:
///
///     root/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_626MB/…
///     root/models/openai/whisper-large-v3/{config,tokenizer,tokenizer_config}.json
///     root/typr-whisper-installed.json   (the marker)
///
/// Installed means the marker matches the pinned spec AND every pinned file exists with its exact
/// size. A partial or invalid folder is never installed and never selectable. Typr never deletes
/// the model (Delete is out of scope); a failed or cancelled download leaves its files for Retry.
nonisolated struct WhisperModelStore: Sendable {
    static let markerFileName = "typr-whisper-installed.json"

    /// What the marker records; any difference (another revision) means not installed.
    struct Marker: Codable, Equatable, Sendable {
        var modelRepo = WhisperModelSpec.modelRepo
        var modelRevision = WhisperModelSpec.modelRevision
        var modelFolder = WhisperModelSpec.modelFolderName
        var tokenizerRepo = WhisperModelSpec.tokenizerRepo
        var tokenizerRevision = WhisperModelSpec.tokenizerRevision
        var totalBytes = WhisperModelSpec.totalBytes
    }

    let root: URL

    init(root: URL) {
        self.root = root
    }

    /// `Application Support/Typr/Whisper` in the app's own container.
    static func defaultRoot(fileManager: FileManager = .default) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Typr", isDirectory: true)
            .appendingPathComponent("Whisper", isDirectory: true)
    }

    static var production: WhisperModelStore { WhisperModelStore(root: defaultRoot()) }

    /// The Hub cache folder of one repository, built with the same calls as WhisperKit 1.1.1's
    /// `HubApi.localRepoLocation` (`downloadBase.appending(component: "models").appending(component: id)`)
    /// so both always name the same files.
    func repoFolder(_ repo: String) -> URL {
        root.appending(component: "models").appending(component: repo)
    }

    var modelFolder: URL {
        repoFolder(WhisperModelSpec.modelRepo)
            .appendingPathComponent(WhisperModelSpec.modelFolderName, isDirectory: true)
    }

    var tokenizerFolder: URL {
        repoFolder(WhisperModelSpec.tokenizerRepo)
    }

    var markerURL: URL {
        root.appendingPathComponent(Self.markerFileName)
    }

    func fileURL(for file: WhisperModelSpec.PinnedFile) -> URL {
        repoFolder(file.repo).appending(path: file.path)
    }

    /// The on-disk size, nil when missing or not a regular file.
    func size(of file: WhisperModelSpec.PinnedFile) -> Int64? {
        let url = fileURL(for: file)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true, let size = values.fileSize else { return nil }
        return Int64(size)
    }

    /// Pinned files that are missing or have a different size.
    func invalidFiles(_ files: [WhisperModelSpec.PinnedFile] = WhisperModelSpec.allFiles) -> [WhisperModelSpec.PinnedFile] {
        files.filter { size(of: $0) != $0.bytes }
    }

    var filesComplete: Bool {
        invalidFiles().isEmpty
    }

    /// Bytes of pinned files already present with their exact size.
    var completeBytes: Int64 {
        WhisperModelSpec.allFiles.filter { size(of: $0) == $0.bytes }.reduce(0) { $0 + $1.bytes }
    }

    var hasMarker: Bool {
        guard let data = try? Data(contentsOf: markerURL),
              let marker = try? JSONDecoder().decode(Marker.self, from: data) else { return false }
        return marker == Marker()
    }

    /// Marker plus every pinned file at its exact size. Checked at launch and before every prepare.
    var isInstalled: Bool {
        hasMarker && filesComplete
    }

    /// Creates the root and excludes it (and so everything below it) from iCloud/device backup.
    func prepareRoot(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        var url = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    func writeMarker() throws {
        let data = try JSONEncoder().encode(Marker())
        try data.write(to: markerURL, options: .atomic)
    }

    func removeMarker(fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: markerURL)
    }

    /// Free space for important downloads on the volume holding `root`; nil when unknown.
    func availableCapacity() -> Int64? {
        var probe = root
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe.deleteLastPathComponent()
        }
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
