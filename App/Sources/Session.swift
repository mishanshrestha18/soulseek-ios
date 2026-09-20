import Foundation
import Observation
import SeeleseekCore

/// Owns the `NetworkClient` and republishes the parts of its event stream the
/// UI observes. Everything here is MainActor; `NetworkClient` is an actor and
/// is only touched through `await`.
@MainActor
@Observable
final class Session {
    /// The official server. Port 2242 is the modern one; 2240 is the legacy
    /// port and is not used here.
    static let defaultServer = "server.slsknet.org"
    static let defaultPort: UInt16 = 2242

    private(set) var status: ConnectionStatus = .disconnected
    private(set) var lastError: String?

    private(set) var results: [SearchResult] = []
    private(set) var isSearching = false
    private(set) var query = ""

    let client = NetworkClient()

    /// Results arrive asynchronously from many peers and are matched to the
    /// search that asked for them by token. Late results from a previous
    /// search are dropped rather than mixed into the current list.
    private var activeToken: UInt32?
    private var observers: [Task<Void, Never>] = []

    init() {
        observeConnection()
        observeSearch()
    }

    deinit {
        for observer in observers { observer.cancel() }
    }

    var isConnected: Bool { status == .connected }

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

    // MARK: - Event observation

    private func observeConnection() {
        observers.append(Task { [weak self] in
            guard let self else { return }
            for await event in client.events.connection.subscribe() {
                switch event {
                case .statusChanged(let newStatus):
                    self.status = newStatus
                    if newStatus == .disconnected || newStatus == .error {
                        self.isSearching = false
                    }
                case .protocolNotice:
                    break
                }
            }
        })
    }

    private func observeSearch() {
        // A popular query can draw thousands of responses in seconds. Tail-drop
        // rather than let the buffer grow without bound — a missed result is a
        // missed row, not a broken transfer.
        observers.append(Task { [weak self] in
            guard let self else { return }
            for await event in client.events.search.subscribe(bufferingPolicy: .bufferingOldest(4096)) {
                guard case .results(let token, let incoming) = event else { continue }
                guard token == self.activeToken else { continue }
                self.isSearching = false
                self.results.append(contentsOf: incoming)
            }
        })
    }
}
