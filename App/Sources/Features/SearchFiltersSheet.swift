import SeeleseekCore
import SwiftUI

/// The constraints that do not fit in the chip row: quality floors, size floor,
/// excluded words and sort order. Mirrors the desktop client's filter bar.
///
/// Sections use the `header:`/`footer:` form throughout. There is no
/// `Section(_ title:) { } footer: { }` initializer — a title string and a
/// footer builder cannot be combined that way.
struct SearchFiltersSheet: View {
    @Binding var filter: SearchFilter
    @Binding var sort: SearchSort
    @Binding var groupByFolder: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Group by folder", isOn: $groupByFolder)
                } header: {
                    Text("Layout")
                } footer: {
                    Text("Peers share whole directories, so grouping collapses an album into one row and lets you queue all of it at once.")
                }

                Section {
                    Toggle("Lossless only", isOn: $filter.losslessOnly)

                    Picker("Minimum bitrate", selection: $filter.minBitrate) {
                        ForEach(SearchFilter.bitrateOptions, id: \.self) { rate in
                            Text(rate == 0 ? "Any" : "\(rate) kbps").tag(rate)
                        }
                    }
                } header: {
                    Text("Quality")
                } footer: {
                    Text("A bitrate floor never hides lossless files — they report no comparable bitrate.")
                }

                Section {
                    Toggle("Free slot only", isOn: $filter.freeSlotsOnly)
                } header: {
                    Text("Availability")
                } footer: {
                    Text("A free slot means the transfer starts now. Everything else waits in that user's queue, sometimes for hours.")
                }

                Section {
                    Picker("Minimum size", selection: $filter.minSizeMB) {
                        ForEach(SearchFilter.sizeOptions, id: \.self) { size in
                            Text(size == 0 ? "Any" : "\(size) MB").tag(size)
                        }
                    }
                } header: {
                    Text("Size")
                } footer: {
                    Text("Useful for excluding snippets and previews from album searches.")
                }

                Section {
                    TextField("park", text: $filter.required)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Must include words")
                } footer: {
                    Text("Space separated; every word must appear in the path. Useful when a phrase draws no replies from the network but its individual words do — ask for the word that works, then narrow here.")
                }

                Section {
                    TextField("live remix karaoke", text: $filter.excluded)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Exclude words")
                } footer: {
                    Text("Space separated. A result whose path contains any of these is hidden.")
                }

                Section {
                    Picker("Order", selection: $sort) {
                        ForEach(SearchSort.allCases) { order in
                            Text(order.label).tag(order)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Sort")
                } footer: {
                    Text("Default keeps the order results arrived in, which roughly tracks which peers responded fastest.")
                }

                if filter.isActive {
                    Section {
                        Button("Reset filters", role: .destructive) {
                            filter = SearchFilter()
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
