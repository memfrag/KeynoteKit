import CryptoKit
import Foundation
import KeynoteSchemas

/// Creating drawables from scratch — building the records for a new shape or
/// image rather than cloning a prototype. The drawable's own structure
/// (geometry, path, data) is synthesized; it still *references* a base style
/// from the document's theme, so the result inherits real Keynote styling.
extension KeynoteDocument {

    /// Adds a freshly-synthesized rectangle to a slide and returns its node id.
    /// The shape references a theme shape style, so ``setNodeFill(_:to:)`` can
    /// override its fill exactly as it would for a cloned shape.
    @discardableResult
    public mutating func addShape(
        toSlideAt index: Int, frame: Frame, kind: ShapeKind = .rectangle
    ) throws -> UInt64 {
        guard let shapeStyleID = firstIdentifier(ofType: 2025) else {
            throw SceneEditError.unsupportedEdit("no theme shape style to reference")
        }
        let (_, slideComponent, slideRecord) = try slideArchiveLocation(at: index)
        let slideRootID = components[slideComponent].records[slideRecord].identifier ?? 0
        let version = components[slideComponent].records[slideRecord].info.messageInfos[0].version

        let nodeID = try allocateIdentifier()

        var shape = TSWP_ShapeInfoArchive()
        shape.super.super.geometry = Self.geometry(frame)
        shape.super.super.parent = reference(slideRootID)
        shape.super.style = reference(shapeStyleID)
        shape.super.pathsource = Self.pathSource(for: kind, width: frame.width, height: frame.height)
        shape.isTextBox = false

        let record = try makeRecord(
            identifier: nodeID, type: 2011, message: shape,
            version: version, objectReferences: [shapeStyleID]
        )
        components[slideComponent].records.append(record)

        try attachDrawable(nodeID, toSlideAt: slideComponent, record: slideRecord)
        try declareExternalReference(fromComponent: slideComponent, toObject: shapeStyleID)
        return nodeID
    }

    /// Adds a freshly-synthesized image to a slide and returns its node id.
    /// The bytes are registered as document data (deduped by digest), and the
    /// image references a theme style, so it opens exactly like a cloned one.
    @discardableResult
    public mutating func addImage(toSlideAt index: Int, data: Data, frame: Frame) throws -> UInt64 {
        // Images use a media style (type 3016), not a shape style (2025) —
        // the renderer crashes if handed the wrong kind.
        guard let styleID = defaultMediaStyleID() else {
            throw SceneEditError.unsupportedEdit("no theme media style to reference")
        }
        let (_, slideComponent, slideRecord) = try slideArchiveLocation(at: index)
        let slideRootID = components[slideComponent].records[slideRecord].identifier ?? 0
        let version = components[slideComponent].records[slideRecord].info.messageInfos[0].version

        let (mainID, thumbnailID) = try registerImageData(data)

        // Empty title/caption stand-ins: an image's view hierarchy lays these
        // out, so they must exist (a shape needs none).
        let captionID = try allocateIdentifier()
        let titleID = try allocateIdentifier()
        for id in [captionID, titleID] {
            let record = try makeRecord(
                identifier: id, type: 3097, message: TSD_StandinCaptionArchive(),
                version: [10, 1, 0], objectReferences: []
            )
            components[slideComponent].records.append(record)
        }

        let nodeID = try allocateIdentifier()
        let size = TSP_Size.with { $0.width = Float(frame.width); $0.height = Float(frame.height) }
        var image = TSD_ImageArchive()
        image.super.geometry = Self.geometry(frame)
        image.super.parent = reference(slideRootID)
        image.super.exteriorTextWrap = TSD_ExteriorTextWrapArchive.with {
            $0.type = 4
            $0.direction = 2
            $0.fitType = 1
            $0.margin = 12
            $0.alphaThreshold = 0.5
            $0.isHtmlWrap = false
        }
        image.super.aspectRatioLocked = true
        image.super.title = reference(titleID)
        image.super.caption = reference(captionID)
        image.super.titleHidden = false
        image.super.captionHidden = false
        image.style = reference(styleID)
        image.originalSize = size
        image.naturalSize = size
        image.data = TSP_DataReference.with { $0.identifier = mainID }
        image.thumbnailData = TSP_DataReference.with { $0.identifier = thumbnailID }
        image.interpretsUntaggedImageDataAsGeneric = false
        image.tracedPath = Self.rectangleTSPPath(width: frame.width, height: frame.height)

        var record = try makeRecord(
            identifier: nodeID, type: 3005, message: image,
            version: version, objectReferences: [captionID, titleID, styleID]
        )
        try record.setDataReferences([mainID, thumbnailID], at: 0)
        components[slideComponent].records.append(record)

        try attachDrawable(nodeID, toSlideAt: slideComponent, record: slideRecord)
        try bindDataReferences([mainID, thumbnailID], toObject: nodeID, inComponent: slideComponent)
        try declareExternalReference(fromComponent: slideComponent, toObject: styleID)
        return nodeID
    }

    /// Adds a freshly-synthesized text box to a slide and returns its node id.
    /// The box is built from scratch, but its text still leans on the theme's
    /// paragraph/character/list styles (discovered on an existing text
    /// storage), so it renders with real theme typography and
    /// ``setNodeCharacterStyle(_:fontSize:bold:italic:color:)`` can override it.
    @discardableResult
    public mutating func addText(toSlideAt index: Int, string: String, frame: Frame) throws -> UInt64 {
        guard let styles = defaultTextStyles() else {
            throw SceneEditError.unsupportedEdit("no theme text styles to reference")
        }
        guard let shapeStyleID = firstIdentifier(ofType: 2025) else {
            throw SceneEditError.unsupportedEdit("no theme shape style to reference")
        }
        let (_, slideComponent, slideRecord) = try slideArchiveLocation(at: index)
        let slideRootID = components[slideComponent].records[slideRecord].identifier ?? 0
        let version = components[slideComponent].records[slideRecord].info.messageInfos[0].version

        // The text storage, seeded with a char-0 entry in each paragraph-keyed
        // table (setNodeText then replicates them per paragraph).
        func objectTable(_ styleID: UInt64?) -> TSWP_ObjectAttributeTable {
            TSWP_ObjectAttributeTable.with {
                $0.entries = [TSWP_ObjectAttributeTable.ObjectAttribute.with {
                    $0.characterIndex = 0
                    if let styleID { $0.object = reference(styleID) }
                }]
            }
        }
        func dataTable() -> TSWP_ParaDataAttributeTable {
            TSWP_ParaDataAttributeTable.with {
                $0.entries = [TSWP_ParaDataAttributeTable.ParaDataAttribute.with {
                    $0.characterIndex = 0; $0.first = 0; $0.second = 0
                }]
            }
        }
        let storageID = try allocateIdentifier()
        var storage = TSWP_StorageArchive()
        storage.styleSheet = reference(styles.styleSheet)
        storage.text = [""]
        storage.tableParaStyle = objectTable(styles.para)
        storage.tableParaData = dataTable()
        if let listID = styles.list { storage.tableListStyle = objectTable(listID) }
        storage.tableCharStyle = objectTable(styles.char)
        storage.inDocument = true
        storage.tableParaStarts = dataTable()
        storage.tableParaBidi = dataTable()
        storage.tableDropCapStyle = objectTable(nil)
        let storageRecord = try makeRecord(
            identifier: storageID, type: 2001, message: storage,
            version: [1, 0, 5], objectReferences: [styles.para, styles.char] + [styles.list].compactMap { $0 }
        )
        components[slideComponent].records.append(storageRecord)

        let captionID = try allocateIdentifier()
        let titleID = try allocateIdentifier()
        for id in [captionID, titleID] {
            let record = try makeRecord(
                identifier: id, type: 3097, message: TSD_StandinCaptionArchive(),
                version: [10, 1, 0], objectReferences: []
            )
            components[slideComponent].records.append(record)
        }

        let nodeID = try allocateIdentifier()
        var shape = TSWP_ShapeInfoArchive()
        shape.super.super.geometry = Self.geometry(frame)
        shape.super.super.parent = reference(slideRootID)
        shape.super.super.exteriorTextWrap = TSD_ExteriorTextWrapArchive.with {
            $0.type = 4
            $0.direction = 2
            $0.fitType = 1
            $0.margin = 12
            $0.alphaThreshold = 0.5
            $0.isHtmlWrap = false
        }
        shape.super.super.title = reference(titleID)
        shape.super.super.caption = reference(captionID)
        shape.super.style = reference(shapeStyleID)
        shape.super.pathsource = Self.rectanglePath(width: frame.width, height: frame.height)
        shape.deprecatedStorage = reference(storageID)
        shape.ownedStorage = reference(storageID)
        shape.isTextBox = true
        let record = try makeRecord(
            identifier: nodeID, type: 2011, message: shape,
            version: version, objectReferences: [captionID, titleID, shapeStyleID, storageID]
        )
        components[slideComponent].records.append(record)

        try attachDrawable(nodeID, toSlideAt: slideComponent, record: slideRecord)
        for external in [shapeStyleID, styles.char, styles.para] + [styles.list].compactMap({ $0 }) {
            try declareExternalReference(fromComponent: slideComponent, toObject: external)
        }

        // Fill in the text through the proven path (replicates paragraph tables).
        try setNodeText(nodeID, to: string)
        return nodeID
    }

    /// The theme's default paragraph/character/list styles and its stylesheet,
    /// learned from an existing text storage. Any real deck carries several
    /// (placeholders, prototypes), so this finds one to reference.
    func defaultTextStyles() -> (char: UInt64, para: UInt64, list: UInt64?, styleSheet: UInt64)? {
        // Best: styles from an existing populated text storage — guaranteed
        // theme-consistent and known-good.
        for component in components {
            for record in component.records where record.primaryType == 2001 {
                guard let storage = try? record.decode(TSWP_StorageArchive.self), storage.hasStyleSheet,
                      let charEntry = storage.tableCharStyle.entries.first, charEntry.hasObject,
                      let paraEntry = storage.tableParaStyle.entries.first, paraEntry.hasObject
                else { continue }
                let listID = storage.tableListStyle.entries.first
                    .flatMap { $0.hasObject ? $0.object.identifier : nil } ?? firstIdentifier(ofType: 2023)
                return (charEntry.object.identifier, paraEntry.object.identifier, listID, storage.styleSheet.identifier)
            }
        }
        // Fallback (empty placeholders carry no char table): reference base
        // styles straight from a stylesheet component. Prefer a non-variation
        // character style as the base to override.
        for component in components {
            guard let styleSheetID = component.records.first(where: { $0.primaryType == 401 })?.identifier,
                  let paraID = component.records.first(where: { $0.primaryType == 2022 })?.identifier
            else { continue }
            // Prefer a plain base: a non-variation style with no underline or
            // strikethrough (avoids picking a link/emphasis style).
            func score(_ record: ObjectRecord) -> Int {
                guard let style = try? record.decode(TSWP_CharacterStyleArchive.self) else { return -1 }
                return (style.super.isVariation ? 0 : 2)
                    + (!style.charProperties.hasUnderline && !style.charProperties.hasStrikethru ? 1 : 0)
            }
            let baseChar = component.records
                .filter { $0.primaryType == 2021 }
                .max { score($0) < score($1) }
            guard let charID = baseChar?.identifier else { continue }
            let listID = component.records.first(where: { $0.primaryType == 2023 })?.identifier
            return (charID, paraID, listID, styleSheetID)
        }
        return nil
    }

    /// Masks (clips) an image to a shape — Keynote's "Mask with Shape". The
    /// image shows only through the shape; the rest is hidden. Pass any
    /// ``ShapeKind`` (ellipse, rounded rectangle, star, a custom path…).
    public mutating func maskImage(_ nodeID: UInt64, with kind: ShapeKind) throws {
        let location = try locateSceneNode(nodeID)
        var record = components[location.component].records[location.record]
        guard record.primaryType == 3005 else {
            throw SceneEditError.unsupportedEdit("node \(nodeID) is not an image")
        }
        var image = try record.decode(TSD_ImageArchive.self)
        let size = image.super.geometry.size

        // The mask covers the whole image; its geometry is in the image's own
        // coordinate space (origin at the image's top-left).
        let maskID = try allocateIdentifier()
        var mask = TSD_MaskArchive()
        mask.super.geometry = TSD_GeometryArchive.with {
            $0.position = TSP_Point.with { $0.x = 0; $0.y = 0 }
            $0.size = size
            $0.flags = 3
        }
        mask.super.parent = reference(nodeID)
        mask.pathsource = Self.pathSource(for: kind, width: Double(size.width), height: Double(size.height))
        let maskRecord = try makeRecord(
            identifier: maskID, type: 3006, message: mask,
            version: record.info.messageInfos[0].version, objectReferences: []
        )
        components[location.component].records.append(maskRecord)

        image.mask = reference(maskID)
        try record.setMessage(image)
        var refs = record.info.messageInfos[0].objectReferences
        if !refs.contains(maskID) { refs.append(maskID) }
        try record.setObjectReferences(refs, at: 0)
        components[location.component].records[location.record] = record
    }

    /// Groups existing drawables on a slide into a new group, and returns the
    /// group's node id. Members must live on the given slide. The group's
    /// frame is the members' bounding box; each member is reparented and moved
    /// into the group's coordinate space. Members may themselves be groups, so
    /// groups nest.
    @discardableResult
    public mutating func groupNodes(_ nodeIDs: [UInt64], onSlideAt index: Int) throws -> UInt64 {
        guard nodeIDs.count >= 2 else {
            throw SceneEditError.unsupportedEdit("a group needs at least two members")
        }
        let (_, slideComponent, slideRecordIndex) = try slideArchiveLocation(at: index)
        let slideRootID = components[slideComponent].records[slideRecordIndex].identifier ?? 0
        let version = components[slideComponent].records[slideRecordIndex].info.messageInfos[0].version

        // Bounding box of the members, in slide coordinates.
        var minX = Double.greatestFiniteMagnitude, minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
        for id in nodeIDs {
            guard let geometry = try drawableGeometry(id) else {
                throw SceneEditError.unsupportedEdit("node \(id) can't be grouped")
            }
            let x = Double(geometry.position.x), y = Double(geometry.position.y)
            minX = min(minX, x); minY = min(minY, y)
            maxX = max(maxX, x + Double(geometry.size.width)); maxY = max(maxY, y + Double(geometry.size.height))
        }
        let frame = Frame(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        // Empty title/caption stand-ins (a group carries them like any drawable).
        let captionID = try allocateIdentifier()
        let titleID = try allocateIdentifier()
        for id in [captionID, titleID] {
            let record = try makeRecord(
                identifier: id, type: 3097, message: TSD_StandinCaptionArchive(),
                version: [10, 1, 0], objectReferences: []
            )
            components[slideComponent].records.append(record)
        }

        let groupID = try allocateIdentifier()
        var group = TSD_GroupArchive()
        group.super.geometry = Self.geometry(frame)
        group.super.parent = reference(slideRootID)
        group.super.title = reference(titleID)
        group.super.caption = reference(captionID)
        group.children = nodeIDs.map { reference($0) }
        let record = try makeRecord(
            identifier: groupID, type: 3008, message: group,
            version: version, objectReferences: [captionID, titleID] + nodeIDs
        )
        components[slideComponent].records.append(record)

        // Reparent each member into the group and move it into group space
        // (child coordinates are relative to the group's origin).
        let groupRef = reference(groupID)
        for id in nodeIDs {
            try mutateDrawable(id) { drawable in
                drawable.parent = groupRef
                drawable.geometry.position = TSP_Point.with {
                    $0.x = Float(Double(drawable.geometry.position.x) - minX)
                    $0.y = Float(Double(drawable.geometry.position.y) - minY)
                }
            }
        }

        // Swap the members for the group in the slide's ownership and z-order.
        var slideRecord = components[slideComponent].records[slideRecordIndex]
        var slide = try slideRecord.decode(KN_SlideArchive.self)
        let members = Set(nodeIDs)
        slide.ownedDrawables.removeAll { members.contains($0.identifier) }
        slide.drawablesZOrder.removeAll { members.contains($0.identifier) }
        slide.ownedDrawables.append(reference(groupID))
        slide.drawablesZOrder.append(reference(groupID))
        try slideRecord.setMessage(slide)
        var refs = slideRecord.info.messageInfos[0].objectReferences.filter { !members.contains($0) }
        refs.append(groupID)
        try slideRecord.setObjectReferences(refs, at: 0)
        components[slideComponent].records[slideRecordIndex] = slideRecord

        return groupID
    }

    // MARK: Building blocks

    /// Registers image bytes (and a scaled thumbnail) as document data blobs,
    /// deduping by content digest, and returns their identifiers. Allocates
    /// ids from the document id space, writes the `Data/` files, and updates
    /// both the PackageMetadata data list and the DocumentMetadata digest list.
    mutating func registerImageData(_ newData: Data) throws -> (main: UInt64, thumbnail: UInt64) {
        let thumbnailData = Self.imageData(newData, scaledToFit: 512) ?? newData
        let ext = Self.imageExtension(of: newData)

        let metadataLocation = try locateRecord(type: 11006, orThrow: MediaOperationError.packageMetadataNotFound)
        var metadataRecord = components[metadataLocation.component].records[metadataLocation.record]
        var metadata = try metadataRecord.decode(TSP_PackageMetadata.self)

        var newDigests: [Data] = []
        func resolve(_ bytes: Data, stem: String) -> UInt64 {
            let digest = Data(Insecure.SHA1.hash(data: bytes))
            if let existing = metadata.datas.first(where: { $0.digest == digest }) {
                return existing.identifier
            }
            metadata.lastObjectIdentifier += 1
            let id = metadata.lastObjectIdentifier
            let info = TSP_DataInfo.with {
                $0.identifier = id
                $0.digest = digest
                $0.preferredFileName = "\(stem).\(ext)"
                $0.fileName = "\(stem)-\(id).\(ext)"
                $0.materializedLength = UInt64(bytes.count)
            }
            setEntryData(at: "Data/" + info.fileName, to: bytes)
            metadata.datas.append(info)
            newDigests.append(digest)
            return id
        }
        let mainID = resolve(newData, stem: "media")
        let thumbnailID = resolve(thumbnailData, stem: "media-small")
        try metadataRecord.setMessage(metadata)
        components[metadataLocation.component].records[metadataLocation.record] = metadataRecord

        if !newDigests.isEmpty {
            let docLocation = try locateRecord(type: 11011, orThrow: MediaOperationError.documentMetadataNotFound)
            var docRecord = components[docLocation.component].records[docLocation.record]
            var documentMetadata = try docRecord.decode(TSP_DocumentMetadata.self)
            for digest in newDigests {
                documentMetadata.dataPropertiesV1.properties.append(TSP_DataPropertiesEntryV1.with {
                    $0.digest = digest
                    $0.expectsMatchedDigest = true
                })
            }
            try docRecord.setMessage(documentMetadata)
            components[docLocation.component].records[docLocation.record] = docRecord
        }
        return (mainID, thumbnailID)
    }

    /// Records, in a component's metadata, that `objectID` uses each data blob.
    mutating func bindDataReferences(_ dataIDs: [UInt64], toObject objectID: UInt64, inComponent component: Int) throws {
        let componentRootID = components[component].records.first?.identifier ?? 0
        let metadataLocation = try locateRecord(type: 11006, orThrow: MediaOperationError.packageMetadataNotFound)
        var record = components[metadataLocation.component].records[metadataLocation.record]
        var metadata = try record.decode(TSP_PackageMetadata.self)
        guard let infoIndex = metadata.components.firstIndex(where: { $0.identifier == componentRootID }) else { return }
        var info = metadata.components[infoIndex]
        for dataID in dataIDs {
            let usage = TSP_ComponentDataReference.ObjectReference.with {
                $0.objectIdentifier = objectID
                $0.count = 1
            }
            if let existing = info.dataReferences.firstIndex(where: { $0.dataIdentifier == dataID }) {
                info.dataReferences[existing].objectReferenceList.append(usage)
            } else {
                info.dataReferences.append(TSP_ComponentDataReference.with {
                    $0.dataIdentifier = dataID
                    $0.objectReferenceList = [usage]
                })
            }
        }
        metadata.components[infoIndex] = info
        try record.setMessage(metadata)
        components[metadataLocation.component].records[metadataLocation.record] = record
    }

    /// The theme's default image media style (type 3016), preferring the one
    /// named for images over equation/other media variants.
    func defaultMediaStyleID() -> UInt64? {
        var fallback: UInt64?
        for component in components {
            for record in component.records where record.primaryType == 3016 {
                guard let id = record.identifier else { continue }
                if fallback == nil { fallback = id }
                if let style = try? record.decode(TSD_MediaStyleArchive.self),
                   style.super.styleIdentifier.contains("image") {
                    return id
                }
            }
        }
        return fallback
    }

    func firstIdentifier(ofType type: UInt32) -> UInt64? {
        for component in components {
            for record in component.records where record.primaryType == type {
                if let id = record.identifier { return id }
            }
        }
        return nil
    }

    static func geometry(_ frame: Frame) -> TSD_GeometryArchive {
        TSD_GeometryArchive.with {
            $0.position = TSP_Point.with { $0.x = Float(frame.x); $0.y = Float(frame.y) }
            $0.size = TSP_Size.with { $0.width = Float(frame.width); $0.height = Float(frame.height) }
            $0.flags = 3
            $0.angle = 0
        }
    }

    /// A closed rectangle path in natural coordinates matching the size, laid
    /// out like Keynote's own rectangle (move/line×4/close, then a trailing
    /// move to origin).
    static func rectanglePath(width: Double, height: Double) -> TSD_PathSourceArchive {
        TSD_PathSourceArchive.with {
            $0.bezierPathSource = TSD_BezierPathSourceArchive.with {
                $0.naturalSize = TSP_Size.with { $0.width = Float(width); $0.height = Float(height) }
                $0.path = rectangleTSPPath(width: width, height: height)
            }
        }
    }

    /// A closed rectangle as a bare `TSP_Path` (used for both shape outlines
    /// and an image's traced wrap path).
    static func rectangleTSPPath(width: Double, height: Double) -> TSP_Path {
        let w = Float(width), h = Float(height)
        func line(_ x: Float, _ y: Float) -> TSP_Path.Element {
            TSP_Path.Element.with { $0.type = .lineTo; $0.points = [TSP_Point.with { $0.x = x; $0.y = y }] }
        }
        func move(_ x: Float, _ y: Float) -> TSP_Path.Element {
            TSP_Path.Element.with { $0.type = .moveTo; $0.points = [TSP_Point.with { $0.x = x; $0.y = y }] }
        }
        return TSP_Path.with {
            $0.elements = [
                move(0, 0), line(w, 0), line(w, h), line(0, h),
                TSP_Path.Element.with { $0.type = .closeSubpath },
                move(0, 0),
            ]
        }
    }

    /// Owns a new drawable on a slide: appends to the slide's owned-drawables
    /// and z-order, and records the reference.
    private mutating func attachDrawable(_ nodeID: UInt64, toSlideAt slideComponent: Int, record slideRecordIndex: Int) throws {
        var slideRecord = components[slideComponent].records[slideRecordIndex]
        var slide = try slideRecord.decode(KN_SlideArchive.self)
        slide.ownedDrawables.append(reference(nodeID))
        slide.drawablesZOrder.append(reference(nodeID))
        try slideRecord.setMessage(slide)
        try slideRecord.setObjectReferences(
            slideRecord.info.messageInfos[0].objectReferences + [nodeID], at: 0
        )
        components[slideComponent].records[slideRecordIndex] = slideRecord
    }
}
