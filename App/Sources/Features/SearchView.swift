import SeeleseekCore
import SwiftUI

struct SearchView: View {
    @Environment(Session.self) private var session

    @State private var text = ""
    @State private var filter = SearchFilter()
    @State private var sort = SearchSort.relevance
    @State private var showingFilters = false
    @State private var queueTaps = 0

    /// Extensions actually present in the current results, with counts, so the
    /// chips reflect what this search returned rather than a fixed list.
    private var availableTypes: [(ext: String, count: Int)] {
        Dictionary(grouping: session.results, by: \.fileExtension)
            .filter { !$0.key.isEmpty }
            .map { (ext: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    private var visibleResults: [SearchResult] {
        sort.apply(to: filter.apply(to: session.results))
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleResults.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(visibleResults) { result in
                            Button {
                                queue(result)
                            } label: {
                                SearchResultRow(
                                    result: result,
                                    status: session.transfers.downloadStatus(
                                        username: result.username,
                                        filename: result.filename
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .safeAreaInset(edge: .top) {
                if !session.results.isEmpty {
                    filterBar
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
            .sheet(isPresented: $showingFilters) {
                SearchFiltersSheet(filter: $filter, sort: $sort)
            }
            // Tapping only queues the file with the peer, so without this the
            // tap has no perceptible effect until the peer decides to answer.
            .sensoryFeedback(.success, trigger: queueTaps)
        }
    }

    private func queue(_ result: SearchResult) {
        queueTaps += 1
        Task { await session.download(result) }
    }

    @ViewBuilder
    private var filterBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    FilterChip(title: "All", isOn: filter.fileTypes.isEmpty) {
                        filter.fileTypes.removeAll()
                    }

                    ForEach(availableTypes, id: \.ext) { entry in
                        FilterChip(
                            title: "\(entry.ext.uppercased()) \(entry.count)",
                            isOn: filter.fileTypes.contains(entry.ext)
                        ) {
                            // Multi-select: FLAC plus WAV is a reasonable ask.
                            if filter.fileTypes.contains(entry.ext) {
                                filter.fileTypes.remove(entry.ext)
                            } else {
                                filter.fileTypes.insert(entry.ext)
                            }
                        }
                    }

                    FilterChip(title: "Free slot", isOn: filter.freeSlotsOnly) {
                        filter.freeSlotsOnly.toggle()
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)

            HStack {
                Text("\(visibleResults.count) of \(session.results.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showingFilters = true
                } label: {
                    Label(
                        filter.activeCount > 0 ? "Filters (\(filter.activeCount))" : "Filters",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                    .font(.caption)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var emptyState: some View {
        if session.isSearching {
            // Results arrive from individual peers over several seconds rather
            // than as one response, so an empty list is normal for a while.
            ContentUnavailableView {
                Label("Searching", systemImage: "magnifyingglass")
            } description: {
                Text("Waiting for peers to respond to \(session.query).")
            }
        } else if session.query.isEmpty {
            ContentUnavailableView {
                Label("Search Soulseek", systemImage: "magnifyingglass")
            } description: {
                Text("Search the network for music shared by other users.")
            }
        } else if !session.results.isEmpty {
            ContentUnavailableView {
                Label("Nothing matches", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("\(session.results.count) results are hidden by your filters.")
            } actions: {
                Button("Clear filters") { filter = SearchFilter() }
            }
        } else {
            ContentUnavailableView.search(text: session.query)
        }
    }
}

private struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SearchResultRow: View {
    let result: SearchResult
    let status: Transfer.TransferStatus?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.displayFilename)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(result.username)
                    Text("-")
                    Text(result.formattedSize)
                    if let bitrate = result.formattedBitrate {
                        Text("-")
                        Text(bitrate)
                    }
                    if let duration = result.formattedDuration {
                        Text("-")
                        Text(duration)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                HStack(spacing: 6) {
                    // A free slot means the transfer starts now instead of
                    // sitting in that user's queue, which matters more than raw
                    // speed.
                    Label(
                        result.freeSlots ? "Free slot" : "Queued (\(result.queueLength))",
                        systemImage: result.freeSlots ? "bolt.fill" : "clock"
                    )
                    .foregroundStyle(result.freeSlots ? Color.green : Color.secondary)

                    Text(result.formattedSpeed)
                        .foregroundStyle(.secondary)
                }
                .font(.caption2)
            }

            Spacer(minLength: 0)

            statusIcon
        }
        .padding(.vertical, 2)
    }

    /// The only signal that a tap did anything until the peer responds.
    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case nil:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.tint)
        case .queued, .waiting:
            Image(systemName: "clock.fill")
                .foregroundStyle(.orange)
        case .connecting, .transferring:
            ProgressView()
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "slash.circle")
                .foregroundStyle(.secondary)
        }
    }
}
