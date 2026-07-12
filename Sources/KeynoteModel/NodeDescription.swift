import Foundation
import IWAContainer
import KeynoteSchemas

/// The accessibility description of a drawable — the "Description" field in
/// Keynote's inspector. It lives on every drawable (`TSD.DrawableArchive`),
/// so images, shapes, and text boxes can all carry one. KeynoteKit uses it
/// as an addressing label: set a description like `@hero` in Keynote and
/// target that element by it.
extension KeynoteDocument {

    /// The accessibility description ("Description" in the inspector) of a
    /// node, or nil if unset.
    public func nodeDescription(_ nodeID: UInt64) throws -> String? {
        let location = try locateSceneNode(nodeID)
        let record = components[location.component].records[location.record]
        let value = try Self.drawableDescription(of: record)
        return (value?.isEmpty ?? true) ? nil : value
    }

    /// Sets a node's accessibility description.
    public mutating func setNodeDescription(_ nodeID: UInt64, to description: String) throws {
        let location = try locateSceneNode(nodeID)
        var record = components[location.component].records[location.record]
        switch record.primaryType {
        case 7:
            var a = try record.decode(KN_PlaceholderArchive.self)
            a.super.super.super.accessibilityDescription = description
            try record.setMessage(a)
        case 2011:
            var a = try record.decode(TSWP_ShapeInfoArchive.self)
            a.super.super.accessibilityDescription = description
            try record.setMessage(a)
        case 3005:
            var a = try record.decode(TSD_ImageArchive.self)
            a.super.accessibilityDescription = description
            try record.setMessage(a)
        case 3007:
            var a = try record.decode(TSD_MovieArchive.self)
            a.super.accessibilityDescription = description
            try record.setMessage(a)
        case 3008:
            var a = try record.decode(TSD_GroupArchive.self)
            a.super.accessibilityDescription = description
            try record.setMessage(a)
        default:
            throw SceneEditError.unsupportedEdit("node \(nodeID) has no description")
        }
        components[location.component].records[location.record] = record
    }

    /// The image nodes on a slide, paired with their description label —
    /// what an image-by-label placement targets. Ordered largest-frame first
    /// (the order used when no label matches).
    public func slideImageLabels(at index: Int) throws -> [(nodeID: UInt64, label: String?, frame: Frame?)] {
        try sceneTree(forSlideAt: index).nodes
            .filter { $0.type == "image" }
            .map { ($0.id, $0.label, $0.frame) }
            .sorted { ($0.2.map { $0.width * $0.height } ?? 0) > ($1.2.map { $0.width * $0.height } ?? 0) }
    }

    /// Replaces the image on a slide whose description label matches `key`
    /// (a leading `@` in either is optional). Throws if none matches.
    public mutating func setSlideImage(at index: Int, matching key: String, to data: Data) throws {
        let needle = key.lowercased().hasPrefix("@") ? String(key.lowercased().dropFirst()) : key.lowercased()
        let images = try slideImageLabels(at: index)
        let match = images.first { image in
            guard var label = image.label?.lowercased() else { return false }
            if label.hasPrefix("@") { label.removeFirst() }
            return label == needle
        }
        guard let match else {
            throw SceneEditError.unknownNode(0)
        }
        try setNodeMedia(match.nodeID, to: data)
    }

    static func drawableDescription(of record: ObjectRecord) throws -> String? {
        switch record.primaryType {
        case 7: return try record.decode(KN_PlaceholderArchive.self).super.super.super.accessibilityDescription
        case 2011: return try record.decode(TSWP_ShapeInfoArchive.self).super.super.accessibilityDescription
        case 3005: return try record.decode(TSD_ImageArchive.self).super.accessibilityDescription
        case 3007: return try record.decode(TSD_MovieArchive.self).super.accessibilityDescription
        case 3008: return try record.decode(TSD_GroupArchive.self).super.accessibilityDescription
        default: return nil
        }
    }
}
