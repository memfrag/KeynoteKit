import Foundation
import KeynoteSchemas
import SwiftProtobuf

/// Character-style overrides for text nodes.
///
/// Keynote applies per-run formatting through anonymous *variation* styles:
/// a `TSWP.CharacterStyleArchive` that lives in the document stylesheet,
/// inherits the run's base style, and overrides only the changed properties.
/// This replicates that structure exactly (verified against Keynote output),
/// so overridden text opens and renders correctly.
extension KeynoteDocument {

    /// Overrides font size, weight, italic, and color on a text node. `nil`
    /// arguments keep the inherited value. Colors are RGBA in 0…1.
    public mutating func setNodeCharacterStyle(
        _ nodeID: UInt64,
        fontSize: Double? = nil,
        bold: Bool? = nil,
        italic: Bool? = nil,
        color: (Double, Double, Double, Double)? = nil
    ) throws {
        guard fontSize != nil || bold != nil || italic != nil || color != nil else { return }

        let location = try locateSceneNode(nodeID)
        guard let storageID = try storageIdentifier(forNodeAt: location),
              let storageIndex = components[location.component].records.firstIndex(where: { $0.identifier == storageID })
        else { throw SceneEditError.nodeHasNoText(nodeID) }

        var storageRecord = components[location.component].records[storageIndex]
        var storage = try storageRecord.decode(TSWP_StorageArchive.self)

        // The run's current character style is the parent the override
        // inherits from; the storage's stylesheet is the override's stylesheet.
        guard let baseStyleID = storage.tableCharStyle.entries.first?.object.identifier,
              storage.hasStyleSheet
        else { throw SceneEditError.unsupportedEdit("text node \(nodeID) has no base character style to inherit") }
        let styleSheetID = storage.styleSheet.identifier

        // Overrides are anonymous styles that live in the document stylesheet
        // (the component holding the base style), not the slide.
        guard let stylesheetComponent = components.firstIndex(where: {
            $0.records.contains { $0.identifier == baseStyleID }
        }) else {
            throw SceneEditError.unsupportedEdit("cannot locate the stylesheet for node \(nodeID)")
        }

        var overrideCount: UInt32 = 0
        var properties = TSWP_CharacterStylePropertiesArchive()
        if let fontSize { properties.fontSize = Float(fontSize); overrideCount += 1 }
        if let bold { properties.bold = bold; overrideCount += 1 }
        if let italic { properties.italic = italic; overrideCount += 1 }
        if let color {
            properties.fontColor = Self.color(color)
            properties.tsdFill = TSD_FillArchive.with { $0.color = Self.color(color) }
            overrideCount += 1
        }

        let newStyleID = try allocateIdentifier()
        let style = TSWP_CharacterStyleArchive.with {
            $0.super = TSS_StyleArchive.with {
                $0.parent = reference(baseStyleID)
                $0.isVariation = true
                $0.stylesheet = reference(styleSheetID)
            }
            $0.overrideCount = overrideCount
            $0.charProperties = properties
        }
        let styleRecord = try makeRecord(
            identifier: newStyleID, type: 2021, message: style,
            version: storageRecord.info.messageInfos[0].version,
            objectReferences: [baseStyleID]
        )
        components[stylesheetComponent].records.append(styleRecord)

        // Point every run at the override, and declare the storage's new
        // cross-component reference to it.
        for i in storage.tableCharStyle.entries.indices {
            storage.tableCharStyle.entries[i].object = reference(newStyleID)
        }
        try storageRecord.setMessage(storage)
        var refs = storageRecord.info.messageInfos[0].objectReferences
        if !refs.contains(newStyleID) { refs.append(newStyleID) }
        try storageRecord.setObjectReferences(refs, at: 0)
        components[location.component].records[storageIndex] = storageRecord

        try declareExternalReference(fromComponent: location.component, toObject: newStyleID)
    }

    /// Overrides a shape's fill color (RGBA 0…1). Convenience for
    /// ``setNodeFill(_:fill:)`` with a solid color.
    public mutating func setNodeFill(_ nodeID: UInt64, to color: (Double, Double, Double, Double)) throws {
        try setNodeFill(nodeID, fill: .color(color.0, color.1, color.2, color.3))
    }

    /// Overrides a shape's fill with any ``Fill`` — none, color, gradient, or
    /// image — via an anonymous variation of its shape style, mirroring
    /// Keynote's own structure.
    public mutating func setNodeFill(_ nodeID: UInt64, fill: Fill) throws {
        let location = try locateSceneNode(nodeID)
        var record = components[location.component].records[location.record]
        guard record.primaryType == 2011 else {
            throw SceneEditError.unsupportedEdit("node \(nodeID) is not a fillable shape")
        }
        var shape = try record.decode(TSWP_ShapeInfoArchive.self)
        guard shape.super.hasStyle else {
            throw SceneEditError.unsupportedEdit("shape \(nodeID) has no base style to inherit")
        }
        let baseStyleID = shape.super.style.identifier

        // The base shape style (a TSWP.ShapeStyleArchive) lives in the
        // stylesheet; the override inherits from it and goes there too.
        guard let stylesheetComponent = components.firstIndex(where: {
            $0.records.contains { $0.identifier == baseStyleID }
        }), let baseRecord = components[stylesheetComponent].records.first(where: { $0.identifier == baseStyleID }),
            let baseStyle = try? baseRecord.decode(TSWP_ShapeStyleArchive.self)
        else {
            throw SceneEditError.unsupportedEdit("cannot locate the base style for shape \(nodeID)")
        }
        let styleSheetID = baseStyle.super.super.hasStylesheet ? baseStyle.super.super.stylesheet.identifier : nil

        let (fillArchive, fillDataIDs) = try makeFillArchive(fill)
        let newStyleID = try allocateIdentifier()
        let style = TSWP_ShapeStyleArchive.with {
            $0.super = TSD_ShapeStyleArchive.with {
                $0.super = TSS_StyleArchive.with {
                    $0.parent = reference(baseStyleID)
                    $0.isVariation = true
                    if let styleSheetID { $0.stylesheet = reference(styleSheetID) }
                }
                $0.overrideCount = 1
                $0.shapeProperties = TSD_ShapeStylePropertiesArchive.with { $0.fill = fillArchive }
            }
        }
        var styleRecord = try makeRecord(
            identifier: newStyleID, type: 2025, message: style,
            version: record.info.messageInfos[0].version,
            objectReferences: [baseStyleID]
        )
        // An image fill carries a data reference on the style record.
        if !fillDataIDs.isEmpty {
            try styleRecord.setDataReferences(fillDataIDs, at: 0)
        }
        components[stylesheetComponent].records.append(styleRecord)
        if !fillDataIDs.isEmpty {
            try bindDataReferences(fillDataIDs, toObject: newStyleID, inComponent: stylesheetComponent)
        }

        shape.super.style = reference(newStyleID)
        try record.setMessage(shape)
        var refs = record.info.messageInfos[0].objectReferences
        if !refs.contains(newStyleID) { refs.append(newStyleID) }
        try record.setObjectReferences(refs, at: 0)
        components[location.component].records[location.record] = record

        try declareExternalReference(fromComponent: location.component, toObject: newStyleID)
    }

    /// Sets a slide's background fill color (RGBA 0…1). Convenience for
    /// ``setSlideBackground(at:fill:)`` with a solid color.
    public mutating func setSlideBackground(at index: Int, to color: (Double, Double, Double, Double)) throws {
        try setSlideBackground(at: index, fill: .color(color.0, color.1, color.2, color.3))
    }

    /// Sets a slide's background to any ``Fill`` — none, color, gradient, or
    /// image — by attaching an anonymous variation of its slide style, so a
    /// single slide's background changes without touching the shared master
    /// style.
    public mutating func setSlideBackground(at index: Int, fill: Fill) throws {
        let (slideArchive, slideComponent, slideRecordIndex) = try slideArchiveLocation(at: index)
        var slide = slideArchive
        let version = components[slideComponent].records[slideRecordIndex].info.messageInfos[0].version

        // The slide's current style (from its master) is the parent to inherit.
        let baseStyleID: UInt64? = slide.hasStyle ? slide.style.identifier : nil

        // Variation styles live in the stylesheet component that holds the
        // base style; fall back to any component that carries slide styles.
        let stylesheetComponent: Int
        var styleSheetID: UInt64?
        if let baseStyleID,
           let comp = components.firstIndex(where: { $0.records.contains { $0.identifier == baseStyleID } }) {
            stylesheetComponent = comp
            if let baseRecord = components[comp].records.first(where: { $0.identifier == baseStyleID }),
               let baseStyle = try? baseRecord.decode(KN_SlideStyleArchive.self), baseStyle.super.hasStylesheet {
                styleSheetID = baseStyle.super.stylesheet.identifier
            }
        } else if let comp = components.firstIndex(where: { $0.records.contains { $0.primaryType == 9 } }) {
            stylesheetComponent = comp
        } else {
            throw SceneEditError.unsupportedEdit("no slide style component to hold the background")
        }

        let (fillArchive, fillDataIDs) = try makeFillArchive(fill)
        let newStyleID = try allocateIdentifier()
        let style = KN_SlideStyleArchive.with {
            $0.super = TSS_StyleArchive.with {
                if let baseStyleID {
                    $0.parent = reference(baseStyleID)
                    $0.isVariation = true
                }
                if let styleSheetID { $0.stylesheet = reference(styleSheetID) }
            }
            $0.overrideCount = 1
            $0.slideProperties = KN_SlideStylePropertiesArchive.with { $0.fill = fillArchive }
        }
        var styleRecord = try makeRecord(
            identifier: newStyleID, type: 9, message: style, version: version,
            objectReferences: baseStyleID.map { [$0] } ?? []
        )
        // An image fill carries a data reference on the style record.
        if !fillDataIDs.isEmpty {
            try styleRecord.setDataReferences(fillDataIDs, at: 0)
        }
        components[stylesheetComponent].records.append(styleRecord)
        if !fillDataIDs.isEmpty {
            try bindDataReferences(fillDataIDs, toObject: newStyleID, inComponent: stylesheetComponent)
        }

        // Repoint the slide at the new style and fix its references.
        var slideRecord = components[slideComponent].records[slideRecordIndex]
        slide.style = reference(newStyleID)
        try slideRecord.setMessage(slide)
        var refs = slideRecord.info.messageInfos[0].objectReferences
        if let baseStyleID { refs.removeAll { $0 == baseStyleID } }
        if !refs.contains(newStyleID) { refs.append(newStyleID) }
        try slideRecord.setObjectReferences(refs, at: 0)
        components[slideComponent].records[slideRecordIndex] = slideRecord

        try declareExternalReference(fromComponent: slideComponent, toObject: newStyleID)
    }

    // MARK: Helpers

    func reference(_ id: UInt64) -> TSP_Reference {
        TSP_Reference.with { $0.identifier = id }
    }

    static func color(_ rgba: (Double, Double, Double, Double)) -> TSP_Color {
        TSP_Color.with {
            $0.model = .rgb
            $0.rgbspace = .srgb
            $0.r = Float(rgba.0)
            $0.g = Float(rgba.1)
            $0.b = Float(rgba.2)
            $0.a = Float(rgba.3)
        }
    }

    mutating func allocateIdentifier() throws -> UInt64 {
        let metadataLocation = try locateRecord(type: 11006, orThrow: MediaOperationError.packageMetadataNotFound)
        var record = components[metadataLocation.component].records[metadataLocation.record]
        var metadata = try record.decode(TSP_PackageMetadata.self)
        metadata.lastObjectIdentifier += 1
        let id = metadata.lastObjectIdentifier
        try record.setMessage(metadata)
        components[metadataLocation.component].records[metadataLocation.record] = record
        return id
    }

    /// Declares a cross-component reference in `component`'s ComponentInfo
    /// (idempotent). No-op if the object is local.
    mutating func declareExternalReference(fromComponent component: Int, toObject objectID: UInt64) throws {
        if components[component].records.contains(where: { $0.identifier == objectID }) { return }
        guard let ownerRootID = components.first(where: {
            $0.records.contains { $0.identifier == objectID }
        })?.records.first?.identifier else { return }

        let componentRootID = components[component].records.first?.identifier ?? 0
        let metadataLocation = try locateRecord(type: 11006, orThrow: MediaOperationError.packageMetadataNotFound)
        var record = components[metadataLocation.component].records[metadataLocation.record]
        var metadata = try record.decode(TSP_PackageMetadata.self)
        guard let infoIndex = metadata.components.firstIndex(where: { $0.identifier == componentRootID }) else { return }

        let declared = metadata.components[infoIndex].externalReferences.contains {
            $0.componentIdentifier == ownerRootID && $0.hasObjectIdentifier && $0.objectIdentifier == objectID
        }
        if !declared {
            metadata.components[infoIndex].externalReferences.append(TSP_ComponentExternalReference.with {
                $0.componentIdentifier = ownerRootID
                $0.objectIdentifier = objectID
            })
            try record.setMessage(metadata)
            components[metadataLocation.component].records[metadataLocation.record] = record
        }
    }

    private func storageIdentifier(forNodeAt location: RecordLocation) throws -> UInt64? {
        let record = components[location.component].records[location.record]
        let shape: TSWP_ShapeInfoArchive
        switch record.primaryType {
        case 7: shape = try record.decode(KN_PlaceholderArchive.self).super
        case 2011: shape = try record.decode(TSWP_ShapeInfoArchive.self)
        default: return nil
        }
        if shape.hasOwnedStorage { return shape.ownedStorage.identifier }
        if shape.hasTextFlow { return shape.textFlow.identifier }
        return nil
    }
}
