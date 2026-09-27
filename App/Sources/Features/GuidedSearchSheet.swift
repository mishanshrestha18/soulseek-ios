import SwiftUI

/// Separate fields for artist, album and track.
///
/// This exists because free text invites the one thing that does not work:
/// typing `Linkin Park - In the End` the way you would into a music app. Peers
/// match every word against the file's folder path, so the words matter and the
/// punctuation between them actively hurts. Three fields remove the question of
/// what separator to use, because the answer is that there isn't one — they are
/// simply concatenated.
struct GuidedSearchSheet: View {
    let onSearch: (String) -> Void

    @State private var artist = ""
    @State private var album = ""
    @State private var track = ""
    @Environment(\.dismiss) private var dismiss

    private var built: String {
        SearchQueryBuilder.build(artist: artist, album: album, track: track)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Artist", text: $artist)
                    TextField("Album", text: $album)
                    TextField("Track", text: $track)
                } header: {
                    Text("Search for")
                } footer: {
                    Text("Fill in what you know. Artist and album usually find more than artist and track, because most people file music by album.")
                }

                if !built.isEmpty {
                    Section {
                        Text(built)
                            .font(.callout.monospaced())
                    } header: {
                        Text("Sent to the network")
                    } footer: {
                        Text("Every word has to appear somewhere in the file's folder path. Fewer, more distinctive words match more.")
                    }
                }

                Section {
                    Button("Search") {
                        onSearch(built)
                        dismiss()
                    }
                    .disabled(built.isEmpty)
                }
            }
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .navigationTitle("Guided search")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
