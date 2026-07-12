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
        color: (Double, Double, Double, Double)? = nil,
        underline: Bool? = nil,
        strikethrough: Bool? = nil
    ) throws {
        guard fontSize != nil || bold != nil || italic != nil || color != nil
            || underline != nil || strikethrough != nil else { return }

        let location = try locateSceneNode(nodeID)
        guard let storageID = try storageIdentifier(forNodeAt: location),
              let storageIndex = components[location.component].records.firstIndex(where: { $0.identifier == storageID })
        else { throw SceneEditError.nodeHasNoText(nodeID) }

        var storageRecord = components[location.component].records[storageIndex]
        var storage = try storageRecord.decode(TSWP_StorageArchive.self)

        // The run's current character style is the parent the override
        // inherits from; the storage's stylesheet is the override's stylesheet.
        // If the char style was cleared (e.g. by a paragraph style), fall back
        // to the theme's base character style.
        var baseStyleID = storage.tableCharStyle.entries.first.flatMap {
            $0.hasObject ? $0.object.identifier : nil
        } ?? 0
        if baseStyleID == 0 { baseStyleID = defaultTextStyles()?.char ?? 0 }
        guard baseStyleID != 0, storage.hasStyleSheet else {
            throw SceneEditError.unsupportedEdit("text node \(nodeID) has no base character style to inherit")
        }
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
        if let underline { properties.underline = underline ? .kSingleUnderline : .kNoUnderline; overrideCount += 1 }
        if let strikethrough { properties.strikethru = strikethrough ? .kSingleStrikethru : .kNoStrikethru; overrideCount += 1 }

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
    /// ``setNodeStyle(_:fill:border:shadow:)``.
    public mutating func setNodeFill(_ nodeID: UInt64, to color: (Double, Double, Double, Double)) throws {
        try setNodeStyle(nodeID, fill: .color(color.0, color.1, color.2, color.3))
    }

    /// Overrides a shape's fill with any ``Fill``. Convenience for
    /// ``setNodeStyle(_:fill:border:shadow:)``.
    public mutating func setNodeFill(_ nodeID: UInt64, fill: Fill) throws {
        try setNodeStyle(nodeID, fill: fill)
    }

    /// Adds or replaces a node's border. Convenience for
    /// ``setNodeStyle(_:fill:border:shadow:)``.
    public mutating func setNodeBorder(_ nodeID: UInt64, _ border: Border) throws {
        try setNodeStyle(nodeID, border: border)
    }

    /// Adds or replaces a node's drop shadow. Convenience for
    /// ``setNodeStyle(_:fill:border:shadow:opacity:)``.
    public mutating func setNodeShadow(_ nodeID: UInt64, _ shadow: Shadow) throws {
        try setNodeStyle(nodeID, shadow: shadow)
    }

    /// Sets a node's opacity (0…1). Convenience for
    /// ``setNodeStyle(_:fill:border:shadow:opacity:)``.
    public mutating func setNodeOpacity(_ nodeID: UInt64, _ opacity: Double) throws {
        try setNodeStyle(nodeID, opacity: opacity)
    }

    /// Overrides a drawable's visual style — fill, border, drop shadow, and/or
    /// opacity — in a single anonymous style variation, mirroring Keynote's
    /// structure.
    ///
    /// Works on shapes and text boxes (which carry a shape style) and on images
    /// (which carry a media style); `fill` applies only to shapes and text
    /// boxes. `nil` arguments leave the inherited value.
    public mutating func setNodeStyle(
        _ nodeID: UInt64, fill: Fill? = nil, border: Border? = nil, shadow: Shadow? = nil,
        opacity: Double? = nil, startCap: LineEnd? = nil, endCap: LineEnd? = nil
    ) throws {
        guard fill != nil || border != nil || shadow != nil || opacity != nil
            || startCap != nil || endCap != nil else { return }
        let location = try locateSceneNode(nodeID)
        let record = components[location.component].records[location.record]

        switch record.primaryType {
        case 2011:
            try setShapeStyle(at: location, fill: fill, border: border, shadow: shadow,
                              opacity: opacity, startCap: startCap, endCap: endCap)
        case 3005:
            try setMediaStyle(at: location, border: border, shadow: shadow, opacity: opacity)
        default:
            throw SceneEditError.unsupportedEdit("node \(nodeID) has no fillable/strokable style")
        }
    }

    /// Shape and text-box styling: a `TSWP.ShapeStyleArchive` variation whose
    /// `shapeProperties` carries the fill, stroke, and shadow.
    private mutating func setShapeStyle(
        at location: RecordLocation, fill: Fill?, border: Border?, shadow: Shadow?,
        opacity: Double?, startCap: LineEnd? = nil, endCap: LineEnd? = nil
    ) throws {
        var record = components[location.component].records[location.record]
        var shape = try record.decode(TSWP_ShapeInfoArchive.self)
        guard shape.super.hasStyle else {
            throw SceneEditError.unsupportedEdit("shape \(record.identifier ?? 0) has no base style to inherit")
        }
        let baseStyleID = shape.super.style.identifier
        guard let stylesheetComponent = components.firstIndex(where: {
            $0.records.contains { $0.identifier == baseStyleID }
        }), let baseRecord = components[stylesheetComponent].records.first(where: { $0.identifier == baseStyleID }),
            let baseStyle = try? baseRecord.decode(TSWP_ShapeStyleArchive.self)
        else {
            throw SceneEditError.unsupportedEdit("cannot locate the base style for shape \(record.identifier ?? 0)")
        }
        let styleSheetID = baseStyle.super.super.hasStylesheet ? baseStyle.super.super.stylesheet.identifier : nil

        var fillDataIDs: [UInt64] = []
        var properties = TSD_ShapeStylePropertiesArchive()
        var overrideCount: UInt32 = 0
        if let fill {
            let (archive, ids) = try makeFillArchive(fill)
            properties.fill = archive; fillDataIDs = ids; overrideCount += 1
        }
        if let border { properties.stroke = Self.strokeArchive(border); overrideCount += 1 }
        if let shadow { properties.shadow = Self.shadowArchive(shadow); overrideCount += 1 }
        if let opacity { properties.opacity = Float(opacity); overrideCount += 1 }
        // Line-end decorations: the tail is the line's start, the head its end.
        if let startCap, let archive = Self.lineEndArchive(startCap) { properties.tailLineEnd = archive; overrideCount += 1 }
        if let endCap, let archive = Self.lineEndArchive(endCap) { properties.headLineEnd = archive; overrideCount += 1 }

        let newStyleID = try allocateIdentifier()
        let style = TSWP_ShapeStyleArchive.with {
            $0.super = TSD_ShapeStyleArchive.with {
                $0.super = TSS_StyleArchive.with {
                    $0.parent = reference(baseStyleID)
                    $0.isVariation = true
                    if let styleSheetID { $0.stylesheet = reference(styleSheetID) }
                }
                $0.overrideCount = overrideCount
                $0.shapeProperties = properties
            }
        }
        var styleRecord = try makeRecord(
            identifier: newStyleID, type: 2025, message: style,
            version: record.info.messageInfos[0].version, objectReferences: [baseStyleID]
        )
        if !fillDataIDs.isEmpty { try styleRecord.setDataReferences(fillDataIDs, at: 0) }
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

    /// Image styling: a `TSD.MediaStyleArchive` variation whose
    /// `mediaProperties` carries the stroke and shadow.
    private mutating func setMediaStyle(at location: RecordLocation, border: Border?, shadow: Shadow?, opacity: Double?) throws {
        guard border != nil || shadow != nil || opacity != nil else { return }
        var record = components[location.component].records[location.record]
        var image = try record.decode(TSD_ImageArchive.self)
        guard image.hasStyle else {
            throw SceneEditError.unsupportedEdit("image \(record.identifier ?? 0) has no base style to inherit")
        }
        let baseStyleID = image.style.identifier
        guard let stylesheetComponent = components.firstIndex(where: {
            $0.records.contains { $0.identifier == baseStyleID }
        }), let baseRecord = components[stylesheetComponent].records.first(where: { $0.identifier == baseStyleID }),
            let baseStyle = try? baseRecord.decode(TSD_MediaStyleArchive.self)
        else {
            throw SceneEditError.unsupportedEdit("cannot locate the base style for image \(record.identifier ?? 0)")
        }
        let styleSheetID = baseStyle.super.hasStylesheet ? baseStyle.super.stylesheet.identifier : nil

        var properties = TSD_MediaStylePropertiesArchive()
        var overrideCount: UInt32 = 0
        if let border { properties.stroke = Self.strokeArchive(border); overrideCount += 1 }
        if let shadow { properties.shadow = Self.shadowArchive(shadow); overrideCount += 1 }
        if let opacity { properties.opacity = Float(opacity); overrideCount += 1 }

        let newStyleID = try allocateIdentifier()
        let style = TSD_MediaStyleArchive.with {
            $0.super = TSS_StyleArchive.with {
                $0.parent = reference(baseStyleID)
                $0.isVariation = true
                if let styleSheetID { $0.stylesheet = reference(styleSheetID) }
            }
            $0.overrideCount = overrideCount
            $0.mediaProperties = properties
        }
        let styleRecord = try makeRecord(
            identifier: newStyleID, type: 3016, message: style,
            version: record.info.messageInfos[0].version, objectReferences: [baseStyleID]
        )
        components[stylesheetComponent].records.append(styleRecord)

        image.style = reference(newStyleID)
        try record.setMessage(image)
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

    func storageIdentifier(forNodeAt location: RecordLocation) throws -> UInt64? {
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
