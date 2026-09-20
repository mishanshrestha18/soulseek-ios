import Foundation
import Observation
import SeeleseekCore

/// The app side of `TransferTracking`. `DownloadManager` drives this; the UI
/// only reads it.
@MainActor
@Observable
final class TransferStore: TransferTracking {
    private(set) var downloads: [Transfer] = []
    private(set) var uploads: [Transfer] = []

    // `findSalvageableDownload` runs on every unsolicited TransferRequest and
    // the protocol requires it stay O(1) in history size, so both lookups are
    // indexed rather than scanned. Positions stay valid because rows are only
    // appended; anything that removes rows rebuilds the indexes.
    private var downloadIDsByPeerFile: [String: [UUID]] = [:]
    private var downloadPositions: [UUID: Int] = [:]
    private var uploadPositions: [UUID: Int] = [:]

    // MARK: - TransferTracking

    func addDownload(_ transfer: Transfer) {
        downloadPositions[transfer.id] = downloads.count
        downloads.append(transfer)
        downloadIDsByPeerFile[Self.key(transfer.username, transfer.filename), default: []]
            .append(transfer.id)
    }

    func addUpload(_ transfer: Transfer) {
        uploadPositions[transfer.id] = uploads.count
        uploads.append(transfer)
    }

    func updateTransfer(id: UUID, update: @Sendable (inout Transfer) -> Void) {
        if let index = downloadPositions[id] {
            update(&downloads[index])
        } else if let index = uploadPositions[id] {
            update(&uploads[index])
        }
    }

    func getTransfer(id: UUID) -> Transfer? {
        if let index = downloadPositions[id] { return downloads[index] }
        if let index = uploadPositions[id] { return uploads[index] }
        return nil
    }

    func findSalvageableDownload(username: String, filename: String) -> Transfer? {
        guard let ids = downloadIDsByPeerFile[Self.key(username, filename)] else { return nil }

        // Newest first: re-queuing the same file leaves the older, settled row
        // in place, and it is the live attempt the peer is answering.
        for id in ids.reversed() {
            guard let index = downloadPositions[id] else { continue }
            let transfer = downloads[index]
            switch transfer.status {
            case .queued, .waiting, .connecting:
                return transfer
            case .transferring, .completed, .failed, .cancelled:
                continue
            }
        }
        return nil
    }

    // MARK: - App-side mutation

    /// Drops settled rows and rebuilds the indexes, since positions shift.
    func clearFinished() {
        downloads.removeAll { !$0.status.isLiveDownloadAttempt }
        uploads.removeAll { !$0.status.isLiveDownloadAttempt }
        reindex()
    }

    private func reindex() {
        downloadPositions.removeAll(keepingCapacity: true)
        downloadIDsByPeerFile.removeAll(keepingCapacity: true)
        uploadPositions.removeAll(keepingCapacity: true)

        for (index, transfer) in downloads.enumerated() {
            downloadPositions[transfer.id] = index
            downloadIDsByPeerFile[Self.key(transfer.username, transfer.filename), default: []]
                .append(transfer.id)
        }
        for (index, transfer) in uploads.enumerated() {
            uploadPositions[transfer.id] = index
        }
    }

    /// NUL cannot appear in a username or a Soulseek path, so it cannot
    /// collide the way a printable separator could.
    private static func key(_ username: String, _ filename: String) -> String {
        "\(username)\u{0}\(filename)"
    }
}
