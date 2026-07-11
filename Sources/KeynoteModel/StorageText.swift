import Foundation
import KeynoteSchemas

/// Shared storage-text mutation.
///
/// Setting a `TSWP.StorageArchive`'s text replaces its runs with one string
/// whose paragraph breaks are U+2029. The storage's paragraph-keyed
/// attribute tables (`table_para_style`, `table_para_data`,
/// `table_para_starts`, `table_para_bidi`, `table_list_style`) must carry
/// one entry per paragraph start or Keynote mis-renders multi-paragraph
/// text — so the existing first entry (which carries the template's real
/// styles) is replicated at every paragraph start index (UTF-16).
enum StorageText {

    static func set(_ storage: inout TSWP_StorageArchive, to text: String) {
        let normalized = text.replacingOccurrences(of: "\n", with: "\u{2029}")
        storage.text = [normalized]

        // Paragraph start offsets in UTF-16 code units: 0, and one past
        // each paragraph separator.
        var starts: [UInt32] = [0]
        var offset: UInt32 = 0
        for unit in normalized.utf16 {
            offset += 1
            if unit == 0x2029 {
                starts.append(offset)
            }
        }

        replicate(&storage.tableParaStyle, at: starts, has: storage.hasTableParaStyle)
        replicate(&storage.tableListStyle, at: starts, has: storage.hasTableListStyle)
        replicateData(&storage.tableParaData, at: starts, has: storage.hasTableParaData)
        replicateData(&storage.tableParaStarts, at: starts, has: storage.hasTableParaStarts)
        replicateData(&storage.tableParaBidi, at: starts, has: storage.hasTableParaBidi)
    }

    private static func replicate(
        _ table: inout TSWP_ObjectAttributeTable, at starts: [UInt32], has: Bool
    ) {
        guard has, let prototype = table.entries.first else { return }
        table.entries = starts.map { start in
            var entry = prototype
            entry.characterIndex = start
            return entry
        }
    }

    private static func replicateData(
        _ table: inout TSWP_ParaDataAttributeTable, at starts: [UInt32], has: Bool
    ) {
        guard has, let prototype = table.entries.first else { return }
        table.entries = starts.map { start in
            var entry = prototype
            entry.characterIndex = start
            return entry
        }
    }
}
