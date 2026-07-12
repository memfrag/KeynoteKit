import Foundation
import IWAContainer
import KeynoteSchemas
import SwiftProtobuf

public enum BuildError: Error {
    case buildNotFound(UInt64)
    case nodeNotOnSlide(UInt64)
}

/// One element animation: a build-in (`kind == "In"`), build-out (`"Out"`),
/// or action build on a drawable. `effect` uses Keynote's internal names
/// (`"apple:bc-appear"`, `"apple:dissolve"`, …).
public struct SlideBuild: Codable, Equatable, Sendable {
    /// The build's own object id (read-only; use 0 when adding).
    public var id: UInt64
    /// The drawable this build animates.
    public var nodeID: UInt64
    /// "In", "Out", or an action type.
    public var kind: String
    public var effect: String
    public var duration: Double
    public var delay: Double

    // Parameters (optional; omitted = the effect's default).

    /// How a multi-paragraph object is delivered: "All at Once", "By
    /// Paragraph", "By Paragraph Group", or "By Highlighted Paragraph".
    public var delivery: String?
    /// How text builds: "byObject", "byWord", "byCharacter", or "byLine".
    public var textDelivery: String?
    /// "forward" or "backward".
    public var deliveryOption: String?
    /// Effect-specific direction constant.
    public var direction: UInt32?
    /// Travel distance for move-style effects, as a fraction (0.07 = 7%).
    public var travelDistance: Double?
    /// Action-build parameters (Rotate / Scale / Opacity actions).
    public var rotationAngle: Double?
    public var scaleSize: Double?
    public var opacity: Double?

    public init(
        id: UInt64 = 0, nodeID: UInt64, kind: String, effect: String,
        duration: Double = 1.0, delay: Double = 0.0,
        delivery: String? = nil, textDelivery: String? = nil, deliveryOption: String? = nil,
        direction: UInt32? = nil, travelDistance: Double? = nil, rotationAngle: Double? = nil,
        scaleSize: Double? = nil, opacity: Double? = nil
    ) {
        self.id = id
        self.nodeID = nodeID
        self.kind = kind
        self.effect = effect
        self.duration = duration
        self.delay = delay
        self.delivery = delivery
        self.travelDistance = travelDistance
        self.textDelivery = textDelivery
        self.deliveryOption = deliveryOption
        self.direction = direction
        self.rotationAngle = rotationAngle
        self.scaleSize = scaleSize
        self.opacity = opacity
    }
}

/// The paragraph-delivery options in Keynote's build inspector, for
/// ``SlideBuild/delivery``.
public enum BuildDelivery {
    public static let allAtOnce = "All at Once"
    public static let byParagraph = "By Paragraph"
    public static let byParagraphGroup = "By Paragraph Group"
    public static let byHighlightedParagraph = "By Highlighted Paragraph"
}

/// String names for the delivery enums.
enum BuildEnumNames {
    static let textDelivery: [KN_BuildAttributesArchive.BuildAttributesTextDelivery: String] = [
        .kTextDeliveryByObject: "byObject",
        .kTextDeliveryByWord: "byWord",
        .kTextDeliveryByCharacter: "byCharacter",
        .kTextDeliveryByLine: "byLine",
    ]
    static let deliveryOption: [KN_BuildAttributesArchive.BuildAttributesDeliveryOption: String] = [
        .kDeliveryOptionForward: "forward",
        .kDeliveryOptionBackward: "backward",
    ]
}

/// Element builds (animations). A `KN.BuildArchive` (type 8) targets a
/// drawable and carries the animation attributes; a `KN.BuildChunkArchive`
/// (type 153) sequences it. The slide lists both (`builds`, `buildChunks` —
/// chunk order is playback order), and the slide node caches `hasBuilds`.
extension KeynoteDocument {

    // MARK: Reading

    public func slideBuilds(at index: Int) throws -> [SlideBuild] {
        let (slide, componentIndex, _) = try slideArchiveLocation(at: index)
        let component = components[componentIndex]
        var result: [SlideBuild] = []
        // Report in playback order (chunk order).
        for chunkReference in slide.buildChunks {
            guard let chunkRecord = component.records.first(where: { $0.identifier == chunkReference.identifier }),
                  chunkRecord.primaryType == 153,
                  let chunk = try? chunkRecord.decode(KN_BuildChunkArchive.self),
                  chunk.hasBuild,
                  let buildRecord = component.records.first(where: { $0.identifier == chunk.build.identifier }),
                  let build = try? buildRecord.decode(KN_BuildArchive.self)
            else { continue }
            let animation = build.attributes.animationAttributes
            let attributes = build.attributes
            result.append(SlideBuild(
                id: chunk.build.identifier,
                nodeID: build.drawable.identifier,
                kind: animation.animationType,
                effect: animation.effect,
                duration: animation.duration,
                delay: animation.delay,
                delivery: build.hasDelivery && !build.delivery.isEmpty ? build.delivery : nil,
                textDelivery: attributes.hasCustomTextDelivery
                    ? BuildEnumNames.textDelivery[attributes.customTextDelivery] : nil,
                deliveryOption: attributes.hasCustomDeliveryOption
                    ? BuildEnumNames.deliveryOption[attributes.customDeliveryOption] : nil,
                direction: animation.hasDirection ? animation.direction : nil,
                travelDistance: attributes.hasCustomTravelDistance ? Double(attributes.customTravelDistance) : nil,
                rotationAngle: attributes.hasActionRotationAngle ? attributes.actionRotationAngle : nil,
                scaleSize: attributes.hasActionScaleSize ? attributes.actionScaleSize : nil,
                opacity: attributes.hasActionColorAlpha ? attributes.actionColorAlpha : nil
            ))
        }
        return result
    }

    // MARK: Adding

    /// Adds a build to a drawable on the slide, appended to the playback
    /// order. Returns the new build's id.
    @discardableResult
    public mutating func addBuild(_ build: SlideBuild, toSlideAt index: Int) throws -> UInt64 {
        var (slide, componentIndex, recordIndex) = try slideArchiveLocation(at: index)
        guard components[componentIndex].records.contains(where: { $0.identifier == build.nodeID }) else {
            throw BuildError.nodeNotOnSlide(build.nodeID)
        }

        // Allocate identifiers.
        let metadataLocation = try locateRecord(type: 11006, orThrow: MediaOperationError.packageMetadataNotFound)
        var metadataRecord = components[metadataLocation.component].records[metadataLocation.record]
        var metadata = try metadataRecord.decode(TSP_PackageMetadata.self)
        let buildID = metadata.lastObjectIdentifier + 1
        let chunkID = metadata.lastObjectIdentifier + 2
        metadata.lastObjectIdentifier = chunkID
        try metadataRecord.setMessage(metadata)
        components[metadataLocation.component].records[metadataLocation.record] = metadataRecord

        // Mirror the version stamp of the slide's own record.
        let version = components[componentIndex].records[recordIndex].info.messageInfos[0].version

        let buildArchive = KN_BuildArchive.with {
            $0.drawable = TSP_Reference.with { $0.identifier = build.nodeID }
            $0.delivery = build.delivery ?? "All at Once"
            $0.attributes = KN_BuildAttributesArchive.with {
                $0.eventTrigger = 1
                $0.animationAttributes = KN_AnimationAttributesArchive.with {
                    $0.animationType = build.kind
                    $0.effect = build.effect
                    $0.duration = build.duration
                    $0.delay = build.delay
                    if let direction = build.direction { $0.direction = direction }
                    $0.randomNumberSeed = UInt32.random(in: 1...UInt32.max)
                }
                if let name = build.textDelivery,
                   let value = BuildEnumNames.textDelivery.first(where: { $0.value == name })?.key {
                    $0.customTextDelivery = value
                }
                if let name = build.deliveryOption,
                   let value = BuildEnumNames.deliveryOption.first(where: { $0.value == name })?.key {
                    $0.customDeliveryOption = value
                }
                if let travel = build.travelDistance { $0.customTravelDistance = travel }
                if let angle = build.rotationAngle { $0.actionRotationAngle = angle }
                if let scale = build.scaleSize { $0.actionScaleSize = scale }
                if let alpha = build.opacity { $0.actionColorAlpha = alpha }
            }
            $0.chunkIDSeed = 1
        }
        let buildUUID = TSP_UUID.with {
            $0.lower = UInt64.random(in: UInt64.min...UInt64.max)
            $0.upper = UInt64.random(in: UInt64.min...UInt64.max)
        }
        let chunkArchive = KN_BuildChunkArchive.with {
            $0.build = TSP_Reference.with { $0.identifier = buildID }
            $0.delay = 0
            $0.duration = build.duration
            $0.automatic = false
            $0.referent = true
            $0.buildChunkIdentifier = KN_BuildChunkIdentifierArchive.with {
                $0.buildID = buildUUID
                $0.buildChunkID = 1
            }
            $0.buildID = buildUUID
        }

        components[componentIndex].records.append(try makeRecord(
            identifier: buildID, type: 8, message: buildArchive,
            version: version, objectReferences: []
        ))
        components[componentIndex].records.append(try makeRecord(
            identifier: chunkID, type: 153, message: chunkArchive,
            version: version, objectReferences: []
        ))

        // Wire into the slide and its node cache.
        slide.builds.append(TSP_Reference.with { $0.identifier = buildID })
        slide.buildChunks.append(TSP_Reference.with { $0.identifier = chunkID })
        var slideRecord = components[componentIndex].records[recordIndex]
        try slideRecord.setMessage(slide)
        try slideRecord.setObjectReferences(
            slideRecord.info.messageInfos[0].objectReferences + [buildID, chunkID], at: 0
        )
        components[componentIndex].records[recordIndex] = slideRecord
        try setNodeBuildFlags(at: index, hasBuilds: true)
        return buildID
    }

    // MARK: Ordering

    /// Reorders the element animations on a slide. `order` must contain exactly
    /// the current build ids (as ``slideBuilds(at:)`` reports them), in the new
    /// playback order.
    public mutating func reorderBuilds(onSlideAt index: Int, order buildIDs: [UInt64]) throws {
        var (slide, componentIndex, recordIndex) = try slideArchiveLocation(at: index)
        let existing = Set(slide.builds.map(\.identifier))
        guard Set(buildIDs) == existing else {
            throw BuildError.buildNotFound(buildIDs.first(where: { !existing.contains($0) }) ?? 0)
        }
        let rank = Dictionary(uniqueKeysWithValues: buildIDs.enumerated().map { ($1, $0) })

        func buildID(ofChunk reference: TSP_Reference) -> UInt64? {
            guard let record = components[componentIndex].records.first(where: { $0.identifier == reference.identifier }),
                  record.primaryType == 153,
                  let chunk = try? record.decode(KN_BuildChunkArchive.self)
            else { return nil }
            return chunk.build.identifier
        }
        // Chunk order is playback order; sort chunks (and the builds list) by
        // the requested rank of the build they animate.
        slide.buildChunks.sort {
            (buildID(ofChunk: $0).flatMap { rank[$0] } ?? 0) < (buildID(ofChunk: $1).flatMap { rank[$0] } ?? 0)
        }
        slide.builds.sort { (rank[$0.identifier] ?? 0) < (rank[$1.identifier] ?? 0) }

        var slideRecord = components[componentIndex].records[recordIndex]
        try slideRecord.setMessage(slide)
        components[componentIndex].records[recordIndex] = slideRecord
    }

    // MARK: Removing

    /// Removes a build (by the id `slideBuilds` reports) and its chunks.
    public mutating func removeBuild(_ buildID: UInt64, fromSlideAt index: Int) throws {
        var (slide, componentIndex, recordIndex) = try slideArchiveLocation(at: index)
        guard slide.builds.contains(where: { $0.identifier == buildID }) else {
            throw BuildError.buildNotFound(buildID)
        }

        // Chunks pointing at this build.
        var chunkIDs: Set<UInt64> = []
        for reference in slide.buildChunks {
            if let record = components[componentIndex].records.first(where: { $0.identifier == reference.identifier }),
               record.primaryType == 153,
               let chunk = try? record.decode(KN_BuildChunkArchive.self),
               chunk.build.identifier == buildID {
                chunkIDs.insert(reference.identifier)
            }
        }

        slide.builds.removeAll { $0.identifier == buildID }
        slide.buildChunks.removeAll { chunkIDs.contains($0.identifier) }
        let removed = chunkIDs.union([buildID])
        var slideRecord = components[componentIndex].records[recordIndex]
        try slideRecord.setMessage(slide)
        try slideRecord.setObjectReferences(
            slideRecord.info.messageInfos[0].objectReferences.filter { !removed.contains($0) }, at: 0
        )
        components[componentIndex].records[recordIndex] = slideRecord
        components[componentIndex].records.removeAll {
            $0.identifier.map { removed.contains($0) } ?? false
        }
        try setNodeBuildFlags(at: index, hasBuilds: !slide.builds.isEmpty)
    }

    // MARK: Helpers

    private mutating func setNodeBuildFlags(at index: Int, hasBuilds: Bool) throws {
        let nodeIDs = try slideNodeIdentifiers()
        let location = try locateSceneNode(nodeIDs[index])
        var record = components[location.component].records[location.record]
        var node = try record.decode(KN_SlideNodeArchive.self)
        node.hasBuilds_p = hasBuilds
        node.hasExplicitBuilds_p = hasBuilds
        // Invalidate the cached counts so Keynote recomputes them.
        node.buildEventCountCacheVersion = UInt32.max
        node.hasExplicitBuildsCacheVersion_p = UInt32.max
        try record.setMessage(node)
        components[location.component].records[location.record] = record
    }

    /// Creates a fresh single-message record.
    func makeRecord(
        identifier: UInt64,
        type: UInt32,
        message: any SwiftProtobuf.Message,
        version: [UInt32],
        objectReferences: [UInt64]
    ) throws -> ObjectRecord {
        let payload: Data = try message.serializedData()
        let info = TSP_ArchiveInfo.with {
            $0.identifier = identifier
            $0.messageInfos = [TSP_MessageInfo.with {
                $0.type = type
                $0.version = version
                $0.length = UInt32(payload.count)
                $0.objectReferences = objectReferences
            }]
        }
        return try ObjectRecord(ArchiveRecord(
            identifier: identifier,
            messageTypes: [type],
            messageLengths: [payload.count],
            archiveInfo: try info.serializedData(),
            payload: payload
        ))
    }

    /// The slide archive at a tree index, plus its record's location.
    func slideArchiveLocation(at index: Int) throws -> (KN_SlideArchive, Int, Int) {
        let nodeIDs = try slideNodeIdentifiers()
        guard nodeIDs.indices.contains(index) else {
            throw SlideContentError.slideIndexOutOfRange(index)
        }
        let node = try recordAnywhere(identifier: nodeIDs[index], type: 4).decode(KN_SlideNodeArchive.self)
        let slideRootID = node.slide.identifier
        for (componentIndex, component) in components.enumerated() {
            if let recordIndex = component.records.firstIndex(where: { $0.identifier == slideRootID }) {
                let slide = try component.records[recordIndex].decode(KN_SlideArchive.self)
                return (slide, componentIndex, recordIndex)
            }
        }
        throw SlideContentError.slideComponentNotFound(slideRootID)
    }
}
