import Foundation
import Observation
import SeeleseekCore

/// iOS has no user-chosen download folder. Finished files land in the app's
/// Documents directory, which `UIFileSharingEnabled` and
/// `LSSupportsOpeningDocumentsInPlace` surface in the Files app, so they are
/// reachable without an explicit export step.
@MainActor
@Observable
final class DownloadSettings: DownloadSettingsProviding {
    let downloadLocation: URL
    let incompleteDownloadDirectory: URL

    /// Tag-based templates (`{artist}`, `{album}`) make `DownloadManager`
    /// re-derive the final path from file tags and move the file again after
    /// it lands. The path-based default needs no metadata and no second move.
    var activeDownloadTemplate: String = DownloadManager.fallbackTemplate

    /// A macOS affordance — directories have no custom icons on iOS.
    let setFolderIcons = false

    init() {
        let documents = URL.documentsDirectory
        downloadLocation = documents.appending(path: "Downloads", directoryHint: .isDirectory)

        // Deliberately not Caches: iOS evicts that under storage pressure, and
        // a partial transfer disappearing mid-download would strand the row.
        // Application Support is backed up and never reclaimed behind our back.
        incompleteDownloadDirectory = URL.applicationSupportDirectory
            .appending(path: "Incomplete", directoryHint: .isDirectory)

        for directory in [downloadLocation, incompleteDownloadDirectory] {
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
    }

    var snapshot: DownloadSettingsSnapshot {
        DownloadSettingsSnapshot(from: self)
    }
}
