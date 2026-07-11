import Foundation
import KeynoteModel

/// Indexes the slides of a template `.key` by layout key, so the writer can
/// clone the right example slide for each piece of content.
///
/// A template deck is an ordinary Keynote file whose slides each demonstrate
/// one layout. Two things identify a slide's layout:
/// - an explicit tag in its presenter notes — a line like `@layout: quote`
///   (or `layout: quote`), which takes precedence; and
/// - the name of the master (slide layout) it is built on, e.g. "Quote".
///
/// Both are lowercased into the lookup, so `layout: Quote`, `@layout: quote`,
/// and a slide on the "Quote" master all resolve to the same entry.
public struct TemplateLibrary {
    public struct Entry {
        public let slideIndex: Int
        public let tag: String?
        public let masterName: String?
    }

    public let entries: [Entry]
    private let byKey: [String: Int] // lookup key → slide index

    public init(document: KeynoteDocument) throws {
        var entries: [Entry] = []
        var byKey: [String: Int] = [:]

        for index in 0..<document.slideCount {
            let notes = try document.slideNotes(at: index)
            let tag = Self.layoutTag(in: notes)
            let masterName = try document.slideMasterName(at: index)
            entries.append(Entry(slideIndex: index, tag: tag, masterName: masterName))

            // Master name is the weaker key (registered first so an explicit
            // tag on another slide can override a collision).
            if let masterName { byKey[Self.normalize(masterName)] = index }
        }
        // Tags override, and win ties.
        for entry in entries {
            if let tag = entry.tag { byKey[Self.normalize(tag)] = entry.slideIndex }
        }

        self.entries = entries
        self.byKey = byKey
    }

    public init(templateURL: URL) throws {
        try self.init(document: try KeynoteDocument(contentsOf: templateURL))
    }

    /// Whether this deck actually declares layouts (any slide has a tag).
    /// A plain single-slide seed has none, and the writer falls back to its
    /// clone-slide-0 behavior.
    public var declaresLayouts: Bool {
        entries.contains { $0.tag != nil }
    }

    /// The template slide index for a layout key, or nil if unknown.
    public func slideIndex(for layout: String) -> Int? {
        byKey[Self.normalize(layout)]
    }

    /// All resolvable layout keys, for diagnostics.
    public var availableLayouts: [String] {
        Array(byKey.keys).sorted()
    }

    // MARK: Helpers

    static func normalize(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Extracts a `@layout:`/`layout:` tag from the first matching notes line.
    static func layoutTag(in notes: String?) -> String? {
        guard let notes else { return nil }
        // Paragraph breaks in stored text appear as U+2029, or CR/LF when the
        // notes were authored via AppleScript's `return`.
        let lines = notes.components(separatedBy: CharacterSet(charactersIn: "\u{2029}\r\n"))
        for rawLine in lines {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("@") { line.removeFirst() }
            let lower = line.lowercased()
            if lower.hasPrefix("layout:") {
                return String(line.dropFirst("layout:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
