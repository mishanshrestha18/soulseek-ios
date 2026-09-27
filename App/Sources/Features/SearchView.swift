import SeeleseekCore
import SwiftUI

struct SearchView: View {
    @Environment(Session.self) private var session

    @State private var text = ""
    @State private var filter = SearchFilter()
    @State private var sort = SearchSort.relevance
    @State private var groupByFolder = false
    @State private var showingFilters = false
    @State private var showingFields = false
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

    private var folders: [ResultFolder] {
        ResultFolder.group(visibleResults)
    }

    /// A rescue for a multi-word query that no peer answered while its
    /// individual words do get answers — "linkin park" draws nothing, "linkin"
    /// draws 55 peers. Whatever upstream filtering causes that is not reachable
    /// from here, but the intended search is: send the word the network will
    /// carry and require the rest locally.
    ///
    /// Picks the longest word to send, as the most distinctive and so the one
    /// returning the least noise to narrow.
    private var splitSuggestion: (send: String, require: String)? {
        guard !session.isSearching, session.searchReplyCount == 0 else { return nil }
        let terms = session.query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard terms.count >= 2, let pivot = terms.max(by: { $0.count < $1.count }) else {
            return nil
        }
        let rest = terms.filter { $0.caseInsensitiveCompare(pivot) != .orderedSame }
        guard !rest.isEmpty else { return nil }
        return (pivot, rest.joined(separator: " "))
    }

    private func runSplit(_ split: (send: String, require: String)) {
        filter.required = split.require
        text = split.send
        Task { await session.search(split.send) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleResults.isEmpty {
                    emptyState
                } else if groupByFolder {
                    List {
                        ForEach(folders) { folder in
                            FolderRow(folder: folder, onQueue: queue, onQueueAll: queueAll)
                        }
                    }
                    .listStyle(.plain)
                } else {
                    List {
                        ForEach(visibleResults) { result in
                            resultButton(result)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    if let notice = session.searchNotice {
                        NoticeBanner(text: notice)
                    }
                    if !session.results.isEmpty {
                        filterBar
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(
                text: $text,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Artist album track"
            )
            .onSubmit(of: .search) {
                Task { await session.search(text) }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if session.isSearching {
                        ProgressView()
                    } else {
                        Button {
                            showingFields = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                SearchFiltersSheet(filter: $filter, sort: $sort, groupByFolder: $groupByFolder)
            }
            .sheet(isPresented: $showingFields) {
                GuidedSearchSheet { built in
                    text = built
                    Task { await session.search(built) }
                }
            }
            // Tapping only queues the file with the peer, so without this the
            // tap has no perceptible effect until the peer decides to answer.
            .sensoryFeedback(.success, trigger: queueTaps)
        }
    }

    private func resultButton(_ result: SearchResult) -> some View {
        Button {
            queue(result)
        } label: {
            SearchResultRow(
                result: result,
                snapshot: session.transfers.downloadSnapshot(
                    username: result.username,
                    filename: result.filename
                )
            )
        }
        .buttonStyle(.plain)
    }

    private func queue(_ result: SearchResult) {
        queueTaps += 1
        Task { await session.download(result) }
    }

    private func queueAll(_ folder: ResultFolder) {
        queueTaps += 1
        Task { await session.downloadAll(folder.files) }
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

                    FilterChip(title: "Folders", isOn: groupByFolder) {
                        groupByFolder.toggle()
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)

            HStack {
                Text(groupByFolder
                     ? "\(folders.count) folders, \(visibleResults.count) files"
                     : "\(visibleResults.count) of \(session.results.count)")
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
                Text("Peers match every word against the file's folder path, so artist, album and track together works best.")
            } actions: {
                Button("Search by artist and album") { showingFields = true }
            }
        } else if !session.results.isEmpty {
            ContentUnavailableView {
                Label("Nothing matches", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("\(session.results.count) results are hidden by your filters.")
            } actions: {
                Button("Clear filters") { filter = SearchFilter() }
            }
        } else if let split = splitSuggestion {
            ContentUnavailableView {
                Label("No peer answered", systemImage: "exclamationmark.magnifyingglass")
            } description: {
                Text("Some phrases draw no replies even when their words do. Search \(split.send) instead and require \(split.require) in the results.")
            } actions: {
                Button("Search \(split.send), require \(split.require)") {
                    runSplit(split)
                }
                Button("Search by artist and album") { showingFields = true }
            }
        } else {
            ContentUnavailableView {
                Label("No results", systemImage: "magnifyingglass")
            } description: {
                Text("No peer answered for \(session.query). Fewer, more distinctive words usually work better — try the artist and album without the track name.")
            } actions: {
                Button("Search by artist and album") { showingFields = true }
            }
        }
    }
}

// MARK: - Folder row

private struct FolderRow: View {
    let folder: ResultFolder
    let onQueue: (SearchResult) -> Void
    let onQueueAll: (ResultFolder) -> Void

    @Environment(Session.self) private var session

    var body: some View {
        DisclosureGroup {
            ForEach(folder.files) { file in
                Button {
                    onQueue(file)
                } label: {
                    SearchResultRow(
                        result: file,
                        snapshot: session.transfers.downloadSnapshot(
                            username: file.username,
                            filename: file.filename
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(folder.displayName)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(folder.username)
                        Text("-")
                        Text("\(folder.fileCount) files")
                        Text("-")
                        Text(folder.formattedSize)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                    HStack(spacing: 6) {
                        Label(
                            folder.freeSlots ? "Free slot" : "Queued (\(folder.queueLength))",
                            systemImage: folder.freeSlots ? "bolt.fill" : "clock"
                        )
                        .foregroundStyle(folder.freeSlots ? Color.green : Color.secondary)

                        if !folder.types.isEmpty {
                            Text(folder.types.prefix(3).map { $0.uppercased() }.joined(separator: " "))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption2)
                }

                Spacer(minLength: 0)

                Button {
                    onQueueAll(folder)
                } label: {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                // Without this the disclosure arrow swallows the tap.
                .contentShape(Rectangle())
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Small pieces

private struct NoticeBanner: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.yellow.opacity(0.2))
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
    let snapshot: DownloadSnapshot?

    var body: some View {
        HStack(spacing: 12) {
            // Leading, so the state of every row reads down a single column
            // instead of against a ragged right edge of varying name lengths.
            statusIcon
                .frame(width: 32)

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
        }
        .padding(.vertical, 2)
    }

    /// The only signal that a tap did anything until the peer responds.
    @ViewBuilder
    private var statusIcon: some View {
        switch snapshot?.status {
        case nil:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.tint)
        case .queued, .waiting:
            Image(systemName: "clock.fill")
                .foregroundStyle(.orange)
        case .connecting:
            // No bytes have moved yet, so there is no fraction to draw.
            ProgressView()
        case .transferring:
            DownloadProgressRing(fraction: snapshot?.fraction ?? 0)
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
