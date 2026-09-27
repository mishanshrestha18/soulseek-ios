import SwiftUI

/// The server's list of phrases peers must leave out of search replies.
///
/// Exists to settle a specific question: a query that draws zero replies looks
/// identical whether nobody had a match or every peer had one and withheld it.
/// Reading the list is the only way to tell from the client side.
struct BlocklistView: View {
    @Environment(Session.self) private var session
    @State private var filterText = ""

    private var phrases: [String] {
        let all = session.excludedPhrases.sorted { $0.lowercased() < $1.lowercased() }
        guard !filterText.isEmpty else { return all }
        let needle = filterText.lowercased()
        return all.filter { $0.lowercased().contains(needle) }
    }

    var body: some View {
        List {
            if !session.receivedExcludedPhrases {
                Section {
                    Text("The server has not sent the list yet. Until it does, an empty list proves nothing either way.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if phrases.isEmpty {
                    Text(filterText.isEmpty ? "No phrases." : "No phrase contains that.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(phrases, id: \.self) { phrase in
                        Text(phrase)
                            .font(.callout.monospaced())
                    }
                }
            } header: {
                Text("\(session.excludedPhrases.count) phrases")
            } footer: {
                Text("Peers must omit any file whose path contains one of these. A peer left with nothing to send usually sends no reply at all, which is why a blocked query and an unanswered query look the same.")
            }
        }
        .searchable(
            text: $filterText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Check a word"
        )
        .navigationTitle("Blocked phrases")
    }
}
