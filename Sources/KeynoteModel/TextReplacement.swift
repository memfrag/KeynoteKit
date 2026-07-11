import Foundation
import KeynoteSchemas

/// Text find/replace over every `TSWP.StorageArchive` (type 2001) in the
/// document — the same operation keynote-parser's `replace` command performs.
///
/// Style/attribute tables in a storage are keyed by character index, so
/// same-length replacements are always safe. Length-changing replacements
/// are fine for uniformly-styled storages (tables keyed only at index 0),
/// which covers typical title/body placeholder text; storages with rich
/// mid-string style runs may render with shifted style boundaries.
public enum TextReplacement {

    public static let textStorageTypeID: UInt32 = 2001

    /// Replaces all occurrences of `find` with `replacement` across the
    /// document. Returns the number of storages modified.
    @discardableResult
    public static func replace(
        _ find: String,
        with replacement: String,
        in document: inout KeynoteDocument
    ) throws -> Int {
        var modified = 0
        try document.forEachRecord(ofType: textStorageTypeID) { record in
            var storage = try record.decode(TSWP_StorageArchive.self)
            guard storage.text.contains(where: { $0.contains(find) }) else { return nil }
            storage.text = storage.text.map {
                $0.replacingOccurrences(of: find, with: replacement)
            }
            var updated = record
            try updated.setMessage(storage)
            modified += 1
            return updated
        }
        return modified
    }

    /// All text runs in the document, in component order. Useful for
    /// inspection and tests.
    public static func allText(in document: KeynoteDocument) -> [String] {
        var texts: [String] = []
        for component in document.components {
            for record in component.records where record.primaryType == textStorageTypeID {
                if let storage = try? record.decode(TSWP_StorageArchive.self) {
                    texts.append(contentsOf: storage.text)
                }
            }
        }
        return texts
    }
}
