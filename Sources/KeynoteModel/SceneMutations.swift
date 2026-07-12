import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import IWAContainer
import KeynoteSchemas

public enum SceneEditError: Error {
    case unknownNode(UInt64)
    case nodeHasNoText(UInt64)
    case nodeHasNoFrame(UInt64)
    case nodeHasNoMedia(UInt64)
    case cannotDeletePlaceholder(UInt64)
    case unsupportedEdit(String)
}

/// ObjectID-addressed edit commands — the wrapper interface an AI (or the
/// scene reconciler) uses to change a document. Node ids come from
/// `sceneTree(forSlideAt:)`; every command validates its target and keeps the
/// document's bookkeeping (lengths, references, digests) consistent.
extension KeynoteDocument {

    // MARK: Text

    /// Sets the text of a placeholder or shape node. `\n` becomes the
    /// paragraph separator U+2029.
    public mutating func setNodeText(_ nodeID: UInt64, to text: String) throws {
        let location = try locateSceneNode(nodeID)
        let record = components[location.component].records[location.record]

        let shape: TSWP_ShapeInfoArchive
        switch record.primaryType {
        case 7:
            shape = try record.decode(KN_PlaceholderArchive.self).super
        case 2011:
            shape = try record.decode(TSWP_ShapeInfoArchive.self)
        default:
            throw SceneEditError.nodeHasNoText(nodeID)
        }
        let storageID: UInt64
        if shape.hasOwnedStorage {
            storageID = shape.ownedStorage.identifier
        } else if shape.hasTextFlow {
            storageID = shape.textFlow.identifier
        } else {
            throw SceneEditError.nodeHasNoText(nodeID)
        }
        guard let storageIndex = components[location.component].records.firstIndex(where: {
            $0.identifier == storageID
        }) else {
            throw SceneEditError.nodeHasNoText(nodeID)
        }
        var storageRecord = components[location.component].records[storageIndex]
        var storage = try storageRecord.decode(TSWP_StorageArchive.self)
        StorageText.set(&storage, to: text)
        try storageRecord.setMessage(storage)
        components[location.component].records[storageIndex] = storageRecord
    }

    // MARK: Geometry

    /// Moves/resizes a drawable node.
    public mutating func setNodeFrame(_ nodeID: UInt64, to frame: Frame) throws {
        let location = try locateSceneNode(nodeID)
        var record = components[location.component].records[location.record]

        func updated(_ geometry: inout TSD_GeometryArchive) {
            geometry.position = TSP_Point.with { $0.x = Float(frame.x); $0.y = Float(frame.y) }
            geometry.size = TSP_Size.with { $0.width = Float(frame.width); $0.height = Float(frame.height) }
            // Clear the "size is unset" flag (bit 2) if present so the
            // explicit size takes effect.
            geometry.flags &= ~UInt32(4)
        }

        switch record.primaryType {
        case 7:
            var archive = try record.decode(KN_PlaceholderArchive.self)
            updated(&archive.super.super.super.geometry)
            try record.setMessage(archive)
        case 2011:
            var archive = try record.decode(TSWP_ShapeInfoArchive.self)
            updated(&archive.super.super.geometry)
            // A shape's outline is drawn from its path source in "natural
            // size" coordinates; the geometry frame alone doesn't stretch it.
            // Rescale the path to the new size so the shape fills its frame.
            if archive.super.hasPathsource {
                Self.resizePathSource(&archive.super.pathsource, to: frame)
            }
            try record.setMessage(archive)
        case 3005:
            var archive = try record.decode(TSD_ImageArchive.self)
            updated(&archive.super.geometry)
            try record.setMessage(archive)
        case 3007:
            var archive = try record.decode(TSD_MovieArchive.self)
            updated(&archive.super.geometry)
            try record.setMessage(archive)
        case 3008:
            var archive = try record.decode(TSD_GroupArchive.self)
            updated(&archive.super.geometry)
            try record.setMessage(archive)
        default:
            throw SceneEditError.nodeHasNoFrame(nodeID)
        }
        components[location.component].records[location.record] = record
    }

    /// Rotates a drawable node. Positive degrees rotate counterclockwise.
    public mutating func setNodeRotation(_ nodeID: UInt64, degrees: Double) throws {
        try mutateGeometry(nodeID) { $0.angle = Float(degrees) }
    }

    /// Locks or unlocks a drawable — a locked element can't be selected or
    /// edited in Keynote until it's unlocked.
    public mutating func setNodeLocked(_ nodeID: UInt64, _ locked: Bool) throws {
        try mutateDrawable(nodeID) { $0.locked = locked }
    }

    /// Applies a change to a drawable's geometry, decoding whichever archive
    /// type the node is.
    mutating func mutateGeometry(_ nodeID: UInt64, _ apply: @escaping (inout TSD_GeometryArchive) -> Void) throws {
        try mutateDrawable(nodeID) { apply(&$0.geometry) }
    }

    /// Applies a change to a drawable's shared `TSD.DrawableArchive` fields
    /// (geometry, parent, …), decoding whichever archive type the node is.
    mutating func mutateDrawable(_ nodeID: UInt64, _ apply: (inout TSD_DrawableArchive) -> Void) throws {
        let location = try locateSceneNode(nodeID)
        var record = components[location.component].records[location.record]
        switch record.primaryType {
        case 7:
            var archive = try record.decode(KN_PlaceholderArchive.self)
            apply(&archive.super.super.super)
            try record.setMessage(archive)
        case 2011:
            var archive = try record.decode(TSWP_ShapeInfoArchive.self)
            apply(&archive.super.super)
            try record.setMessage(archive)
        case 3005:
            var archive = try record.decode(TSD_ImageArchive.self)
            apply(&archive.super)
            try record.setMessage(archive)
        case 3007:
            var archive = try record.decode(TSD_MovieArchive.self)
            apply(&archive.super)
            try record.setMessage(archive)
        case 3008:
            var archive = try record.decode(TSD_GroupArchive.self)
            apply(&archive.super)
            try record.setMessage(archive)
        default:
            throw SceneEditError.nodeHasNoFrame(nodeID)
        }
        components[location.component].records[location.record] = record
    }

    /// A drawable node's geometry (position/size), or nil if it has none.
    func drawableGeometry(_ nodeID: UInt64) throws -> TSD_GeometryArchive? {
        let location = try locateSceneNode(nodeID)
        let record = components[location.component].records[location.record]
        switch record.primaryType {
        case 7: return try record.decode(KN_PlaceholderArchive.self).super.super.super.geometry
        case 2011: return try record.decode(TSWP_ShapeInfoArchive.self).super.super.geometry
        case 3005: return try record.decode(TSD_ImageArchive.self).super.geometry
        case 3007: return try record.decode(TSD_MovieArchive.self).super.geometry
        case 3008: return try record.decode(TSD_GroupArchive.self).super.geometry
        default: return nil
        }
    }

    // MARK: Media

    /// Replaces the media content of an image node.
    ///
    /// When the node's data is materialized (a real `Data/` file), the bytes
    /// are swapped in place. When it is an unmaterialized theme resource
    /// (stock photos in Apple's layouts), fresh `DataInfo` entries are
    /// created and the node is repointed at them, with all digest and
    /// data-reference bookkeeping updated.
    public mutating func setNodeMedia(_ nodeID: UInt64, to newData: Data) throws {
        let location = try locateSceneNode(nodeID)
        let record = components[location.component].records[location.record]
        guard record.primaryType == 3005 else {
            throw SceneEditError.nodeHasNoMedia(nodeID)
        }
        let image = try record.decode(TSD_ImageArchive.self)
        guard image.hasData else {
            throw SceneEditError.nodeHasNoMedia(nodeID)
        }

        // Replace bytes in place only when this node exclusively owns the
        // data. If the data is unmaterialized (theme stock) or shared with
        // another drawable (e.g. after cloning an image), an in-place swap
        // would change every user of it — so create fresh data and repoint.
        if let mainFileName = fileName(forDataIdentifier: image.data.identifier),
           !imageDataIsShared(image.data.identifier, byNodeOtherThan: nodeID) {
            try replaceMediaFile(named: mainFileName, with: newData)
            if image.hasThumbnailData,
               let thumbnailName = fileName(forDataIdentifier: image.thumbnailData.identifier),
               let old = dataForEntry(at: "Data/" + thumbnailName),
               let scaled = Self.imageData(newData, scaledToMatch: old) {
                try replaceMediaFile(named: thumbnailName, with: scaled)
            }
        } else {
            try repointImage(at: location, to: newData)
        }
    }

    /// Whether a data identifier is referenced by any image drawable other
    /// than `nodeID` (its main or thumbnail data).
    private func imageDataIsShared(_ dataID: UInt64, byNodeOtherThan nodeID: UInt64) -> Bool {
        for component in components {
            for record in component.records where record.primaryType == 3005 && record.identifier != nodeID {
                guard let other = try? record.decode(TSD_ImageArchive.self) else { continue }
                if (other.hasData && other.data.identifier == dataID)
                    || (other.hasThumbnailData && other.thumbnailData.identifier == dataID) {
                    return true
                }
            }
        }
        return false
    }

    /// Creates fresh data entries for `newData` (plus a thumbnail) and points
    /// the image node at them.
    private mutating func repointImage(at location: RecordLocation, to newData: Data) throws {
        var record = components[location.component].records[location.record]
        var image = try record.decode(TSD_ImageArchive.self)
        let oldIDs = [
            image.hasData ? image.data.identifier : nil,
            image.hasThumbnailData ? image.thumbnailData.identifier : nil,
        ].compactMap { $0 }

        let metadataLocation = try locateRecord(type: 11006, orThrow: MediaOperationError.packageMetadataNotFound)
        var metadataRecord = components[metadataLocation.component].records[metadataLocation.record]
        var metadata = try metadataRecord.decode(TSP_PackageMetadata.self)

        // Thumbnail: a scaled render (max 512px on the long side).
        let thumbnailData = Self.imageData(newData, scaledToFit: 512) ?? newData
        let ext = Self.imageExtension(of: newData)

        // Resolve a blob to a DataInfo identifier. Keynote forbids two
        // DataInfos with the same content digest — a duplicate makes
        // TSPersistence abort on open — so if a data with this digest already
        // exists (a theme asset, or the same image used twice), reuse it
        // instead of registering a colliding copy. New datas allocate their id
        // from last_object_identifier, since data ids share the document-wide
        // id space with objects.
        var newlyCreatedDigests: [Data] = []
        func resolveData(_ bytes: Data, stem: String) -> UInt64 {
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
            newlyCreatedDigests.append(digest)
            return id
        }
        let mainID = resolveData(newData, stem: "media")
        let thumbnailID = resolveData(thumbnailData, stem: "media-small")

        // Component data-reference bookkeeping: this object no longer uses the
        // old datas; it uses the resolved ones. Append to an existing usage
        // list when the resolved data is already referenced (dedup case).
        let objectID = record.identifier ?? 0
        let componentRootID = components[location.component].records.first?.identifier ?? 0
        if let componentInfoIndex = metadata.components.firstIndex(where: { $0.identifier == componentRootID }) {
            var info = metadata.components[componentInfoIndex]
            info.dataReferences = info.dataReferences.compactMap { reference in
                guard oldIDs.contains(reference.dataIdentifier) else { return reference }
                var updated = reference
                updated.objectReferenceList.removeAll { $0.objectIdentifier == objectID }
                return updated.objectReferenceList.isEmpty ? nil : updated
            }
            for dataID in [mainID, thumbnailID] {
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
            metadata.components[componentInfoIndex] = info
        }
        try metadataRecord.setMessage(metadata)
        components[metadataLocation.component].records[metadataLocation.record] = metadataRecord

        // DocumentMetadata digest list — only for datas we newly registered.
        if !newlyCreatedDigests.isEmpty {
            let documentMetadataLocation = try locateRecord(type: 11011, orThrow: MediaOperationError.documentMetadataNotFound)
            var documentMetadataRecord = components[documentMetadataLocation.component].records[documentMetadataLocation.record]
            var documentMetadata = try documentMetadataRecord.decode(TSP_DocumentMetadata.self)
            for digest in newlyCreatedDigests {
                documentMetadata.dataPropertiesV1.properties.append(TSP_DataPropertiesEntryV1.with {
                    $0.digest = digest
                    $0.expectsMatchedDigest = true
                })
            }
            try documentMetadataRecord.setMessage(documentMetadata)
            components[documentMetadataLocation.component].records[documentMetadataLocation.record] = documentMetadataRecord
        }

        // Repoint the node and its MessageInfo data references.
        image.data = TSP_DataReference.with { $0.identifier = mainID }
        image.thumbnailData = TSP_DataReference.with { $0.identifier = thumbnailID }
        image.clearAdjustedImageData()
        image.clearEnhancedImageData()
        image.clearThumbnailAdjustedImageData()
        image.clearOriginalData()
        try record.setMessage(image)
        var dataReferences = record.info.messageInfos[0].dataReferences.filter { !oldIDs.contains($0) }
        dataReferences.append(contentsOf: [mainID, thumbnailID])
        try record.setDataReferences(dataReferences, at: 0)
        components[location.component].records[location.record] = record
    }

    // MARK: Cloning (node addition)

    /// Adds a drawable to a slide by cloning an existing one — from the same
    /// slide, another slide, or a template slide. This is how nodes are
    /// "created": the source supplies valid styles and structure, so nothing
    /// has to be synthesized from scratch. The clone lands on top of the
    /// stacking order. Returns the new node's id.
    @discardableResult
    public mutating func cloneDrawable(_ nodeID: UInt64, toSlideAt index: Int) throws -> UInt64 {
        let sourceLocation = try locateSceneNode(nodeID)
        let sourceRecord = components[sourceLocation.component].records[sourceLocation.record]
        guard [2011, 3005, 3007, 3008].contains(sourceRecord.primaryType) else {
            throw SceneEditError.unsupportedEdit(
                "node \(nodeID) (type \(sourceRecord.primaryType ?? 0)) can't be cloned; only shapes, images, movies, and groups"
            )
        }
        let sourceComponent = components[sourceLocation.component]
        let sourceRootID = sourceComponent.records.first?.identifier ?? 0

        // Destination slide.
        let nodeIDs = try slideNodeIdentifiers()
        guard nodeIDs.indices.contains(index) else {
            throw SlideContentError.slideIndexOutOfRange(index)
        }
        let slideNode = try recordAnywhere(identifier: nodeIDs[index], type: 4).decode(KN_SlideNodeArchive.self)
        let destRootID = slideNode.slide.identifier
        guard let destComponentIndex = components.firstIndex(where: {
            $0.records.contains { $0.identifier == destRootID }
        }) else {
            throw SlideContentError.slideComponentNotFound(destRootID)
        }

        // The drawable's subtree: records in the source component reachable
        // from it, stopping at the slide root (a drawable's parent pointer).
        var subtreeIDs: [UInt64] = []
        var queue: [UInt64] = [nodeID]
        var visited: Set<UInt64> = []
        let sourceByID = Dictionary(
            sourceComponent.records.compactMap { record in record.identifier.map { ($0, record) } },
            uniquingKeysWith: { first, _ in first }
        )
        while let id = queue.popLast() {
            guard !visited.contains(id), let record = sourceByID[id] else { continue }
            visited.insert(id)
            if [5, 6, 15].contains(record.primaryType) { continue } // slide roots, notes
            subtreeIDs.append(id)
            for (payloadIndex, info) in record.info.messageInfos.enumerated() {
                guard let typeName = TSPRegistry.protoNames[info.type] else { continue }
                let references = try ReferenceRewriter.collectReferences(
                    in: record.payloads[payloadIndex], typeName: typeName
                )
                queue.append(contentsOf: references)
            }
        }

        // Fresh identifiers; the parent pointer maps to the destination root.
        let metadataLocation = try locateRecord(type: 11006, orThrow: MediaOperationError.packageMetadataNotFound)
        var metadataRecord = components[metadataLocation.component].records[metadataLocation.record]
        var metadata = try metadataRecord.decode(TSP_PackageMetadata.self)
        var nextIdentifier = metadata.lastObjectIdentifier
        var idMap: [UInt64: UInt64] = [sourceRootID: destRootID]
        for id in subtreeIDs {
            nextIdentifier += 1
            idMap[id] = nextIdentifier
        }
        guard let newNodeID = idMap[nodeID] else {
            throw SceneEditError.unknownNode(nodeID)
        }

        // Clone the records into the destination component.
        var clonedRecords: [ObjectRecord] = []
        for id in subtreeIDs {
            clonedRecords.append(try cloned(sourceByID[id]!, using: idMap))
        }
        components[destComponentIndex].records.append(contentsOf: clonedRecords)

        // Attach to the destination slide (ownership, stacking, references).
        guard let destSlideIndex = components[destComponentIndex].records.firstIndex(where: {
            $0.identifier == destRootID
        }) else {
            throw SlideContentError.slideComponentNotFound(destRootID)
        }
        var destSlideRecord = components[destComponentIndex].records[destSlideIndex]
        var destSlide = try destSlideRecord.decode(KN_SlideArchive.self)
        destSlide.ownedDrawables.append(TSP_Reference.with { $0.identifier = newNodeID })
        destSlide.drawablesZOrder.append(TSP_Reference.with { $0.identifier = newNodeID })
        try destSlideRecord.setMessage(destSlide)
        try destSlideRecord.setObjectReferences(
            destSlideRecord.info.messageInfos[0].objectReferences + [newNodeID], at: 0
        )
        components[destComponentIndex].records[destSlideIndex] = destSlideRecord

        // Metadata: allocator, plus external/data reference bookkeeping for
        // the destination component.
        metadata.lastObjectIdentifier = nextIdentifier
        let destComponentRootID = components[destComponentIndex].records.first?.identifier ?? 0
        try updateComponentReferences(
            in: &metadata,
            clonedRecords: clonedRecords,
            sourceComponentRootID: sourceRootID,
            destComponentRootID: destComponentRootID,
            destSlideRootID: destRootID
        )
        try metadataRecord.setMessage(metadata)
        components[metadataLocation.component].records[metadataLocation.record] = metadataRecord

        return newNodeID
    }

    /// Ensures the destination component declares every external object and
    /// data reference the cloned records carry.
    private func updateComponentReferences(
        in metadata: inout TSP_PackageMetadata,
        clonedRecords: [ObjectRecord],
        sourceComponentRootID: UInt64,
        destComponentRootID: UInt64,
        destSlideRootID: UInt64
    ) throws {
        guard let destInfoIndex = metadata.components.firstIndex(where: { $0.identifier == destComponentRootID })
        else { return }
        var destInfo = metadata.components[destInfoIndex]
        let sourceInfo = metadata.components.first { $0.identifier == sourceComponentRootID }

        let clonedIDs = Set(clonedRecords.compactMap(\.identifier))
        var declaredExternals = Set(destInfo.externalReferences.map {
            "\($0.componentIdentifier):\($0.hasObjectIdentifier ? String($0.objectIdentifier) : "")"
        })

        for record in clonedRecords {
            for (payloadIndex, info) in record.info.messageInfos.enumerated() {
                // External object references → mirror the source component's
                // declarations for them.
                guard let typeName = TSPRegistry.protoNames[info.type] else { continue }
                let references = try ReferenceRewriter.collectReferences(
                    in: record.payloads[payloadIndex], typeName: typeName
                )
                for reference in references
                where !clonedIDs.contains(reference) && reference != destSlideRootID {
                    let mirrored = sourceInfo?.externalReferences.first {
                        ($0.hasObjectIdentifier && $0.objectIdentifier == reference)
                            || (!$0.hasObjectIdentifier && $0.componentIdentifier == reference)
                    }
                    if let mirrored {
                        let key = "\(mirrored.componentIdentifier):\(mirrored.hasObjectIdentifier ? String(mirrored.objectIdentifier) : "")"
                        if !declaredExternals.contains(key) {
                            destInfo.externalReferences.append(mirrored)
                            declaredExternals.insert(key)
                        }
                    }
                }

                // Data usage: each data the clone references gains a usage
                // entry for the new object.
                for dataID in info.dataReferences {
                    let usage = TSP_ComponentDataReference.ObjectReference.with {
                        $0.objectIdentifier = record.identifier ?? 0
                        $0.count = 1
                    }
                    if let existing = destInfo.dataReferences.firstIndex(where: { $0.dataIdentifier == dataID }) {
                        destInfo.dataReferences[existing].objectReferenceList.append(usage)
                    } else {
                        destInfo.dataReferences.append(TSP_ComponentDataReference.with {
                            $0.dataIdentifier = dataID
                            $0.objectReferenceList = [usage]
                        })
                    }
                }
            }
        }
        metadata.components[destInfoIndex] = destInfo
    }

    // MARK: Deletion & ordering

    /// Removes a free drawable (image, shape, group, movie) from its slide.
    /// Placeholders can't be deleted. Child records owned by the drawable
    /// become unreferenced and are dropped by Keynote on next save.
    public mutating func deleteDrawable(_ nodeID: UInt64) throws {
        let location = try locateSceneNode(nodeID)
        let record = components[location.component].records[location.record]
        if record.primaryType == 7 {
            throw SceneEditError.cannotDeletePlaceholder(nodeID)
        }

        // The slide root is the component's first record.
        guard let slideIndex = components[location.component].records.firstIndex(where: { $0.primaryType == 5 || $0.primaryType == 6 }) else {
            throw SceneEditError.unknownNode(nodeID)
        }
        var slideRecord = components[location.component].records[slideIndex]
        var slide = try slideRecord.decode(KN_SlideArchive.self)
        slide.ownedDrawables.removeAll { $0.identifier == nodeID }
        slide.drawablesZOrder.removeAll { $0.identifier == nodeID }
        slide.sageTagToInfoMap.removeAll { $0.info.identifier == nodeID }
        try slideRecord.setMessage(slide)
        let references = slideRecord.info.messageInfos[0].objectReferences.filter { $0 != nodeID }
        try slideRecord.setObjectReferences(references, at: 0)
        components[location.component].records[slideIndex] = slideRecord

        components[location.component].records.remove(
            at: components[location.component].records.firstIndex { $0.identifier == nodeID }!
        )
    }

    /// Restacks a slide's free drawables. `order` must contain exactly the
    /// current z-order ids, back to front.
    public mutating func reorderDrawables(onSlideAt index: Int, to order: [UInt64]) throws {
        let nodeIDs = try slideNodeIdentifiers()
        guard nodeIDs.indices.contains(index) else {
            throw SlideContentError.slideIndexOutOfRange(index)
        }
        let node = try recordAnywhere(identifier: nodeIDs[index], type: 4).decode(KN_SlideNodeArchive.self)
        let slideRootID = node.slide.identifier
        guard let componentIndex = components.firstIndex(where: {
            $0.records.contains { $0.identifier == slideRootID }
        }), let recordIndex = components[componentIndex].records.firstIndex(where: { $0.identifier == slideRootID })
        else {
            throw SlideContentError.slideComponentNotFound(slideRootID)
        }
        var slideRecord = components[componentIndex].records[recordIndex]
        var slide = try slideRecord.decode(KN_SlideArchive.self)
        guard Set(slide.drawablesZOrder.map(\.identifier)) == Set(order) else {
            throw SceneEditError.unsupportedEdit("reorder must permute the existing z-order ids")
        }
        slide.drawablesZOrder = order.map { id in TSP_Reference.with { $0.identifier = id } }
        try slideRecord.setMessage(slide)
        components[componentIndex].records[recordIndex] = slideRecord
    }

    // MARK: Lookup

    func locateSceneNode(_ nodeID: UInt64) throws -> RecordLocation {
        for (componentIndex, component) in components.enumerated() {
            if let recordIndex = component.records.firstIndex(where: { $0.identifier == nodeID }) {
                return RecordLocation(component: componentIndex, record: recordIndex)
            }
        }
        throw SceneEditError.unknownNode(nodeID)
    }

    // MARK: Shape helpers

    /// Rescales a shape's path source so it fills a frame of `size`. Parametric
    /// sources (rounded rects, stars, callouts) just adopt the new natural
    /// size; explicit bezier paths have their points scaled from the old
    /// natural size to the new one.
    private static func resizePathSource(_ pathSource: inout TSD_PathSourceArchive, to size: Frame) {
        let newSize = TSP_Size.with { $0.width = Float(size.width); $0.height = Float(size.height) }

        func scaleFactors(from natural: TSP_Size) -> (Float, Float) {
            let ow = natural.width > 0 ? natural.width : Float(size.width)
            let oh = natural.height > 0 ? natural.height : Float(size.height)
            return (Float(size.width) / ow, Float(size.height) / oh)
        }
        func scale(_ point: inout TSP_Point, _ sx: Float, _ sy: Float) {
            point.x *= sx
            point.y *= sy
        }

        if pathSource.hasBezierPathSource {
            let (sx, sy) = scaleFactors(from: pathSource.bezierPathSource.naturalSize)
            for i in pathSource.bezierPathSource.path.elements.indices {
                for j in pathSource.bezierPathSource.path.elements[i].points.indices {
                    scale(&pathSource.bezierPathSource.path.elements[i].points[j], sx, sy)
                }
            }
            pathSource.bezierPathSource.naturalSize = newSize
        } else if pathSource.hasEditableBezierPathSource {
            let (sx, sy) = scaleFactors(from: pathSource.editableBezierPathSource.naturalSize)
            for s in pathSource.editableBezierPathSource.subpaths.indices {
                for n in pathSource.editableBezierPathSource.subpaths[s].nodes.indices {
                    scale(&pathSource.editableBezierPathSource.subpaths[s].nodes[n].inControlPoint, sx, sy)
                    scale(&pathSource.editableBezierPathSource.subpaths[s].nodes[n].nodePoint, sx, sy)
                    scale(&pathSource.editableBezierPathSource.subpaths[s].nodes[n].outControlPoint, sx, sy)
                }
            }
            pathSource.editableBezierPathSource.naturalSize = newSize
        } else if pathSource.hasPointPathSource {
            pathSource.pointPathSource.naturalSize = newSize
        } else if pathSource.hasScalarPathSource {
            pathSource.scalarPathSource.naturalSize = newSize
        } else if pathSource.hasCalloutPathSource {
            pathSource.calloutPathSource.naturalSize = newSize
        }
    }

    // MARK: Image helpers

    static func imageExtension(of data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if data.starts(with: [0xFF, 0xD8]) { return "jpeg" }
        if data.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        return "img"
    }

    /// Renders `data` scaled down so its long side is at most `maxDimension`,
    /// keeping the container format.
    static func imageData(_ data: Data, scaledToFit maxDimension: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let scale = min(1.0, Double(maxDimension) / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, scaled, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
