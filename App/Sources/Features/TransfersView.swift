import SeeleseekCore
import SwiftUI

struct TransfersView: View {
    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var player = AudioPlayerModel()

    private var downloads: [Transfer] {
        // Newest first: the row you just queued is the one you want to see.
        // `reversed()` on an Array is a ReversedCollection view, not an Array.
        Array(session.transfers.downloads.reversed())
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
                            TransferRow(transfer: transfer, player: player)
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
                                .contextMenu {
                                    if let url = transfer.localPath, transfer.status == .completed {
                                        ShareLink(item: url) {
                                            Label("Share", systemImage: "square.and.arrow.up")
                                        }
                                        Button {
                                            showInFiles(url)
                                        } label: {
                                            Label("Show in Files", systemImage: "folder")
                                        }
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if player.currentURL != nil {
                    PlayerBar(player: player)
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

    /// Files.app opens a `shareddocuments://` path inside a container it can
    /// see, which ours is because the app sets `UIFileSharingEnabled`. The scheme
    /// is long-standing but not formally documented, so the Share action is the
    /// supported route and this is the convenience.
    private func showInFiles(_ url: URL) {
        guard let filesURL = URL(string: "shareddocuments://" + url.path) else { return }
        openURL(filesURL)
    }
}

// MARK: - Row

private struct TransferRow: View {
    let transfer: Transfer
    let player: AudioPlayerModel

    private var playableURL: URL? {
        guard transfer.status == .completed, transfer.isAudioFile else { return nil }
        return transfer.localPath
    }

    var body: some View {
        HStack(spacing: 12) {
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
                    Text("-")
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

            Spacer(minLength: 0)

            if let url = playableURL {
                Button {
                    Task { await player.toggle(url: url) }
                } label: {
                    Image(systemName: player.isCurrent(url) && player.isPlaying
                          ? "pause.circle.fill"
                          : "play.circle.fill")
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusText: String {
        switch transfer.status {
        case .queued:
            // The peer's queue, not ours — position comes from the peer and can
            // take a while to arrive.
            if let position = transfer.queuePosition {
                return "Queued (position \(position))"
            }
            return "Queued"
        case .waiting: return "Waiting for peer"
        case .connecting: return "Connecting"
        case .transferring: return "\(Int(transfer.progress * 100))% - \(transfer.formattedSpeed)"
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

// MARK: - Player

private struct PlayerBar: View {
    let player: AudioPlayerModel

    var body: some View {
        VStack(spacing: 6) {
            if let url = player.currentURL {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }

            Slider(
                value: Binding(
                    get: { player.progress },
                    set: { player.seek(toFraction: $0) }
                )
            )
            .disabled(player.duration <= 0)

            HStack {
                Text(Self.time(player.currentTime))
                Spacer()
                Text(Self.time(player.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)

            HStack(spacing: 28) {
                Button {
                    player.skip(by: -AudioPlayerModel.skipInterval)
                } label: {
                    Image(systemName: "gobackward.10")
                }

                Button {
                    guard let url = player.currentURL else { return }
                    Task { await player.toggle(url: url) }
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 24)
                }

                Button {
                    player.skip(by: AudioPlayerModel.skipInterval)
                } label: {
                    Image(systemName: "goforward.10")
                }

                Button {
                    player.stop()
                } label: {
                    Image(systemName: "xmark")
                }
                .foregroundStyle(.secondary)
            }
            .imageScale(.large)
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
