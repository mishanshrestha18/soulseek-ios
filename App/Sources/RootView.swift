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

/// Placeholder for the transfers tab until downloads land. Also the only
/// place the connection can currently be torn down.
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
