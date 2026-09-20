import SeeleseekCore
import SwiftUI

struct SearchView: View {
    @Environment(Session.self) private var session
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Group {
                if session.results.isEmpty {
                    emptyState
                } else {
                    List(session.results) { result in
                        // Tapping queues with the peer rather than starting a
                        // transfer — the peer decides when a slot frees, so
                        // the row shows up under Transfers as queued.
                        Button {
                            Task { await session.download(result) }
                        } label: {
                            SearchResultRow(result: result)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $text, prompt: "Artist, album, track")
            .onSubmit(of: .search) {
                Task { await session.search(text) }
            }
            .toolbar {
                if session.isSearching {
                    ToolbarItem(placement: .topBarTrailing) { ProgressView() }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if session.isSearching {
            // Results trickle in from individual peers over several seconds
            // rather than arriving as one response, so an empty list here is
            // normal for a while.
            ContentUnavailableView {
                Label("Searching", systemImage: "magnifyingglass")
            } description: {
                Text("Waiting for peers to respond to “\(session.query)”.")
            }
        } else if session.query.isEmpty {
            ContentUnavailableView {
                Label("Search Soulseek", systemImage: "magnifyingglass")
            } description: {
                Text("Search the network for music shared by other users.")
            }
        } else {
            ContentUnavailableView.search(text: session.query)
        }
    }
}

struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.displayFilename)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(result.username)
                Text("·")
                Text(result.formattedSize)
                if let bitrate = result.formattedBitrate {
                    Text("·")
                    Text(bitrate)
                }
                if let duration = result.formattedDuration {
                    Text("·")
                    Text(duration)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            HStack(spacing: 6) {
                // A free slot means the transfer starts now instead of sitting
                // in that user's queue, which matters more than raw speed.
                Label(
                    result.freeSlots ? "Free slot" : "Queued (\(result.queueLength))",
                    systemImage: result.freeSlots ? "bolt.fill" : "clock"
                )
                .foregroundStyle(result.freeSlots ? .green : .secondary)

                Text(result.formattedSpeed)
                    .foregroundStyle(.secondary)
            }
            .font(.caption2)
        }
        .padding(.vertical, 2)
    }
}
