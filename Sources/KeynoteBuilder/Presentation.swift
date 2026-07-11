import Foundation

/// A presentation described declaratively, independent of the Keynote file
/// format. `KeynoteWriter` maps it onto a template document to produce a
/// `.key` file.
public struct Presentation {
    public var slides: [Slide]

    public init(slides: [Slide] = []) {
        self.slides = slides
    }

    public init(@SlideBuilder _ content: () -> [Slide]) {
        self.slides = content()
    }
}

/// One slide's editable content. `nil` leaves the template placeholder's
/// existing text in place; an empty string clears it.
public struct Slide {
    public var title: String?
    public var body: String?

    public init(title: String? = nil, body: String? = nil) {
        self.title = title
        self.body = body
    }
}

@resultBuilder
public enum SlideBuilder {
    public static func buildExpression(_ slide: Slide) -> [Slide] { [slide] }
    public static func buildExpression(_ slides: [Slide]) -> [Slide] { slides }
    public static func buildBlock(_ groups: [Slide]...) -> [Slide] { groups.flatMap { $0 } }
    public static func buildArray(_ groups: [[Slide]]) -> [Slide] { groups.flatMap { $0 } }
    public static func buildOptional(_ slides: [Slide]?) -> [Slide] { slides ?? [] }
    public static func buildEither(first slides: [Slide]) -> [Slide] { slides }
    public static func buildEither(second slides: [Slide]) -> [Slide] { slides }
}
