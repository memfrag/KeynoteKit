import Foundation
import IWAContainer
import KeynoteSchemas

/// Element comments (`TSD.CommentStorageArchive`, referenced by every
/// drawable via `DrawableArchive.comment`). A comment attaches free-form
/// context to an element — what it's for, how it should be used — separate
/// from the element's *name* (its accessibility description), which is what
/// KeynoteKit uses to address it. Read a comment as intent; read the name as
/// the tag.
extension KeynoteDocument {

    /// The comment text on a node, or nil if it has none.
    public func nodeComment(_ nodeID: UInt64) throws -> String? {
        let location = try locateSceneNode(nodeID)
        let component = components[location.component]
        return try Self.commentText(of: component.records[location.record], in: component)
    }

    /// The comment text on a record, or nil if it has none.
    static func commentText(of record: ObjectRecord, in component: Component) throws -> String? {
        guard let commentID = try commentReference(of: record),
              let commentRecord = component.records.first(where: { $0.identifier == commentID }),
              commentRecord.primaryType == 3056
        else { return nil }
        let comment = try commentRecord.decode(TSD_CommentStorageArchive.self)
        return comment.hasText && !comment.text.isEmpty ? comment.text : nil
    }

    /// Removes a node's comment (clears the reference and drops the storage
    /// record).
    public mutating func removeComment(_ nodeID: UInt64) throws {
        let location = try locateSceneNode(nodeID)
        var record = components[location.component].records[location.record]
        guard let commentID = try Self.commentReference(of: record) else { return }

        Self.clearCommentReference(of: &record)
        // Drop the comment id from the record's object-reference bookkeeping.
        let refs = record.info.messageInfos[0].objectReferences.filter { $0 != commentID }
        try record.setObjectReferences(refs, at: 0)
        components[location.component].records[location.record] = record

        components[location.component].records.removeAll {
            $0.identifier == commentID && $0.primaryType == 3056
        }
    }

    // MARK: Drawable comment plumbing

    static func commentReference(of record: ObjectRecord) throws -> UInt64? {
        func value(_ drawable: TSD_DrawableArchive) -> UInt64? {
            drawable.hasComment ? drawable.comment.identifier : nil
        }
        switch record.primaryType {
        case 7: return value(try record.decode(KN_PlaceholderArchive.self).super.super.super)
        case 2011: return value(try record.decode(TSWP_ShapeInfoArchive.self).super.super)
        case 3005: return value(try record.decode(TSD_ImageArchive.self).super)
        case 3007: return value(try record.decode(TSD_MovieArchive.self).super)
        case 3008: return value(try record.decode(TSD_GroupArchive.self).super)
        default: return nil
        }
    }

    private static func clearCommentReference(of record: inout ObjectRecord) {
        switch record.primaryType {
        case 7:
            if var a = try? record.decode(KN_PlaceholderArchive.self) {
                a.super.super.super.clearComment(); try? record.setMessage(a)
            }
        case 2011:
            if var a = try? record.decode(TSWP_ShapeInfoArchive.self) {
                a.super.super.clearComment(); try? record.setMessage(a)
            }
        case 3005:
            if var a = try? record.decode(TSD_ImageArchive.self) {
                a.super.clearComment(); try? record.setMessage(a)
            }
        case 3007:
            if var a = try? record.decode(TSD_MovieArchive.self) {
                a.super.clearComment(); try? record.setMessage(a)
            }
        case 3008:
            if var a = try? record.decode(TSD_GroupArchive.self) {
                a.super.clearComment(); try? record.setMessage(a)
            }
        default:
            break
        }
    }
}

