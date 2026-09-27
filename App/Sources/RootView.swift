import SeeleseekCore
import SwiftUI

struct RootView: View {
    @Environment(Session.self) private var session

    var body: some View {
        Group {
            if session.isConnected {
                TabView {
                    SearchView()
                        .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    TransfersView()
                        .tabItem { Label("Transfers", systemImage: "arrow.down.circle") }
                        // Queueing happens on the Search tab, so without a
                        // badge there is nothing to tell you a transfer is in
                        // flight until you go looking for it.
                        .badge(session.transfers.activeDownloadCount)
                    StatusView()
                        .tabItem { Label("Status", systemImage: "network") }
                }
            } else {
                LoginView()
            }
        }
        .animation(.default, value: session.isConnected)
    }
}

/// Connection detail, search diagnostics, and the only place the session can be
/// torn down.
struct StatusView: View {
    @Environment(Session.self) private var session

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    LabeledContent("Server", value: Session.defaultServer)
                    LabeledContent("Status", value: session.status.rawValue.capitalized)
                }

                Section {
                    // An empty phrase list means nothing until you know whether
                    // the server actually sent one — "nothing is blocked" and
                    // "we never received the list" look identical otherwise.
                    LabeledContent(
                        "Blocklist received",
                        value: session.receivedExcludedPhrases ? "Yes" : "Not yet"
                    )
                    LabeledContent(
                        "Blocked phrases",
                        value: "\(session.excludedPhrases.count)"
                    )
                } header: {
                    Text("Search network")
                } footer: {
                    Text("The server publishes phrases that peers must leave out of search replies. A query containing one returns nothing regardless of how much of that music exists.")
                }

                if !session.query.isEmpty {
                    Section {
                        LabeledContent("Query sent", value: session.query)
                        LabeledContent("Peers replied", value: "\(session.searchReplyCount)")
                        LabeledContent("Files found", value: "\(session.results.count)")
                        LabeledContent("Re-flooded", value: session.searchRetried ? "Yes" : "No")
                    } header: {
                        Text("Last search")
                    } footer: {
                        Text("Zero peers replying means the query never reached anyone who could answer — a different problem from peers replying with no matches.")
                    }
                }

                Section {
                    Button("Disconnect", role: .destructive) {
                        Task { await session.disconnect() }
                    }
                }
            }
            .navigationTitle("Status")
        }
    }
}
