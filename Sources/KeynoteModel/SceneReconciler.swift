import Foundation

/// Applies an edited `SceneTree` back to the document by diffing it against
/// the current tree and translating the differences into validated commands
/// (`setNodeText`, `setNodeFrame`, `setNodeMedia`, `deleteDrawable`,
/// `reorderDrawables`). Edits that can't be expressed as safe operations —
/// new nodes, reparenting, type/role changes — are rejected.
extension KeynoteDocument {

    /// Applies `edited` to the slide it describes.
    ///
    /// Supported edits: text changes, frame changes, notes changes, media
    /// replacement (via `media` keyed by node id, or a `replaceWith` file
    /// path on the node), deleting free drawables (drop the node from the
    /// tree), and restacking free drawables (reorder them in `nodes`).
    public mutating func apply(_ edited: SceneTree, media: [UInt64: Data] = [:]) throws {
        let current = try sceneTree(forSlideAt: edited.slideIndex)
        let currentByID = flatten(current.nodes)
        let editedByID = flatten(edited.nodes)

        // New nodes can't be synthesized.
        for id in editedByID.keys where currentByID[id] == nil {
            throw SceneEditError.unsupportedEdit(
                "node \(id) does not exist on slide \(edited.slideIndex); adding nodes is not supported"
            )
        }

        // Deletions: free drawables only (validated by deleteDrawable).
        for (id, node) in currentByID where editedByID[id] == nil {
            if node.type == "placeholder" {
                throw SceneEditError.cannotDeletePlaceholder(id)
            }
            try deleteDrawable(id)
        }

        // Property edits.
        for (id, editedNode) in editedByID {
            guard let currentNode = currentByID[id] else { continue }

            if editedNode.type != currentNode.type || editedNode.role != currentNode.role {
                throw SceneEditError.unsupportedEdit("node \(id): type/role changes are not supported")
            }

            let normalizedEdited = editedNode.text?.replacingOccurrences(of: "\n", with: "\u{2029}")
            if normalizedEdited != currentNode.text {
                guard let text = normalizedEdited else {
                    throw SceneEditError.unsupportedEdit("node \(id): removing text is not supported; set it to \"\"")
                }
                try setNodeText(id, to: text)
            }

            if let frame = editedNode.frame, frame != currentNode.frame {
                try setNodeFrame(id, to: frame)
            }

            if let replacement = try mediaReplacement(for: editedNode, explicit: media[id]) {
                try setNodeMedia(id, to: replacement)
            }
        }

        // Restacking: compare the free-drawable sequence (placeholders are
        // pinned; only z-ordered drawables reorder).
        let currentOrder = current.nodes.filter { $0.type != "placeholder" }.map(\.id)
        let editedOrder = edited.nodes.filter { $0.type != "placeholder" }.map(\.id)
            .filter { currentByID[$0] != nil && editedByID[$0] != nil }
        let survivingOrder = currentOrder.filter { editedByID[$0] != nil }
        if editedOrder != survivingOrder, Set(editedOrder) == Set(survivingOrder) {
            try reorderDrawables(onSlideAt: edited.slideIndex, to: editedOrder)
        }

        // Notes.
        let currentNotes = current.notes ?? ""
        if let editedNotes = edited.notes, editedNotes != currentNotes {
            try setSlideText(at: edited.slideIndex, .notes, to: editedNotes)
        }
    }

    private func mediaReplacement(for node: SceneNode, explicit: Data?) throws -> Data? {
        if let explicit { return explicit }
        guard let path = node.media?.replaceWith else { return nil }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    private func flatten(_ nodes: [SceneNode]) -> [UInt64: SceneNode] {
        var result: [UInt64: SceneNode] = [:]
        for node in nodes {
            result[node.id] = node
            for (id, child) in flatten(node.children) {
                result[id] = child
            }
        }
        return result
    }
}
