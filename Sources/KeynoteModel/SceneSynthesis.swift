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
    public mutating func addShape(toSlideAt index: Int, frame: Frame) throws -> UInt64 {
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
        shape.super.pathsource = Self.rectanglePath(width: frame.width, height: frame.height)
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
    private mutating func bindDataReferences(_ dataIDs: [UInt64], toObject objectID: UInt64, inComponent component: Int) throws {
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
