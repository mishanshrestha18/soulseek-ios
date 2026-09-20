import SwiftUI

@main
struct SoulseekApp: App {
    @State private var session = Session()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
    }
}
