import Foundation
import SeeleseekCore

/// One peer's folder, with the matching files inside it.
///
/// A search for an album returns a row per track, so twelve rows that are really
/// one thing. Grouping restores that: peers share whole directories, and the
/// path already tells us which files belong together. It also makes "get the
/// whole album" one action instead of twelve taps.
struct ResultFolder: Identifiable {
    let id: String
    let username: String
    let folder: String
    let files: [SearchResult]

    var fileCount: Int { files.count }

    var totalSize: UInt64 {
        files.reduce(0) { $0 + $1.size }
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
    }

    /// Slot state is a property of the peer, not the file, so any one file
    /// answers for the folder.
    var freeSlots: Bool { files.first?.freeSlots ?? false }

    var queueLength: UInt32 { files.first?.queueLength ?? 0 }

    var uploadSpeed: UInt32 { files.first?.uploadSpeed ?? 0 }

    /// Extensions present, most common first — an album is usually one format,
    /// but a folder can mix in a cue sheet, a log or artwork.
    var types: [String] {
        Dictionary(grouping: files, by: \.fileExtension)
            .filter { !$0.key.isEmpty }
            .sorted { $0.value.count > $1.value.count }
            .map(\.key)
    }

    /// The last path component, which is the album folder in nearly every
    /// share layout. Falls back to the peer name for loose files at the root.
    var displayName: String {
        guard !folder.isEmpty else { return "Loose files" }
        return folder.split(separator: "/").last.map(String.init) ?? folder
    }

    /// Groups results while preserving arrival order, which roughly tracks
    /// which peers answered fastest — information a re-sort would discard.
    static func group(_ results: [SearchResult]) -> [ResultFolder] {
        var order: [String] = []
        var buckets: [String: [SearchResult]] = [:]

        for result in results {
            // NUL cannot occur in a username or a Soulseek path, so it cannot
            // collide the way a printable separator could.
            let key = "\(result.username)\u{0}\(result.folderPath)"
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key]?.append(result)
        }

        return order.compactMap { key in
            guard let files = buckets[key], let first = files.first else { return nil }
            return ResultFolder(
                id: key,
                username: first.username,
                folder: first.folderPath,
                files: files
            )
        }
    }
}
