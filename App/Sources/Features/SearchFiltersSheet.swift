import SeeleseekCore
import SwiftUI

/// The constraints that do not fit in the chip row: quality floors, size floor,
/// excluded words and sort order. Mirrors the desktop client's filter bar.
struct SearchFiltersSheet: View {
    @Binding var filter: SearchFilter
    @Binding var sort: SearchSort

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Quality") {
                    Toggle("Lossless only", isOn: $filter.losslessOnly)

                    Picker("Minimum bitrate", selection: $filter.minBitrate) {
                        ForEach(SearchFilter.bitrateOptions, id: \.self) { rate in
                            Text(rate == 0 ? "Any" : "\(rate) kbps").tag(rate)
                        }
                    }
                } footer: {
                    Text("A bitrate floor never hides lossless files — they report no comparable bitrate.")
                }

                Section("Availability") {
                    Toggle("Free slot only", isOn: $filter.freeSlotsOnly)
                } footer: {
                    Text("A free slot means the transfer starts now. Everything else waits in that user's queue, sometimes for hours.")
                }

                Section("Size") {
                    Picker("Minimum size", selection: $filter.minSizeMB) {
                        ForEach(SearchFilter.sizeOptions, id: \.self) { size in
                            Text(size == 0 ? "Any" : "\(size) MB").tag(size)
                        }
                    }
                } footer: {
                    Text("Useful for excluding snippets and previews from album searches.")
                }

                Section("Exclude words") {
                    TextField("live remix karaoke", text: $filter.excluded)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Space separated. A result whose path contains any of these is hidden.")
                }

                Section("Sort") {
                    Picker("Order", selection: $sort) {
                        ForEach(SearchSort.allCases) { order in
                            Text(order.label).tag(order)
                        }
                    }
                    .pickerStyle(.segmented)
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
