import Foundation
import IWAContainer
import KeynoteSchemas

/// A DOM-like view of one slide: its drawables and placeholders as a typed,
/// JSON-serializable node tree. Node `id`s are the document's own object
/// identifiers, so they are stable handles for edits (see `apply`).
///
/// The JSON shape is currently internal and may evolve.
public struct SceneTree: Codable {
    public var slideIndex: Int
    public var master: String?
    public var notes: String?
    /// The transition to the next slide (editable; nil = none).
    public var transition: SlideTransition?
    /// Placeholders first (title, body, object, slideNumber), then free
    /// drawables in z-order, back to front.
    public var nodes: [SceneNode]
}

public struct SceneNode: Codable {
    public var id: UInt64
    /// "placeholder", "image", "shape", "group", "movie", "connectionLine",
    /// or "unknown-<type>".
    public var type: String
    /// For placeholders: "title", "body", "object", "slideNumber".
    public var role: String?
    /// The master's instructional prompt for this role (what the field is
    /// for), where available. Read-only.
    public var prompt: String?
    /// Authored text content, if the node has a text storage.
    public var text: String?
    public var frame: Frame?
    public var media: MediaReference?
    /// For `"table"` nodes: the cell grid as display strings (nil = empty
    /// cell). Editable — the reconciler turns changed cells into
    /// `setTableCellText`/`setTableCellNumber`.
    public var cells: [[String?]]?
    public var children: [SceneNode]
    /// Write-side: to add a node, append a `SceneNode` whose `cloneOf` names
    /// an existing drawable anywhere in the document (e.g. a template
    /// slide's). On `apply` the source is cloned onto this slide, then this
    /// node's text/frame/media edits are applied to the clone. `id` is
    /// ignored (use 0). Never set when reading.
    public var cloneOf: UInt64?

    public init(
        id: UInt64, type: String, role: String? = nil, prompt: String? = nil,
        text: String? = nil, frame: Frame? = nil, media: MediaReference? = nil,
        cells: [[String?]]? = nil, children: [SceneNode] = [], cloneOf: UInt64? = nil
    ) {
        self.id = id
        self.type = type
        self.role = role
        self.prompt = prompt
        self.text = text
        self.frame = frame
        self.media = media
        self.cells = cells
        self.children = children
        self.cloneOf = cloneOf
    }
}

public struct MediaReference: Codable {
    public var dataID: UInt64
    /// File name under `Data/`, when the media is materialized in the
    /// document (theme stock images may not be).
    public var file: String?
    /// Write-side: absolute path to a file whose contents should replace
    /// this media on `apply`. Never set when reading.
    public var replaceWith: String?
}

extension KeynoteDocument {

    public func sceneTrees() throws -> [SceneTree] {
        try (0..<slideCount).map { try sceneTree(forSlideAt: $0) }
    }

    public func sceneTree(forSlideAt index: Int) throws -> SceneTree {
        let nodeIDs = try slideNodeIdentifiers()
        guard nodeIDs.indices.contains(index) else {
            throw SlideContentError.slideIndexOutOfRange(index)
        }
        let node = try recordAnywhere(identifier: nodeIDs[index], type: 4).decode(KN_SlideNodeArchive.self)
        let slideRootID = node.slide.identifier
        guard let componentIndex = components.firstIndex(where: {
            $0.records.contains { $0.identifier == slideRootID }
        }) else {
            throw SlideContentError.slideComponentNotFound(slideRootID)
        }
        let component = components[componentIndex]
        let slideRecord = component.records.first { $0.identifier == slideRootID }!
        let slide = try slideRecord.decode(KN_SlideArchive.self)

        // Prompts by role, from the master.
        var promptByRole: [String: String] = [:]
        var masterName: String?
        if let (masterRecord, masterComponentIndex) = try masterRecordAndComponent(forSlideAt: index) {
            let master = try masterRecord.decode(KN_SlideArchive.self)
            masterName = master.hasName ? master.name : nil
            var roleByID: [UInt64: String] = [:]
            if master.hasTitlePlaceholder { roleByID[master.titlePlaceholder.identifier] = "title" }
            if master.hasBodyPlaceholder { roleByID[master.bodyPlaceholder.identifier] = "body" }
            if master.hasObjectPlaceholder { roleByID[master.objectPlaceholder.identifier] = "object" }
            for entry in master.instructionalTextMap.instructionalTextForInfos {
                if let role = roleByID[entry.info.identifier] {
                    promptByRole[role] = entry.instructionalText
                }
            }
            _ = masterComponentIndex
        }

        var nodes: [SceneNode] = []
        var seen: Set<UInt64> = []

        // Named placeholders first.
        let named: [(TSP_Reference, String, Bool)] = [
            (slide.titlePlaceholder, "title", slide.hasTitlePlaceholder),
            (slide.bodyPlaceholder, "body", slide.hasBodyPlaceholder),
            (slide.objectPlaceholder, "object", slide.hasObjectPlaceholder),
            (slide.slideNumberPlaceholder, "slideNumber", slide.hasSlideNumberPlaceholder),
        ]
        for (reference, role, present) in named where present {
            if let sceneNode = try buildNode(id: reference.identifier, in: component, role: role, promptByRole: promptByRole) {
                nodes.append(sceneNode)
                seen.insert(reference.identifier)
            }
        }

        // Free drawables in z-order (fall back to ownership order).
        let drawableRefs = slide.drawablesZOrder.isEmpty ? slide.ownedDrawables : slide.drawablesZOrder
        for reference in drawableRefs where !seen.contains(reference.identifier) {
            if let sceneNode = try buildNode(id: reference.identifier, in: component, role: nil, promptByRole: promptByRole) {
                nodes.append(sceneNode)
                seen.insert(reference.identifier)
            }
        }

        return SceneTree(
            slideIndex: index,
            master: masterName,
            notes: try slideNotes(at: index),
            transition: try slideTransition(at: index),
            nodes: nodes
        )
    }

    // MARK: Node construction

    private func buildNode(
        id: UInt64,
        in component: Component,
        role: String?,
        promptByRole: [String: String]
    ) throws -> SceneNode? {
        // Most drawables live in the slide's component, but some (tables)
        // are stored elsewhere and referenced across components.
        guard let record = component.records.first(where: { $0.identifier == id })
            ?? components.flatMap(\.records).first(where: { $0.identifier == id })
        else { return nil }

        switch record.primaryType {
        case 7: // KN.PlaceholderArchive
            let placeholder = try record.decode(KN_PlaceholderArchive.self)
            let shape = placeholder.super
            return SceneNode(
                id: id,
                type: "placeholder",
                role: role ?? kindName(placeholder.kind),
                prompt: (role ?? kindName(placeholder.kind)).flatMap { promptByRole[$0] },
                text: storageText(of: shape, in: component),
                frame: frame(of: shape.super.super)
            )

        case 2011: // TSWP.ShapeInfoArchive (text box / shape with text)
            let shape = try record.decode(TSWP_ShapeInfoArchive.self)
            return SceneNode(
                id: id,
                type: "shape",
                text: storageText(of: shape, in: component),
                frame: frame(of: shape.super.super)
            )

        case 3005: // TSD.ImageArchive
            let image = try record.decode(TSD_ImageArchive.self)
            var media: MediaReference?
            if image.hasData {
                media = MediaReference(
                    dataID: image.data.identifier,
                    file: fileName(forDataIdentifier: image.data.identifier)
                )
            }
            return SceneNode(
                id: id,
                type: "image",
                frame: frame(of: image.super),
                media: media
            )

        case 3007: // TSD.MovieArchive
            let movie = try record.decode(TSD_MovieArchive.self)
            var media: MediaReference?
            if movie.hasMovieData {
                media = MediaReference(
                    dataID: movie.movieData.identifier,
                    file: fileName(forDataIdentifier: movie.movieData.identifier)
                )
            }
            return SceneNode(
                id: id,
                type: "movie",
                frame: frame(of: movie.super),
                media: media
            )

        case 3008: // TSD.GroupArchive
            let group = try record.decode(TSD_GroupArchive.self)
            var children: [SceneNode] = []
            for child in group.children {
                if let childNode = try buildNode(
                    id: child.identifier, in: component, role: nil, promptByRole: promptByRole
                ) {
                    children.append(childNode)
                }
            }
            return SceneNode(
                id: id,
                type: "group",
                frame: frame(of: group.super),
                children: children
            )

        case 3009:
            return SceneNode(id: id, type: "connectionLine")

        case 6000: // TST.TableInfoArchive
            let info = try record.decode(TST_TableInfoArchive.self)
            return SceneNode(
                id: id,
                type: "table",
                frame: frame(of: info.super),
                cells: try? tableCells(id)
            )

        default:
            return SceneNode(id: id, type: "unknown-\(record.primaryType)")
        }
    }

    private func kindName(_ kind: KN_PlaceholderArchive.Kind) -> String? {
        switch kind {
        case .kKindTitlePlaceholder: return "title"
        case .kKindBodyPlaceholder: return "body"
        case .kKindObjectPlaceholder: return "object"
        case .kKindSlideNumberPlaceholder: return "slideNumber"
        case .kKindPlaceholder: return nil
        }
    }

    private func storageText(of shape: TSWP_ShapeInfoArchive, in component: Component) -> String? {
        let storageID: UInt64
        if shape.hasOwnedStorage {
            storageID = shape.ownedStorage.identifier
        } else if shape.hasTextFlow {
            storageID = shape.textFlow.identifier
        } else {
            return nil
        }
        guard let record = component.records.first(where: { $0.identifier == storageID }),
              let storage = try? record.decode(TSWP_StorageArchive.self)
        else { return nil }
        let text = storage.text.joined()
        return text.isEmpty ? nil : text
    }

    private func frame(of drawable: TSD_DrawableArchive) -> Frame? {
        guard drawable.hasGeometry else { return nil }
        let geometry = drawable.geometry
        return Frame(
            x: Double(geometry.position.x),
            y: Double(geometry.position.y),
            width: Double(geometry.size.width),
            height: Double(geometry.size.height)
        )
    }

    func fileName(forDataIdentifier identifier: UInt64) -> String? {
        guard let metadataRecord = components
            .flatMap(\.records)
            .first(where: { $0.primaryType == 11006 }),
            let metadata = try? metadataRecord.decode(TSP_PackageMetadata.self)
        else { return nil }
        let info = metadata.datas.first { $0.identifier == identifier && !$0.fileName.isEmpty }
        return info?.fileName
    }
}
