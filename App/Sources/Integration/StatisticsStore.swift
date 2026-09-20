import Foundation
import Observation
import SeeleseekCore

/// Minimal `StatisticsRecording`: totals for the session, no persistence yet.
@MainActor
@Observable
final class StatisticsStore: StatisticsRecording {
    private(set) var downloadedBytes: UInt64 = 0
    private(set) var uploadedBytes: UInt64 = 0
    private(set) var completedDownloads = 0
    private(set) var completedUploads = 0

    func recordTransfer(
        filename: String,
        username: String,
        size: UInt64,
        duration: TimeInterval,
        isDownload: Bool
    ) {
        if isDownload {
            downloadedBytes += size
            completedDownloads += 1
        } else {
            uploadedBytes += size
            completedUploads += 1
        }
    }
}
