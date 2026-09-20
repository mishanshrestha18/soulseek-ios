import AVFoundation
import Foundation
import SeeleseekCore

/// `MetadataReading` is a plain Sendable protocol, so this opts out of the
/// app target's MainActor default isolation. It holds no state.
nonisolated struct MetadataReader: MetadataReading {
    func extractAudioMetadata(from url: URL) async -> AudioFileMetadata? {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata), !items.isEmpty else {
            return nil
        }

        // Sequential rather than `async let`: AVMetadataItem is not Sendable,
        // so handing `items` to concurrent child tasks is a data race. These
        // are tag reads on an already-loaded array and cost nothing anyway.
        let artist = await Self.string(from: items, key: .commonKeyArtist)
        let album = await Self.string(from: items, key: .commonKeyAlbumName)
        let title = await Self.string(from: items, key: .commonKeyTitle)

        let metadata = AudioFileMetadata(artist: artist, album: album, title: title)
        guard metadata.artist != nil || metadata.album != nil || metadata.title != nil else {
            return nil
        }
        return metadata
    }

    func extractArtwork(from url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else { return nil }
        let artwork = AVMetadataItem.metadataItems(
            from: items,
            filteredByIdentifier: .commonIdentifierArtwork
        )
        for item in artwork {
            if let data = try? await item.load(.dataValue) { return data }
        }
        return nil
    }

    /// macOS sets a folder's icon from the album art. iOS has no equivalent,
    /// and `DownloadManager` treats false as "not applied" rather than an error.
    func applyArtworkAsFolderIcon(for directory: URL) async -> Bool {
        false
    }

    private static func string(
        from items: [AVMetadataItem],
        key: AVMetadataKey
    ) async -> String? {
        let matches = AVMetadataItem.metadataItems(
            from: items,
            withKey: key,
            keySpace: .common
        )
        for item in matches {
            if let value = try? await item.load(.stringValue), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
