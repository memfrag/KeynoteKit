import Foundation
import IWAContainer
import KeynoteSchemas

/// A fillable text region on a slide — a placeholder or a text box — with the
/// several keys it can be addressed by. Use ``KeynoteDocument/slideTextBlocks(at:)``
/// to list them (or `iwatool blocks-of`), then target one with
/// ``KeynoteDocument/setSlideText(at:block:to:)``.
public struct SlideTextBlock: Sendable, Codable {
    /// The scene-node id (a stable handle; also usable with `setNodeText`).
    public let nodeID: UInt64
    /// "title", "body", "object", or nil for a free text box.
    public let role: String?
    /// The layout's prompt for this region ("Slide bullet text",
    /// "Attribution", …), when the master defines one.
    public let prompt: String?
    /// The text currently in the region — e.g. a label the template author
    /// typed to identify it ("LEFT COLUMN").
    public let text: String?
    /// The region's accessibility description ("Description" in Keynote's
    /// inspector), a clean way to label a block without visible text.
    public let label: String?
    /// Position and size, for disambiguating by geometry.
    public let frame: Frame?
}

public enum TextBlockError: Error {
    case noMatch(String)
    case ambiguous(String, matches: Int)
}

extension KeynoteDocument {

    /// Every text-fillable region on a slide, in reading order (placeholders
    /// then free text boxes, correlated to their master prompts).
    public func slideTextBlocks(at index: Int) throws -> [SlideTextBlock] {
        let nodes = try sceneTree(forSlideAt: index).nodes
        let fields = (try? layoutDescription(at: index).fields) ?? []

        var blocks: [SlideTextBlock] = []
        for node in nodes where node.type == "placeholder" || node.type == "shape" {
            // A placeholder correlates to the master field of the same role;
            // a free text box, to a field with the same frame.
            let field: PlaceholderField?
            if let role = node.role {
                field = fields.first { $0.role == role }
            } else {
                field = fields.first { $0.frame != nil && $0.frame == node.frame }
                    ?? fields.first { $0.role == "text" }
            }
            blocks.append(SlideTextBlock(
                nodeID: node.id,
                role: node.role,
                prompt: field?.prompt,
                text: node.text,
                label: node.label,
                frame: node.frame
            ))
        }
        return blocks
    }

    /// Sets the text of the block matching `key` on the slide at `index`.
    ///
    /// `key` is matched, in order, against each block's role, its current
    /// text (a label the template author typed), and its prompt — first an
    /// exact case-insensitive match, then a substring. Throws
    /// ``TextBlockError/noMatch(_:)`` if nothing matches and
    /// ``TextBlockError/ambiguous(_:matches:)`` if several exact matches tie.
    public mutating func setSlideText(at index: Int, block key: String, to text: String) throws {
        let blocks = try slideTextBlocks(at: index)
        let needle = key.lowercased()

        func exact(_ value: String?) -> Bool { value?.lowercased() == needle }
        func partial(_ value: String?) -> Bool { value?.lowercased().contains(needle) ?? false }
        // A leading "@" on an explicit label is optional in the key.
        func matchesLabel(_ value: String?) -> Bool {
            guard let value = value?.lowercased() else { return false }
            return value == needle || value == "@" + needle
        }

        // Priority cascade: an explicit label (a comment/description the
        // template author set) wins outright over every heuristic. Only when
        // nothing carries a matching label do we fall back to role, then the
        // typed placeholder text, then the layout prompt.
        let labelled = blocks.filter { matchesLabel($0.label) }
        if let target = labelled.first {
            if labelled.count > 1 { throw TextBlockError.ambiguous(key, matches: labelled.count) }
            try setNodeText(target.nodeID, to: text)
            return
        }

        let exactMatches = blocks.filter { exact($0.role) || exact($0.text) || exact($0.prompt) }
        let matches = exactMatches.isEmpty
            ? blocks.filter { partial($0.text) || partial($0.prompt) }
            : exactMatches

        guard let target = matches.first else {
            throw TextBlockError.noMatch(key)
        }
        if matches.count > 1, matches.allSatisfy({ exact($0.role) }) {
            // Genuinely ambiguous only when multiple share the same role
            // (e.g. two "body" placeholders) and nothing else disambiguates.
            throw TextBlockError.ambiguous(key, matches: matches.count)
        }
        try setNodeText(target.nodeID, to: text)
    }
}
