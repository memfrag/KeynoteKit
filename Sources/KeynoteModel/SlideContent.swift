import Foundation
import IWAContainer
import KeynoteSchemas

public enum SlideContentError: Error {
    case slideIndexOutOfRange(Int)
    case slideComponentNotFound(UInt64)
    case placeholderHasNoStorage
    case noPlaceholder(SlidePlaceholder)
}

/// The text placeholders a slide exposes for editing.
public enum SlidePlaceholder: Equatable, Sendable {
    case title
    case body
    /// The presenter notes (`SlideArchive.note` → `NoteArchive`).
    case notes
}

/// Reads and writes the title/body placeholder text of individual slides —
/// the per-slide equivalent of `TextReplacement`, used by the builder to set
/// content on a specific slide rather than find/replace across the document.
///
/// Navigation: slide node (by tree index) → `KN.SlideArchive` (the slide
/// component root) → `titlePlaceholder`/`bodyPlaceholder` reference →
/// `KN.PlaceholderArchive` → its `ShapeInfoArchive.owned_storage` →
/// `TSWP.StorageArchive` whose `text` runs hold the visible characters.
extension KeynoteDocument {

    public func slideTitle(at index: Int) throws -> String? {
        try slideText(at: index, .title)
    }

    public func slideBody(at index: Int) throws -> String? {
        try slideText(at: index, .body)
    }

    public func slideNotes(at index: Int) throws -> String? {
        try slideText(at: index, .notes)
    }

    public func slideText(at index: Int, _ placeholder: SlidePlaceholder) throws -> String? {
        let location = try storageLocation(slideIndex: index, placeholder: placeholder)
        guard let location else { return nil }
        let storage = try components[location.component].records[location.record].decode(TSWP_StorageArchive.self)
        return storage.text.joined()
    }

    /// Sets a placeholder's text. Paragraph breaks are expressed with `\n`,
    /// which Keynote stores as the paragraph separator U+2029 in a single
    /// text run. Throws if the slide has no such placeholder.
    public mutating func setSlideText(
        at index: Int,
        _ placeholder: SlidePlaceholder,
        to text: String
    ) throws {
        guard let location = try storageLocation(slideIndex: index, placeholder: placeholder) else {
            throw SlideContentError.noPlaceholder(placeholder)
        }
        var record = components[location.component].records[location.record]
        var storage = try record.decode(TSWP_StorageArchive.self)
        storage.text = [text.replacingOccurrences(of: "\n", with: "\u{2029}")]
        try record.setMessage(storage)
        components[location.component].records[location.record] = record
    }

    // MARK: Navigation

    private func storageLocation(
        slideIndex: Int,
        placeholder: SlidePlaceholder
    ) throws -> RecordLocation? {
        let nodeIDs = try slideNodeIdentifiers()
        guard nodeIDs.indices.contains(slideIndex) else {
            throw SlideContentError.slideIndexOutOfRange(slideIndex)
        }
        let nodeID = nodeIDs[slideIndex]
        let node = try recordAnywhere(identifier: nodeID, type: 4).decode(KN_SlideNodeArchive.self)
        let slideRootID = node.slide.identifier

        guard let componentIndex = components.firstIndex(where: {
            $0.records.contains { $0.identifier == slideRootID }
        }) else {
            throw SlideContentError.slideComponentNotFound(slideRootID)
        }
        let component = components[componentIndex]
        let slideRecord = component.records.first { $0.identifier == slideRootID }!
        let slide = try slideRecord.decode(KN_SlideArchive.self)

        // Notes reach their storage through a NoteArchive rather than a
        // placeholder/ShapeInfoArchive.
        if placeholder == .notes {
            guard slide.hasNote else { return nil }
            guard let noteRecord = component.records.first(where: {
                $0.identifier == slide.note.identifier
            }) else {
                return nil
            }
            let note = try noteRecord.decode(KN_NoteArchive.self)
            let noteStorageID = note.containedStorage.identifier
            guard let storageRecordIndex = component.records.firstIndex(where: {
                $0.identifier == noteStorageID
            }) else {
                return nil
            }
            return RecordLocation(component: componentIndex, record: storageRecordIndex)
        }

        let placeholderRef: TSP_Reference
        switch placeholder {
        case .title:
            guard slide.hasTitlePlaceholder else { return nil }
            placeholderRef = slide.titlePlaceholder
        case .body:
            guard slide.hasBodyPlaceholder else { return nil }
            placeholderRef = slide.bodyPlaceholder
        case .notes:
            return nil // handled above
        }

        guard let placeholderRecordIndex = component.records.firstIndex(where: {
            $0.identifier == placeholderRef.identifier
        }) else {
            return nil
        }
        let placeholderArchive = try component.records[placeholderRecordIndex].decode(KN_PlaceholderArchive.self)
        let shapeInfo = placeholderArchive.super
        let storageID: UInt64
        if shapeInfo.hasOwnedStorage {
            storageID = shapeInfo.ownedStorage.identifier
        } else if shapeInfo.hasTextFlow {
            storageID = shapeInfo.textFlow.identifier
        } else {
            throw SlideContentError.placeholderHasNoStorage
        }

        guard let storageRecordIndex = component.records.firstIndex(where: {
            $0.identifier == storageID
        }) else {
            return nil
        }
        return RecordLocation(component: componentIndex, record: storageRecordIndex)
    }

    private func recordAnywhere(identifier: UInt64, type: UInt32) throws -> ObjectRecord {
        for component in components {
            if let record = component.records.first(where: {
                $0.identifier == identifier && $0.primaryType == type
            }) {
                return record
            }
        }
        throw SlideContentError.slideComponentNotFound(identifier)
    }
}
