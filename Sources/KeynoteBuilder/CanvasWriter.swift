import Foundation
import KeynoteModel

public enum CanvasWriterError: Error {
    case paletteMissing
    case prototypeMissing(String)
    case emptyCanvas
}

/// Renders free-form ``Canvas`` slides — elements placed by absolute position
/// with a SwiftUI-like syntax — into a `.key`.
///
/// Each element is realized by cloning a prototype from a bundled palette
/// (a text box, an image, a shape), so it inherits valid Keynote structure
/// and default styling; the element's content and position are then applied.
public struct CanvasWriter {
    private let paletteURL: URL

    private static let textProto = "kk-proto-text"
    private static let shapeProto = "kk-proto-box"
    private static let imageProto = "kk-proto-image"

    public init(paletteURL: URL? = nil) throws {
        if let paletteURL {
            self.paletteURL = paletteURL
        } else {
            guard let bundled = Bundle.module.url(forResource: "palette", withExtension: "key") else {
                throw CanvasWriterError.paletteMissing
            }
            self.paletteURL = bundled
        }
    }

    public func write(
        _ canvases: [Canvas], to url: URL, imageBaseURL: URL? = nil,
        paragraphStyles: [ParagraphStyle] = []
    ) throws {
        let document = try build(canvases, imageBaseURL: imageBaseURL, paragraphStyles: paragraphStyles)
        try document.write(to: url)
    }

    public func build(
        _ canvases: [Canvas], imageBaseURL: URL? = nil, paragraphStyles: [ParagraphStyle] = []
    ) throws -> KeynoteDocument {
        guard !canvases.isEmpty else { throw CanvasWriterError.emptyCanvas }
        var document = try KeynoteDocument(contentsOf: paletteURL)

        while document.slideCount < canvases.count { try document.duplicateSlide(at: 0) }
        while document.slideCount > canvases.count { try document.removeSlide(at: document.slideCount - 1) }

        // Register named paragraph styles once, document-wide.
        var styleIDs: [String: UInt64] = [:]
        for style in paragraphStyles { styleIDs[style.name] = try document.defineParagraphStyle(style) }

        for (index, canvas) in canvases.enumerated() {
            try render(canvas, at: index, in: &document, imageBaseURL: imageBaseURL, paragraphStyles: styleIDs)
        }
        return document
    }

    private func render(
        _ canvas: Canvas, at index: Int,
        in document: inout KeynoteDocument, imageBaseURL: URL?, paragraphStyles: [String: UInt64]
    ) throws {
        // Every element is synthesized from scratch — nothing is cloned — so
        // the seed's prototypes are only removed, never used. Capture them up
        // front (they may be absent in a slimmed seed).
        func prototypeID(_ label: String) -> UInt64? {
            let nodes = (try? document.sceneTree(forSlideAt: index).nodes) ?? []
            return nodes.first(where: { $0.label == label })?.id
        }
        let leftoverProtos = [Self.textProto, Self.shapeProto, Self.imageProto].compactMap(prototypeID)

        if let background = canvas.background {
            try document.setSlideBackground(at: index, fill: background)
        }

        for element in canvas.elements {
            _ = try create(element, at: index, in: &document, imageBaseURL: imageBaseURL, paragraphStyles: paragraphStyles)
        }

        // Remove the seed's prototypes so only the composed elements remain.
        for id in leftoverProtos {
            try? document.deleteDrawable(id)
        }
    }

    /// Creates one element (recursing into groups) and returns its node id.
    private func create(
        _ element: Element, at index: Int, in document: inout KeynoteDocument, imageBaseURL: URL?,
        paragraphStyles: [String: UInt64]
    ) throws -> UInt64 {
        let frame = element.style.frame ?? Self.defaultFrame
        switch element.kind {
        case .text(let string):
            let newID = try document.addText(toSlideAt: index, string: string, frame: frame)
            try applyStyle(element.style, to: newID, in: &document)
            if let name = element.style.paragraphStyleName, let styleID = paragraphStyles[name] {
                try document.applyParagraphStyle(styleID, to: newID)
            }
            if let columns = element.style.columns {
                try document.setNodeColumns(newID, count: columns, gap: element.style.columnGap ?? 20)
            }
            if let inset = element.style.textInset {
                try document.setNodeTextInset(newID, inset)
            }
            if let marker = element.style.listMarker {
                try document.setNodeList(newID, marker)
            }
            if let lines = element.style.dropCapLines {
                try document.setNodeDropCap(newID, lines: lines, characters: element.style.dropCapCharacters ?? 1)
            }
            if let valign = element.style.verticalAlignment {
                try document.setNodeVerticalAlignment(newID, valign)
            }
            return newID
        case .shape(let kind):
            let newID = try document.addShape(toSlideAt: index, frame: frame, kind: kind)
            try applyStyle(element.style, to: newID, in: &document)
            return newID
        case .image(let path):
            let url = URL(fileURLWithPath: path, relativeTo: imageBaseURL)
            let newID = try document.addImage(toSlideAt: index, data: try Data(contentsOf: url), frame: frame)
            try applyStyle(element.style, to: newID, in: &document)
            if let mask = element.style.mask {
                try document.maskImage(newID, with: mask)
            }
            return newID
        case .group(let children):
            let ids = try children.map { try create($0, at: index, in: &document, imageBaseURL: imageBaseURL, paragraphStyles: paragraphStyles) }
            let groupID = try document.groupNodes(ids, onSlideAt: index)
            // A group's frame is its members' bounds; rotation and lock apply.
            if let rotation = element.style.rotationDegrees {
                try document.setNodeRotation(groupID, degrees: rotation)
            }
            if let locked = element.style.locked {
                try document.setNodeLocked(groupID, locked)
            }
            if element.style.flipHorizontal == true || element.style.flipVertical == true {
                try document.setNodeFlip(
                    groupID, horizontal: element.style.flipHorizontal ?? false,
                    vertical: element.style.flipVertical ?? false
                )
            }
            return groupID
        }
    }

    private static let defaultFrame = Frame(x: 0, y: 0, width: 300, height: 200)

    private func applyStyle(_ style: ElementStyle, to nodeID: UInt64, in document: inout KeynoteDocument) throws {
        if style.fontSize != nil || style.bold != nil || style.italic != nil || style.foregroundColor != nil
            || style.underline != nil || style.strikethrough != nil {
            try document.setNodeCharacterStyle(
                nodeID,
                fontSize: style.fontSize,
                bold: style.bold,
                italic: style.italic,
                color: style.foregroundColor.map { ($0.red, $0.green, $0.blue, $0.alpha) },
                underline: style.underline,
                strikethrough: style.strikethrough
            )
        }
        try document.setNodeStyle(
            nodeID, fill: style.fill, border: style.border, shadow: style.shadow,
            opacity: style.opacity, startCap: style.startCap, endCap: style.endCap
        )
        if let rotation = style.rotationDegrees {
            try document.setNodeRotation(nodeID, degrees: rotation)
        }
        if let locked = style.locked {
            try document.setNodeLocked(nodeID, locked)
        }
        if style.flipHorizontal == true || style.flipVertical == true {
            try document.setNodeFlip(
                nodeID, horizontal: style.flipHorizontal ?? false, vertical: style.flipVertical ?? false
            )
        }
        if let name = style.name {
            try document.setNodeName(nodeID, to: name)
        }
    }
}
