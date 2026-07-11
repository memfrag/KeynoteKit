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

    /// Layouts whose prominent text is the body placeholder rather than the
    /// title (e.g. Keynote's Statement, Quote, Big Fact — their masters put
    /// the main text in the body and keep the title as a small secondary
    /// label). For these, a slide's title and body are joined into the body
    /// placeholder. Keys are matched case-insensitively against the layout
    /// name/tag. Override to match a custom theme.
    public var bodyPrimaryLayouts: Set<String> = ["statement", "quote", "big fact"]

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
    public func write(_ presentation: Presentation, to url: URL) throws {
        let document = try build(presentation)
        try document.write(to: url)
    }

    /// Builds `presentation` into a `KeynoteDocument` for further mutation
    /// (e.g. image replacement) before writing.
    public func build(_ presentation: Presentation) throws -> KeynoteDocument {
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
        return document
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
            try fill(
                slide,
                at: templateCount + contentIndex,
                bodyPrimary: bodyPrimaryLayouts.contains(TemplateLibrary.normalize(requested)),
                in: &document
            )
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
            try fill(slide, at: index, bodyPrimary: false, in: &document)
        }
    }

    private func fill(
        _ slide: Slide,
        at index: Int,
        bodyPrimary: Bool,
        in document: inout KeynoteDocument
    ) throws {
        if bodyPrimary {
            // The layout's prominent placeholder is the body; fold the title
            // and body into it (e.g. a quote followed by its attribution).
            let text = [slide.title, slide.body].compactMap { $0 }.joined(separator: "\n")
            if !text.isEmpty {
                try document.setSlideText(at: index, .body, to: text)
            }
        } else {
            if let title = slide.title {
                try document.setSlideText(at: index, .title, to: title)
            }
            if let body = slide.body {
                try document.setSlideText(at: index, .body, to: body)
            }
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
