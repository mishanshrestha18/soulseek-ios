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

    private(set) var results: [SearchResult] = []
    private(set) var isSearching = false
    private(set) var query = ""

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
    /// search that asked for them by token. Late results from a previous
    /// search are dropped rather than mixed into the current list.
    private var activeToken: UInt32?

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
            lastError = await client.connectionError ?? "Could not sign in."
        }
    }

    func disconnect() async {
        await client.disconnectAsync()
        results = []
        activeToken = nil
        isSearching = false
    }

    // MARK: - Search

    func search(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isConnected else { return }

        // Zero is a valid token but is used as a sentinel by enough clients
        // that it is worth avoiding.
        let token = UInt32.random(in: 1...UInt32.max)
        activeToken = token
        query = trimmed
        results = []
        isSearching = true

        do {
            try await client.search(query: trimmed, token: token)
        } catch {
            isSearching = false
            lastError = error.localizedDescription
        }
    }

    func clearSearch() {
        activeToken = nil
        results = []
        query = ""
        isSearching = false
    }

    // MARK: - Downloads

    /// Queues the file with the peer. The peer answers with a TransferRequest
    /// when a slot frees, which may be immediately or hours later — the row
    /// appears in `transfers.downloads` straight away either way.
    func download(_ result: SearchResult) async {
        await downloadManager.queueDownload(from: result)
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
                guard case .results(let token, let incoming) = event else { continue }
                guard token == self.activeToken else { continue }
                self.isSearching = false
                self.results.append(contentsOf: incoming)
            }
        }
    }
}
