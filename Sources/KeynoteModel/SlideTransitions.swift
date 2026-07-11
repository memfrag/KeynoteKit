import Foundation
import IWAContainer
import KeynoteSchemas

/// A slide's transition (the animation to the *next* slide).
///
/// `effect` uses Keynote's internal names: `"apple:dissolve"`,
/// `"apple:3D-cube"`, `"apple:magic-move"`, `"apple:push"`,
/// `"apple:wipe"`, `"apple:fade-through-color"`, … and `"none"`.
public struct SlideTransition: Codable, Equatable, Sendable {
    public var effect: String
    public var duration: Double
    public var delay: Double
    /// Effect-specific direction constant (e.g. which way a cube turns).
    public var direction: UInt32?
    /// Advance to the next slide automatically after `delay`.
    public var isAutomatic: Bool

    public init(
        effect: String,
        duration: Double = 1.0,
        delay: Double = 0.5,
        direction: UInt32? = nil,
        isAutomatic: Bool = false
    ) {
        self.effect = effect
        self.duration = duration
        self.delay = delay
        self.direction = direction
        self.isAutomatic = isAutomatic
    }
}

extension KeynoteDocument {

    /// The transition of the slide at `index`, or nil when none is set.
    public func slideTransition(at index: Int) throws -> SlideTransition? {
        let (slide, _, _) = try slideArchive(at: index)
        guard slide.hasTransition, slide.transition.hasAttributes,
              slide.transition.attributes.hasAnimationAttributes
        else { return nil }
        let animation = slide.transition.attributes.animationAttributes
        guard animation.effect != "none", !animation.effect.isEmpty else { return nil }
        return SlideTransition(
            effect: animation.effect,
            duration: animation.duration,
            delay: animation.delay,
            direction: animation.hasDirection ? animation.direction : nil,
            isAutomatic: animation.isAutomatic
        )
    }

    /// Sets (or with nil, removes) the transition of the slide at `index`.
    public mutating func setSlideTransition(at index: Int, to transition: SlideTransition?) throws {
        let (slide, componentIndex, recordIndex) = try slideArchive(at: index)
        var updated = slide

        var animation = KN_AnimationAttributesArchive()
        animation.animationType = "Transition"
        animation.effect = transition?.effect ?? "none"
        animation.duration = transition?.duration ?? 1.0
        animation.delay = transition?.delay ?? 0.5
        if let direction = transition?.direction {
            animation.direction = direction
        }
        animation.isAutomatic = transition?.isAutomatic ?? false
        animation.randomNumberSeed = UInt32.random(in: 1...UInt32.max)
        updated.transition = KN_TransitionArchive.with {
            $0.attributes = KN_TransitionAttributesArchive.with {
                $0.animationAttributes = animation
            }
        }

        var record = components[componentIndex].records[recordIndex]
        try record.setMessage(updated)
        components[componentIndex].records[recordIndex] = record

        // The slide node caches whether a transition exists.
        let nodeIDs = try slideNodeIdentifiers()
        let nodeLocation = try locateSceneNode(nodeIDs[index])
        var nodeRecord = components[nodeLocation.component].records[nodeLocation.record]
        var node = try nodeRecord.decode(KN_SlideNodeArchive.self)
        node.hasTransition_p = transition != nil
        try nodeRecord.setMessage(node)
        components[nodeLocation.component].records[nodeLocation.record] = nodeRecord
    }

    /// The slide archive for a tree index, plus where its record lives.
    private func slideArchive(at index: Int) throws -> (KN_SlideArchive, Int, Int) {
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
