import Foundation
import IWAContainer
import KeynoteSchemas
import SwiftProtobuf

public enum SlideOperationError: Error {
    case showArchiveNotFound
    case packageMetadataNotFound
    case documentComponentNotFound
    case slideIndexOutOfRange(Int)
    case slideNodeNotFound(UInt64)
    case slideComponentNotFound(UInt64)
    case cannotRemoveLastSlide
}

/// Slide-level operations: duplicate, remove, reorder.
///
/// The slide list lives in `KN.ShowArchive.slideTree.slides` (references to
/// `KN.SlideNodeArchive` records in Document.iwa); each node references a
/// `KN.SlideArchive` that is the root object of its own `Slide-<id>.iwa`
/// component. Duplication deep-copies the component with fresh identifiers
/// (rewriting internal references, keeping external ones) and maintains the
/// package metadata: the clone's `ComponentInfo` (fresh object UUIDs), the
/// Document component's cross-component references, data-usage bookkeeping,
/// and `last_object_identifier`.
extension KeynoteDocument {

    // MARK: Slide list

    public func slideNodeIdentifiers() throws -> [UInt64] {
        let show = try showRecord().decode(KN_ShowArchive.self)
        return show.slideTree.slides.map(\.identifier)
    }

    public var slideCount: Int {
        (try? slideNodeIdentifiers().count) ?? 0
    }

    // MARK: Reorder

    public mutating func moveSlide(from source: Int, to destination: Int) throws {
        let location = try locate(type: 2, orThrow: SlideOperationError.showArchiveNotFound)
        var record = components[location.component].records[location.record]
        var show = try record.decode(KN_ShowArchive.self)
        guard show.slideTree.slides.indices.contains(source),
              show.slideTree.slides.indices.contains(destination) else {
            throw SlideOperationError.slideIndexOutOfRange(max(source, destination))
        }
        let reference = show.slideTree.slides.remove(at: source)
        show.slideTree.slides.insert(reference, at: destination)
        try record.setMessage(show)
        components[location.component].records[location.record] = record
    }

    // MARK: Duplicate

    /// Duplicates the slide at `index`, inserting the copy right after it.
    /// Returns the new slide's root object identifier.
    @discardableResult
    public mutating func duplicateSlide(at index: Int) throws -> UInt64 {
        let showLocation = try locate(type: 2, orThrow: SlideOperationError.showArchiveNotFound)
        var showRecord = components[showLocation.component].records[showLocation.record]
        var show = try showRecord.decode(KN_ShowArchive.self)
        guard show.slideTree.slides.indices.contains(index) else {
            throw SlideOperationError.slideIndexOutOfRange(index)
        }
        let nodeID = show.slideTree.slides[index].identifier

        let nodeLocation = try locateNode(nodeID)
        let nodeRecord = components[nodeLocation.component].records[nodeLocation.record]
        let slideRootID = try nodeRecord.decode(KN_SlideNodeArchive.self).slide.identifier

        // Package metadata drives identifier allocation.
        let metadataLocation = try locate(type: 11006, orThrow: SlideOperationError.packageMetadataNotFound)
        var metadataRecord = components[metadataLocation.component].records[metadataLocation.record]
        var metadata = try metadataRecord.decode(TSP_PackageMetadata.self)
        var nextIdentifier = metadata.lastObjectIdentifier

        guard let sourceComponentIndex = components.firstIndex(where: { component in
            component.records.first?.identifier == slideRootID || component.records.contains { $0.identifier == slideRootID }
        }) else {
            throw SlideOperationError.slideComponentNotFound(slideRootID)
        }
        let sourceComponent = components[sourceComponentIndex]

        // Fresh identifiers for every object in the slide component + the node.
        var idMap: [UInt64: UInt64] = [:]
        for record in sourceComponent.records {
            if let identifier = record.identifier {
                nextIdentifier += 1
                idMap[identifier] = nextIdentifier
            }
        }
        nextIdentifier += 1
        let newNodeID = nextIdentifier
        idMap[nodeID] = newNodeID
        guard let newRootID = idMap[slideRootID] else {
            throw SlideOperationError.slideComponentNotFound(slideRootID)
        }

        // NOTE: addComponent mutates the components array and would shift
        // every RecordLocation captured above — it must stay the LAST step.
        let newPath = "Index/Slide-\(newRootID).iwa"
        let clonedRecords = try sourceComponent.records.map { try cloned($0, using: idMap) }

        do {
            // Clone the slide node; mark thumbnails stale so Keynote regenerates.
            var newNode = try cloned(nodeRecord, using: idMap)
            var nodeArchive = try newNode.decode(KN_SlideNodeArchive.self)
            nodeArchive.thumbnailsAreDirty = true
            try newNode.setMessage(nodeArchive)
            components[nodeLocation.component].records.insert(newNode, at: nodeLocation.record + 1)

            // Insert into the slide tree and update reference bookkeeping.
            show.slideTree.slides.insert(TSP_Reference.with { $0.identifier = newNodeID }, at: index + 1)
            try showRecord.setMessage(show)
            try showRecord.setObjectReferences(showRecord.info.messageInfos[0].objectReferences + [newNodeID], at: 0)
            components[showLocation.component].records[showLocation.record] = showRecord
        }

        do {
            // Metadata: clone the slide's ComponentInfo with fresh object UUIDs.
            guard let sourceInfoIndex = metadata.components.firstIndex(where: { $0.identifier == slideRootID }) else {
                throw SlideOperationError.slideComponentNotFound(slideRootID)
            }
            var newInfo = metadata.components[sourceInfoIndex]
            newInfo.identifier = newRootID
            newInfo.locator = "Slide-\(newRootID)"
            newInfo.objectUuidMapEntries = newInfo.objectUuidMapEntries.map { entry in
                var updated = entry
                updated.identifier = idMap[entry.identifier] ?? entry.identifier
                updated.uuid = randomUUID()
                return updated
            }
            newInfo.dataReferences = newInfo.dataReferences.map { dataReference in
                var updated = dataReference
                updated.objectReferenceList = dataReference.objectReferenceList.map { objectReference in
                    var mapped = objectReference
                    mapped.objectIdentifier = idMap[objectReference.objectIdentifier] ?? objectReference.objectIdentifier
                    return mapped
                }
                return updated
            }
            metadata.components.insert(newInfo, at: sourceInfoIndex + 1)
        }

        // Document component: it references the slide component root and the
        // node's thumbnail data; mirror those entries for the clone.
        if let documentInfoIndex = metadata.components.firstIndex(where: { $0.preferredLocator == "Document" }) {
            var documentInfo = metadata.components[documentInfoIndex]
            do {
                let mirrored = documentInfo.externalReferences
                    .filter { $0.componentIdentifier == slideRootID }
                    .map { reference in
                        var updated = reference
                        updated.componentIdentifier = newRootID
                        if reference.hasObjectIdentifier {
                            updated.objectIdentifier = idMap[reference.objectIdentifier] ?? reference.objectIdentifier
                        }
                        return updated
                    }
                documentInfo.externalReferences.append(contentsOf: mirrored)
            }
            do {
                documentInfo.dataReferences = documentInfo.dataReferences.map { dataReference in
                    var updated = dataReference
                    for objectReference in dataReference.objectReferenceList
                    where objectReference.objectIdentifier == nodeID {
                        var mirroredUsage = objectReference
                        mirroredUsage.objectIdentifier = newNodeID
                        updated.objectReferenceList.append(mirroredUsage)
                    }
                    return updated
                }
                documentInfo.objectUuidMapEntries = documentInfo.objectUuidMapEntries.flatMap { entry -> [TSP_ObjectUUIDMapEntry] in
                    guard entry.identifier == nodeID else { return [entry] }
                    var mirroredEntry = entry
                    mirroredEntry.identifier = newNodeID
                    mirroredEntry.uuid = randomUUID()
                    return [entry, mirroredEntry]
                }
            }
            metadata.components[documentInfoIndex] = documentInfo
        }

        metadata.lastObjectIdentifier = nextIdentifier
        try metadataRecord.setMessage(metadata)
        components[metadataLocation.component].records[metadataLocation.record] = metadataRecord

        addComponent(path: newPath, records: clonedRecords, after: sourceComponent.path)

        return newRootID
    }

    // MARK: Remove

    public mutating func removeSlide(at index: Int) throws {
        let showLocation = try locate(type: 2, orThrow: SlideOperationError.showArchiveNotFound)
        var showRecord = components[showLocation.component].records[showLocation.record]
        var show = try showRecord.decode(KN_ShowArchive.self)
        guard show.slideTree.slides.indices.contains(index) else {
            throw SlideOperationError.slideIndexOutOfRange(index)
        }
        guard show.slideTree.slides.count > 1 else {
            throw SlideOperationError.cannotRemoveLastSlide
        }
        let nodeID = show.slideTree.slides[index].identifier

        let nodeLocation = try locateNode(nodeID)
        let nodeRecord = components[nodeLocation.component].records[nodeLocation.record]
        let slideRootID = try nodeRecord.decode(KN_SlideNodeArchive.self).slide.identifier

        // Slide tree + node record.
        show.slideTree.slides.remove(at: index)
        try showRecord.setMessage(show)
        var showReferences = showRecord.info.messageInfos[0].objectReferences
        if let referenceIndex = showReferences.firstIndex(of: nodeID) {
            showReferences.remove(at: referenceIndex)
        }
        try showRecord.setObjectReferences(showReferences, at: 0)
        components[showLocation.component].records[showLocation.record] = showRecord
        components[nodeLocation.component].records.remove(at: nodeLocation.record)

        // Slide component. (Data/ media it referenced is left in place —
        // orphaned data is tolerated; Keynote garbage-collects on save.)
        if let componentIndex = components.firstIndex(where: { $0.records.contains { $0.identifier == slideRootID } }) {
            removeComponent(path: components[componentIndex].path)
        }

        // Metadata bookkeeping.
        let metadataLocation = try locate(type: 11006, orThrow: SlideOperationError.packageMetadataNotFound)
        var metadataRecord = components[metadataLocation.component].records[metadataLocation.record]
        var metadata = try metadataRecord.decode(TSP_PackageMetadata.self)
        metadata.components.removeAll { $0.identifier == slideRootID }
        if let documentInfoIndex = metadata.components.firstIndex(where: { $0.preferredLocator == "Document" }) {
            var documentInfo = metadata.components[documentInfoIndex]
            documentInfo.externalReferences.removeAll { $0.componentIdentifier == slideRootID }
            documentInfo.dataReferences = documentInfo.dataReferences.map { dataReference in
                var updated = dataReference
                updated.objectReferenceList.removeAll { $0.objectIdentifier == nodeID }
                return updated
            }
            documentInfo.objectUuidMapEntries.removeAll { $0.identifier == nodeID }
            metadata.components[documentInfoIndex] = documentInfo
        }
        try metadataRecord.setMessage(metadata)
        components[metadataLocation.component].records[metadataLocation.record] = metadataRecord
    }

    // MARK: Helpers

    private func locate(type: UInt32, orThrow error: SlideOperationError) throws -> RecordLocation {
        try locateRecord(type: type, orThrow: error)
    }

    private func locateNode(_ nodeID: UInt64) throws -> RecordLocation {
        for (componentIndex, component) in components.enumerated() {
            if let recordIndex = component.records.firstIndex(where: {
                $0.identifier == nodeID && $0.primaryType == 4
            }) {
                return RecordLocation(component: componentIndex, record: recordIndex)
            }
        }
        throw SlideOperationError.slideNodeNotFound(nodeID)
    }

    private func showRecord() throws -> ObjectRecord {
        let location = try locate(type: 2, orThrow: SlideOperationError.showArchiveNotFound)
        return components[location.component].records[location.record]
    }

    /// Deep-copies a record: fresh identifier, internal references rewritten
    /// through `idMap` (identifiers not in the map — external objects — stay).
    func cloned(_ record: ObjectRecord, using idMap: [UInt64: UInt64]) throws -> ObjectRecord {
        var copy = record
        if let identifier = record.identifier {
            copy.setIdentifier(idMap[identifier] ?? identifier)
        }
        for (payloadIndex, info) in record.info.messageInfos.enumerated() {
            if let typeName = TSPRegistry.protoNames[info.type] {
                let rewritten = try ReferenceRewriter.rewrite(
                    record.payloads[payloadIndex],
                    typeName: typeName,
                    using: idMap
                )
                try copy.setPayloadData(rewritten, at: payloadIndex)
            }
            try copy.setObjectReferences(info.objectReferences.map { idMap[$0] ?? $0 }, at: payloadIndex)
        }
        return copy
    }

    private func randomUUID() -> TSP_UUID {
        TSP_UUID.with {
            $0.lower = UInt64.random(in: UInt64.min...UInt64.max)
            $0.upper = UInt64.random(in: UInt64.min...UInt64.max)
        }
    }
}
