import Foundation

/// Turns what a user types into something the Soulseek network will actually
/// match.
///
/// Peers compare every term in a query against the file's whole path as a
/// case-insensitive substring — folder names included. So
/// `linkin park hybrid theory in the end` matches
/// `@@share\Linkin Park\Hybrid Theory\08 In The End.flac`, because each term
/// appears somewhere in that path.
///
/// Two consequences drive everything here:
///
/// 1. Punctuation the user types is treated as part of a term. A path almost
///    never contains `Artist - Title`, so the dash turns a working query into
///    a dead one. Stripping it is safe precisely because matching is
///    substring-based: searching `Remastered` still finds `(Remastered)`.
/// 2. A term beginning with `-` means *exclude this word* to many clients, so
///    `Linkin Park - In the End` can actively exclude the track it names.
enum SearchQueryBuilder {
    /// Characters replaced with a space. Apostrophes are deliberately kept:
    /// they appear in real paths and removing them would split `Don't` into
    /// two terms that no longer match it.
    static let separators = CharacterSet(charactersIn: "-–—_/\\|,;:()[]{}<>\"?!*+=&~`#$%^")

    static func normalize(_ raw: String) -> String {
        raw.components(separatedBy: separators)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Artist, album and track concatenate into one term list because that is
    /// exactly how peers match — all three appear at different depths of the
    /// same path. This is why structured fields are easier than free text: the
    /// user does not have to guess the separator, because there isn't one.
    static func build(artist: String, album: String, track: String) -> String {
        normalize([artist, album, track].joined(separator: " "))
    }

    /// True when normalizing would meaningfully change the query, so the UI can
    /// show what is actually being sent rather than silently rewriting it.
    static func wasRewritten(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalize(trimmed) != trimmed
    }
}
