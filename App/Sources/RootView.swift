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

/// Connection detail, and the only place the session can be torn down.
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
                    Button("Disconnect", role: .destructive) {
                        Task { await session.disconnect() }
                    }
                }
            }
            .navigationTitle("Status")
        }
    }
}
