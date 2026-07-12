import Foundation
import KeynoteModel

public enum KeynoteWriterError: Error {
    case seedResourceMissing
    case emptyPresentation
    /// A slide asked for a layout the template doesn't define. Carries the
    /// requested layout and the layouts the template offers.
    case unknownLayout(requested: String, available: [String])
}

/// Produces a `.key` file from a `Presentation` using the template strategy:
/// start from a seed document (one title+body slide), grow or shrink it to
/// the requested slide count by duplicating/removing slide 0, then set each
/// slide's title and body text.
///
/// The seed carries a real Keynote theme, master slides, and stylesheets, so
/// the output inherits genuine Keynote styling rather than anything
/// synthesized. Pass a custom `templateURL` to start from your own `.key`
/// (e.g. a branded theme) instead of the bundled seed.
public struct KeynoteWriter {
    private let templateURL: URL

    /// The layout used for content slides that don't name one, when building
    /// against a multi-layout template. If the template doesn't define this
    /// layout, the template's first slide is used.
    public var defaultLayout: String

    /// Optional override for which layouts are body-primary (their prominent
    /// text is the body placeholder, not the title). Normally left empty: the
    /// writer infers it per slide by comparing the title and body placeholder
    /// areas from the layout, so it adapts to any theme without configuration.
    /// Keys are matched case-insensitively against the layout name/tag.
    public var bodyPrimaryLayouts: Set<String> = []

    public init(templateURL: URL? = nil, defaultLayout: String = "bullets") throws {
        if let templateURL {
            self.templateURL = templateURL
        } else {
            guard let bundled = Bundle.module.url(forResource: "seed", withExtension: "key") else {
                throw KeynoteWriterError.seedResourceMissing
            }
            self.templateURL = bundled
        }
        self.defaultLayout = defaultLayout
    }

    /// Builds `presentation` and writes the resulting `.key` to `url`.
    /// Relative image paths resolve against `imageBaseURL` (e.g. the
    /// markdown file's directory).
    public func write(_ presentation: Presentation, to url: URL, imageBaseURL: URL? = nil) throws {
        let document = try build(presentation, imageBaseURL: imageBaseURL)
        try document.write(to: url)
    }

    /// Builds `presentation` into a `KeynoteDocument` for further mutation
    /// (e.g. image replacement) before writing.
    public func build(_ presentation: Presentation, imageBaseURL: URL? = nil) throws -> KeynoteDocument {
        guard !presentation.slides.isEmpty else {
            throw KeynoteWriterError.emptyPresentation
        }
        var document = try KeynoteDocument(contentsOf: templateURL)
        let library = try TemplateLibrary(document: document)

        if library.declaresLayouts {
            try buildFromLayouts(presentation, into: &document, library: library)
        } else {
            try buildFromSingleSeed(presentation, into: &document)
        }
        try placeImages(presentation, into: &document, baseURL: imageBaseURL)
        // `@label` comments are authoring scaffolding — never ship them.
        try document.stripLabelComments()
        return document
    }

    /// Places each slide's image references into its image nodes, largest
    /// frame first (a Photo layout's full-bleed picture before any small
    /// inline image). Slides without image nodes leave their references
    /// unplaced — choose a layout that shows a picture.
    private func placeImages(
        _ presentation: Presentation,
        into document: inout KeynoteDocument,
        baseURL: URL?
    ) throws {
        for (index, slide) in presentation.slides.enumerated() where !slide.imagePaths.isEmpty {
            let tree = try document.sceneTree(forSlideAt: index)
            let imageNodes = tree.nodes
                .filter { $0.type == "image" }
                .sorted {
                    let a = ($0.frame?.width ?? 0) * ($0.frame?.height ?? 0)
                    let b = ($1.frame?.width ?? 0) * ($1.frame?.height ?? 0)
                    return a > b
                }
            for (path, node) in zip(slide.imagePaths, imageNodes) {
                let url = URL(fileURLWithPath: path, relativeTo: baseURL)
                try document.setNodeMedia(node.id, to: try Data(contentsOf: url))
            }
        }

        // Label-addressed images (by the image's description).
        for (index, slide) in presentation.slides.enumerated() {
            for (label, path) in slide.images {
                let url = URL(fileURLWithPath: path, relativeTo: baseURL)
                try document.setSlideImage(at: index, matching: label, to: try Data(contentsOf: url))
            }
        }
    }

    /// Multi-layout template: clone the matching example slide per content
    /// item to the tail, fill it, then drop the original example slides.
    private func buildFromLayouts(
        _ presentation: Presentation,
        into document: inout KeynoteDocument,
        library: TemplateLibrary
    ) throws {
        let templateCount = document.slideCount

        for (contentIndex, slide) in presentation.slides.enumerated() {
            let requested = slide.layout ?? defaultLayout
            let templateIndex = library.slideIndex(for: requested)
                ?? (slide.layout == nil ? 0 : nil)
            guard let templateIndex else {
                throw KeynoteWriterError.unknownLayout(
                    requested: requested, available: library.availableLayouts
                )
            }

            // Cloning inserts right after the source; move the clone to the
            // end so the example slides stay put at indices [0, templateCount)
            // and content accumulates at the tail in order.
            try document.duplicateSlide(at: templateIndex)
            try document.moveSlide(from: templateIndex + 1, to: document.slideCount - 1)
            let index = templateCount + contentIndex
            let forceBody = bodyPrimaryLayouts.contains(TemplateLibrary.normalize(requested))
            try fill(slide, at: index, forceBodyPrimary: forceBody, in: &document)
        }

        // Remove the original example slides (now at the front).
        for _ in 0..<templateCount {
            try document.removeSlide(at: 0)
        }
    }

    /// Single-slide seed: grow/shrink by cloning/removing slide 0.
    private func buildFromSingleSeed(
        _ presentation: Presentation,
        into document: inout KeynoteDocument
    ) throws {
        let target = presentation.slides.count
        var current = document.slideCount
        while current < target { try document.duplicateSlide(at: 0); current += 1 }
        while current > target { try document.removeSlide(at: current - 1); current -= 1 }

        for (index, slide) in presentation.slides.enumerated() {
            try fill(slide, at: index, forceBodyPrimary: false, in: &document)
        }
    }

    /// Whether a layout's prominent text placeholder is the body rather than
    /// the title — inferred by comparing their areas, so it adapts to any
    /// theme. (Statement, Quote, Big Fact are body-primary; Title, Section,
    /// Title & Bullets are title-primary.) Used only to place single-text
    /// content; when a slide has both a title and a body they map directly.
    private func isBodyPrimary(at index: Int, in document: KeynoteDocument) -> Bool {
        guard let fields = try? document.layoutDescription(at: index).fields else { return false }
        func area(_ role: String) -> Double {
            guard let frame = fields.first(where: { $0.role == role })?.frame else { return 0 }
            return frame.width * frame.height
        }
        let bodyArea = area("body")
        return bodyArea > 0 && bodyArea > area("title")
    }

    private func fill(
        _ slide: Slide,
        at index: Int,
        forceBodyPrimary: Bool,
        in document: inout KeynoteDocument
    ) throws {
        switch (slide.title, slide.body) {
        case let (title?, body?):
            // Both given: map directly, regardless of layout.
            try document.setSlideText(at: index, .title, to: title)
            try document.setSlideText(at: index, .body, to: body)
        case let (single?, nil), let (nil, single?):
            // One text block: put it in the layout's prominent placeholder.
            let bodyPrimary = forceBodyPrimary || isBodyPrimary(at: index, in: document)
            try document.setSlideText(at: index, bodyPrimary ? .body : .title, to: single)
        case (nil, nil):
            break
        }
        // Extra text blocks (two-column bullets, subtitles, attributions…),
        // addressed by role / label / prompt. Applied after title/body so a
        // block can also override them if the caller prefers.
        for (key, value) in slide.blocks {
            try document.setSlideText(at: index, block: key, to: value)
        }

        // Presenter notes: overwrite whatever the template slide carried
        // (which includes its `@layout:` tag) with the content's notes, or
        // clear the tag if the content has none. Tolerate slides whose layout
        // has no notes placeholder.
        do {
            try document.setSlideText(at: index, .notes, to: slide.notes ?? "")
        } catch SlideContentError.noPlaceholder {
            // no notes storage on this slide; nothing to strip
        }
    }
}
