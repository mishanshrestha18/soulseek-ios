import Foundation
import Observation
import SeeleseekCore

/// Owns the `NetworkClient` and the transfer managers, and republishes the
/// parts of the event stream the UI observes. Everything here is MainActor;
/// the core's actors are only touched through `await`.
@MainActor
@Observable
final class Session {
    /// The official server. Port 2242 is the modern one; 2240 is legacy and
    /// is not used here.
    static let defaultServer = "server.slsknet.org"
    static let defaultPort: UInt16 = 2242

    private(set) var status: ConnectionStatus = .disconnected
    private(set) var lastError: String?

    /// The server's raw login rejection reason, when the last attempt failed
    /// because of the credentials rather than the network. Kept separate from
    /// `lastError` so stored credentials are only discarded when the server
    /// actually rejected them — a dropped connection must not wipe a password
    /// that works.
    private(set) var loginRejection: String?

    private(set) var results: [SearchResult] = []
    private(set) var isSearching = false
    private(set) var query = ""

    /// Something the user should know about the search they just ran — that it
    /// was rewritten, or that the network refuses to carry it.
    private(set) var searchNotice: String?

    /// Phrases the server says are not allowed on the search network. Peers are
    /// required to leave matching paths out of their replies, so a query
    /// containing one comes back empty no matter how common the music is. The
    /// server pushes this list after login; until it arrives the list is empty.
    private(set) var excludedPhrases: [String] = []

    /// Whether the server has actually sent the list. Without this an empty
    /// list is ambiguous — it could mean nothing is blocked, or that the list
    /// never arrived, and those call for completely different conclusions.
    private(set) var receivedExcludedPhrases = false

    /// How many peers replied to the current search, as distinct from how many
    /// files came back. Zero replies means nothing reached us at all, which is a
    /// different problem from peers replying with no matches.
    private(set) var searchReplyCount = 0

    /// Re-floods the query once when the first attempt draws nothing. The server
    /// distributes a search across a subset of the network, so a second pass
    /// reaches a different set of peers — the same reason the desktop client's
    /// wishlist re-runs queries on an interval.
    private(set) var searchRetried = false
    static let searchRetryDelay = Duration.seconds(8)

    /// Whether peers can reach us, and whether we are in the search tree.
    ///
    /// Search replies arrive by a peer opening a connection *to us*, so if we
    /// are unreachable every reply depends on the server-brokered indirect
    /// path. That makes reachability the first thing to check when searches go
    /// unanswered.
    struct Connectivity: Equatable {
        var listenPort: UInt16 = 0
        var externalIP: String?
        var localIP: String?
        var natGateway: String?
        var mappedPorts: [UInt16] = []
        var hasDistributedParent = false

        /// A different external address with no port mapping means inbound
        /// connections do not arrive — the normal situation on cellular, where
        /// the carrier NAT cannot be traversed at all.
        var inboundLikelyBlocked: Bool {
            guard let externalIP, let localIP else { return true }
            return externalIP != localIP && mappedPorts.isEmpty
        }
    }

    private(set) var connectivity = Connectivity()

    let client = NetworkClient()
    let transfers = TransferStore()
    let statistics = StatisticsStore()
    let settings = DownloadSettings()

    // DownloadManager holds its UploadManager weakly, so the strong reference
    // has to live here or the upload side silently disappears. Uploads are
    // not a v1 feature, but the manager still has to exist to answer peers
    // that ask us for files.
    private let uploadManager = UploadManager()
    private let downloadManager = DownloadManager()

    /// Results arrive asynchronously from many peers and are matched to the
    /// search that asked for them by token, so results from a previous search
    /// are dropped rather than mixed into the current list.
    ///
    /// Every token belonging to the current query. A retry adds a token rather
    /// than replacing one, because replies to the first flood keep arriving
    /// after the second is sent — discarding them would throw away the very
    /// results the retry was meant to find.
    private var activeTokens: Set<UInt32> = []

    /// Nothing in the protocol says "that search is over" — replies simply stop
    /// arriving. Without a deadline the spinner runs forever on a query nobody
    /// answers, which reads as the app being stuck.
    private var searchDeadline: Task<Void, Never>?
    static let searchTimeout = Duration.seconds(20)

    init() {
        observeConnection()
        observeSearch()
        configureManagers()
    }

    var isConnected: Bool { status == .connected }

    // MARK: - Setup

    private func configureManagers() {
        let reader = MetadataReader()
        let snapshot = settings.snapshot
        let client = client
        let transfers = transfers
        let statistics = statistics
        let uploadManager = uploadManager
        let downloadManager = downloadManager

        Task {
            await client.setMetadataReader(reader)
            await downloadManager.configure(
                networkClient: client,
                transferState: transfers,
                statisticsState: statistics,
                uploadManager: uploadManager,
                settings: snapshot,
                metadataReader: reader
            )
            await uploadManager.configure(
                networkClient: client,
                transferState: transfers,
                shareManager: client.shareManager,
                statisticsState: statistics
            )
            // Re-arms retry timers persisted by a previous run; without it a
            // row left in .failed keeps a scheduled retry that never fires.
            await downloadManager.rearmPersistedRetries()
        }
    }

    // MARK: - Connection

    func connect(username: String, password: String) async {
        guard !username.isEmpty, !password.isEmpty else { return }
        lastError = nil
        status = .connecting
        await client.connect(
            server: Self.defaultServer,
            port: Self.defaultPort,
            username: username,
            password: password
        )

        // `connect` reports failure through state rather than by throwing.
        // A rejected login is the common case worth surfacing — the server
        // gives a reason string, and there is no password reset, so the user
        // needs to see exactly what it said.
        if await !client.loggedIn {
            let reason = await client.connectionError
            loginRejection = reason
            lastError = Self.explain(reason)
        } else {
            loginRejection = nil
        }
    }

    /// True when the server rejected the credentials themselves. A timeout or
    /// socket error is not this, and must not cause a working password to be
    /// thrown away.
    var credentialsRejected: Bool {
        guard let reason = loginRejection else { return false }
        return ["INVALIDPASS", "INVALIDUSERNAME", "EMPTYPASSWORD"]
            .contains { reason.contains($0) }
    }

    /// The wire reasons are bare tokens like `INVALIDPASS`, which tell the user
    /// nothing. INVALIDPASS is the confusing one: Soulseek registers an account
    /// on first login, so it means the name is already taken by somebody else
    /// far more often than it means a typo.
    private static func explain(_ reason: String?) -> String {
        guard let reason else { return "Could not sign in." }

        if reason.contains("INVALIDPASS") {
            return "That username is already registered to someone else, and "
                + "the password does not match it. Soulseek creates your "
                + "account on first login, so choose a different, more "
                + "distinctive username — unless the account is yours, in "
                + "which case check the password."
        }
        if reason.contains("EMPTYPASSWORD") {
            return "The password cannot be empty."
        }
        if reason.contains("INVALIDUSERNAME") {
            // The server appends a detail: empty, too long (max 30 characters),
            // non-printable-ASCII, or leading/trailing spaces.
            return "That username is not allowed. \(reason)"
        }
        if reason.contains("INVALIDVERSION") {
            return "The server rejected this client version."
        }
        if reason.contains("SVRFULL") {
            return "The server is not accepting connections right now. Try again shortly."
        }
        if reason.contains("SVRPRIVATE") {
            return "The server is not accepting new account registrations."
        }
        return reason
    }

    func disconnect() async {
        await client.disconnectAsync()
        results = []
        activeTokens.removeAll()
        isSearching = false
    }

    // MARK: - Search

    func search(_ text: String) async {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Peers match terms against the file path, so punctuation the user typed
        // as a separator has to go or it becomes a term nothing can satisfy.
        let normalized = SearchQueryBuilder.normalize(raw)
        guard !normalized.isEmpty, isConnected else { return }

        // Zero is a valid token but is used as a sentinel by enough clients
        // that it is worth avoiding.
        let token = UInt32.random(in: 1...UInt32.max)
        activeTokens = [token]
        query = normalized
        results = []
        searchReplyCount = 0
        searchRetried = false
        isSearching = true
        searchNotice = notice(raw: raw, normalized: normalized)

        await send(normalized, token: token)
    }

    private func send(_ normalized: String, token: UInt32) async {
        do {
            try await client.search(query: normalized, token: token)
            startSearchDeadline(for: token)
        } catch {
            isSearching = false
            lastError = error.localizedDescription
        }
    }

    /// Re-issues the current query under a fresh token. A new token means a new
    /// flood through the distributed network, reaching peers the first pass
    /// missed. The earlier token stays live so its replies still count.
    private func retrySearch() async {
        guard !query.isEmpty, isConnected else { return }
        searchRetried = true
        let token = UInt32.random(in: 1...UInt32.max)
        activeTokens.insert(token)
        await send(query, token: token)
    }

    /// Explains anything surprising about this search before the user waits
    /// twenty seconds for nothing.
    private func notice(raw: String, normalized: String) -> String? {
        if let phrase = blockedPhrase(in: normalized) {
            return "The server does not allow \"\(phrase)\" on the search "
                + "network, so peers will not answer this query. Try different "
                + "wording."
        }
        if normalized != raw {
            // Peers tokenize on non-alphanumeric boundaries, so they would drop
            // this punctuation anyway. It is removed here so the query shown is
            // the query sent, and because a term starting with "-" reads as
            // "exclude this word" to some clients.
            return "Searching for \(normalized)"
        }
        return nil
    }

    /// Pulled on demand rather than observed: these change rarely, and the
    /// values live on an actor whose state is not published.
    func refreshConnectivity() async {
        connectivity = Connectivity(
            listenPort: await client.listenPort,
            externalIP: await client.externalIP,
            localIP: await client.localIP,
            natGateway: await client.natGateway,
            mappedPorts: await client.natMappings.map(\.externalPort),
            hasDistributedParent: await client.hasDistributedParent
        )
    }

    /// The first excluded phrase this query contains, if any.
    func blockedPhrase(in query: String) -> String? {
        let haystack = query.lowercased()
        return excludedPhrases.first { phrase in
            !phrase.isEmpty && haystack.contains(phrase.lowercased())
        }
    }

    private func startSearchDeadline(for token: UInt32) {
        searchDeadline?.cancel()
        searchDeadline = Task { [weak self] in
            try? await Task.sleep(for: Self.searchRetryDelay)
            guard !Task.isCancelled, let self, self.activeTokens.contains(token) else { return }

            // Nothing at all after the first pass: try a second flood before
            // telling the user the network had no answer.
            if self.results.isEmpty, !self.searchRetried {
                await self.retrySearch()
                return
            }

            try? await Task.sleep(for: Self.searchTimeout - Self.searchRetryDelay)
            guard !Task.isCancelled, self.activeTokens.contains(token) else { return }
            self.isSearching = false
        }
    }

    func clearSearch() {
        searchDeadline?.cancel()
        searchDeadline = nil
        activeTokens.removeAll()
        results = []
        query = ""
        isSearching = false
        searchNotice = nil
    }

    // MARK: - Downloads

    /// Queues the file with the peer. The peer answers with a TransferRequest
    /// when a slot frees, which may be immediately or hours later — the row
    /// appears in `transfers.downloads` straight away either way.
    func download(_ result: SearchResult) async {
        await downloadManager.queueDownload(from: result)
    }

    /// Queues every file in a folder. The protocol has no "download folder"
    /// message — the desktop client does the same thing, one QueueUpload per
    /// file, and each lands in that peer's queue independently.
    func downloadAll(_ results: [SearchResult]) async {
        for result in results {
            await downloadManager.queueDownload(from: result)
        }
    }

    func cancelDownload(_ id: UUID) async {
        await downloadManager.cancelDownload(transferId: id)
    }

    func retryDownload(_ id: UUID) async {
        await downloadManager.retryFailedDownload(transferId: id)
    }

    // MARK: - Event observation

    private func observeConnection() {
        // The channel is captured strongly and `self` weakly. Capturing self
        // strongly for the life of the loop would be a cycle — Session owns
        // the NetworkClient that owns the channel — and the loop never ends
        // on its own.
        let channel = client.events.connection
        Task { [weak self] in
            for await event in channel.subscribe() {
                guard let self else { break }
                switch event {
                case .statusChanged(let newStatus):
                    self.status = newStatus
                    if newStatus == .disconnected || newStatus == .error {
                        self.isSearching = false
                    }
                    if newStatus == .connected {
                        // Downloads interrupted by a dropped connection resume
                        // from their stored byte offset rather than restarting.
                        await self.downloadManager.resumeDownloadsOnConnect()
                    }
                case .protocolNotice:
                    break
                }
            }
        }
    }

    private func observeSearch() {
        // A popular query can draw thousands of responses in seconds. Tail-drop
        // rather than let the buffer grow without bound — a missed result is a
        // missed row, not a broken transfer.
        let channel = client.events.search
        Task { [weak self] in
            for await event in channel.subscribe(bufferingPolicy: .bufferingOldest(4096)) {
                guard let self else { break }
                switch event {
                case .results(let token, let incoming):
                    guard self.activeTokens.contains(token) else { continue }
                    self.searchReplyCount += 1
                    self.isSearching = false
                    self.results.append(contentsOf: incoming)
                case .excludedPhrases(let phrases):
                    // Pushed once after login. Kept so a query that the network
                    // refuses to carry can be named as such instead of just
                    // returning nothing.
                    self.excludedPhrases = phrases
                    self.receivedExcludedPhrases = true
                case .wishlistInterval, .folderContentsResponse:
                    continue
                }
            }
        }
    }
}
