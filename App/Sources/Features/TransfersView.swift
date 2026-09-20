import SeeleseekCore
import SwiftUI

struct TransfersView: View {
    @Environment(Session.self) private var session

    private var downloads: [Transfer] {
        // Newest first: the row you just queued is the one you want to see.
        session.transfers.downloads.reversed()
    }

    var body: some View {
        NavigationStack {
            Group {
                if downloads.isEmpty {
                    ContentUnavailableView {
                        Label("No downloads", systemImage: "arrow.down.circle")
                    } description: {
                        Text("Files you queue from search appear here.")
                    }
                } else {
                    List {
                        ForEach(downloads) { transfer in
                            TransferRow(transfer: transfer)
                                .swipeActions(edge: .trailing) {
                                    if transfer.canCancel {
                                        Button("Cancel", role: .destructive) {
                                            Task { await session.cancelDownload(transfer.id) }
                                        }
                                    }
                                    if transfer.canRetry {
                                        Button("Retry") {
                                            Task { await session.retryDownload(transfer.id) }
                                        }
                                        .tint(.blue)
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Transfers")
            .toolbar {
                if downloads.contains(where: { !$0.status.isLiveDownloadAttempt }) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") { session.transfers.clearFinished() }
                    }
                }
            }
        }
    }
}

struct TransferRow: View {
    let transfer: Transfer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(transfer.displayFilename)
                .lineLimit(2)

            if transfer.status == .transferring {
                ProgressView(value: transfer.progress)
                    .progressViewStyle(.linear)
            }

            HStack(spacing: 6) {
                Text(statusText)
                    .foregroundStyle(statusColor)
                Text("·")
                Text(transfer.username)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            if let error = transfer.error, transfer.status == .failed {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusText: String {
        switch transfer.status {
        case .queued:
            // The peer's queue, not ours — position comes from the peer and
            // can take a while to arrive.
            if let position = transfer.queuePosition {
                return "Queued (position \(position))"
            }
            return "Queued"
        case .waiting: return "Waiting for peer"
        case .connecting: return "Connecting"
        case .transferring: return "\(Int(transfer.progress * 100))% · \(transfer.formattedSpeed)"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    private var statusColor: Color {
        switch transfer.status {
        case .completed: .green
        case .failed: .red
        case .transferring: .blue
        default: .secondary
        }
    }
}
