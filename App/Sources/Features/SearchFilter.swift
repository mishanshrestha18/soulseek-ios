import Foundation
import SeeleseekCore

/// Result filtering, modelled on the desktop client's filter bar: file type,
/// free slots, a bitrate floor, a size floor and excluded words.
///
/// Kept as a value type with a pure `apply` so the rules are independent of the
/// view that presents them.
struct SearchFilter: Equatable {
    /// Lowercased extensions. Empty means every type, which is the default —
    /// a search for an album should not silently hide the cue sheet or the log.
    var fileTypes: Set<String> = []
    var freeSlotsOnly = false
    var losslessOnly = false
    /// Ignored for lossless results, which report no meaningful bitrate.
    var minBitrate = 0
    var minSizeMB = 0
    /// Space-separated words; a result matching any of them is dropped.
    /// The desktop client's exclusion field behaves the same way.
    var excluded = ""

    static let bitrateOptions = [0, 128, 192, 256, 320]
    static let sizeOptions = [0, 1, 5, 10, 50]

    var isActive: Bool { self != SearchFilter() }

    /// Count of distinct constraints in use, for the badge on the filter button.
    var activeCount: Int {
        var count = 0
        if !fileTypes.isEmpty { count += 1 }
        if freeSlotsOnly { count += 1 }
        if losslessOnly { count += 1 }
        if minBitrate > 0 { count += 1 }
        if minSizeMB > 0 { count += 1 }
        if !excludedWords.isEmpty { count += 1 }
        return count
    }

    var excludedWords: [String] {
        excluded
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    func apply(to results: [SearchResult]) -> [SearchResult] {
        let words = excludedWords
        let minBytes = UInt64(minSizeMB) * 1_048_576

        return results.filter { result in
            if !fileTypes.isEmpty, !fileTypes.contains(result.fileExtension) { return false }
            if losslessOnly, !result.isLossless { return false }
            if freeSlotsOnly, !result.freeSlots { return false }
            if result.size < minBytes { return false }

            // A lossless file has no bitrate worth comparing, so a bitrate
            // floor must not exclude the highest-quality results.
            if minBitrate > 0, !result.isLossless {
                guard let bitrate = result.bitrate, Int(bitrate) >= minBitrate else { return false }
            }

            if !words.isEmpty {
                let haystack = result.filename.lowercased()
                if words.contains(where: haystack.contains) { return false }
            }
            return true
        }
    }
}

/// Sort orders matching the columns the desktop client lets you sort on.
enum SearchSort: String, CaseIterable, Identifiable {
    case relevance
    case bitrate
    case size
    case speed
    case queue

    var id: String { rawValue }

    var label: String {
        switch self {
        case .relevance: "Default"
        case .bitrate: "Bitrate"
        case .size: "Size"
        case .speed: "Speed"
        case .queue: "Queue"
        }
    }

    /// `relevance` keeps arrival order: results stream in from peers roughly
    /// best-responder-first, which is information a re-sort throws away.
    func apply(to results: [SearchResult]) -> [SearchResult] {
        switch self {
        case .relevance: results
        case .bitrate: results.sorted { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }
        case .size: results.sorted { $0.size > $1.size }
        case .speed: results.sorted { $0.uploadSpeed > $1.uploadSpeed }
        case .queue: results.sorted { $0.queueLength < $1.queueLength }
        }
    }
}
