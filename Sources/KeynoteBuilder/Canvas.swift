import Foundation
import KeynoteModel

/// A color with components in 0…1.
public struct RGBAColor: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
    public static func rgb(_ r: Double, _ g: Double, _ b: Double) -> RGBAColor {
        RGBAColor(red: r, green: g, blue: b)
    }
}

/// Geometry and style a canvas element carries. Modifiers accumulate here;
/// the renderer applies the ones relevant to each element kind.
public struct ElementStyle: Sendable {
    public var frame: Frame?
    public var fontSize: Double?
    public var bold: Bool?
    public var italic: Bool?
    public var foregroundColor: RGBAColor?
    public var fill: Fill?
    public var border: Border?
    public var shadow: Shadow?
    public var opacity: Double?
    public var rotationDegrees: Double?
    public var startCap: LineEnd?
    public var endCap: LineEnd?
    public var locked: Bool?
    public var flipHorizontal: Bool?
    public var flipVertical: Bool?
    public var mask: ShapeKind?
    public var paragraphStyleName: String?
    public var columns: Int?
    public var columnGap: Double?
    public var textInset: Double?
    public var bulletMarker: String?

    public init() {}
}

/// One element in a ``Canvas`` — text, an image, or a shape. Realized by
/// cloning a prototype from the bundled palette and applying the element's
/// content and modifiers, so it inherits valid Keynote structure and styling
/// before your overrides.
public struct Element: Sendable {
    public enum Kind: Sendable {
        case text(String)
        case image(path: String)
        case shape(ShapeKind)
        case group([Element])
    }

    public var kind: Kind
    public var style: ElementStyle

    init(_ kind: Kind, style: ElementStyle = ElementStyle()) {
        self.kind = kind
        self.style = style
    }

    // MARK: Modifiers (SwiftUI-style, chainable)

    /// Positions and sizes the element (slide points; origin top-left).
    public func frame(x: Double, y: Double, width: Double, height: Double) -> Element {
        modifying { $0.frame = Frame(x: x, y: y, width: width, height: height) }
    }

    /// Moves the element, keeping its current (or the prototype's) size.
    public func position(x: Double, y: Double) -> Element {
        modifying {
            let size = $0.frame
            $0.frame = Frame(x: x, y: y, width: size?.width ?? 0, height: size?.height ?? 0)
        }
    }

    public func fontSize(_ size: Double) -> Element { modifying { $0.fontSize = size } }
    public func bold(_ on: Bool = true) -> Element { modifying { $0.bold = on } }
    public func italic(_ on: Bool = true) -> Element { modifying { $0.italic = on } }
    public func foregroundColor(_ color: RGBAColor) -> Element { modifying { $0.foregroundColor = color } }
    /// Fill color, for shape elements.
    public func fill(_ color: RGBAColor) -> Element {
        modifying { $0.fill = .color(color.red, color.green, color.blue, color.alpha) }
    }
    /// Fill for shape elements — a color, gradient, image, or `.none`.
    public func fill(_ fill: Fill) -> Element { modifying { $0.fill = fill } }
    /// A border, for shapes, text boxes, and images. `dash` gives dash/gap
    /// lengths in width-multiples (empty = solid).
    public func border(_ color: RGBAColor, width: Double = 1, dash: [Double] = []) -> Element {
        modifying {
            $0.border = Border(color: (color.red, color.green, color.blue, color.alpha), width: width, dash: dash)
        }
    }
    /// A border, for shapes, text boxes, and images.
    public func border(_ border: Border) -> Element { modifying { $0.border = border } }
    /// A drop shadow, for shapes, text boxes, and images. Every parameter has
    /// a sensible default, so `.shadow()` gives a soft black shadow and any
    /// one can be tuned: `.shadow(color: .black, blur: 12, opacity: 0.6)`.
    public func shadow(
        color: RGBAColor = .black,
        offset: Double = 5,
        blur: Double = 6,
        angleDegrees: Double = 315,
        opacity: Double = 0.5
    ) -> Element {
        modifying {
            $0.shadow = Shadow(
                color: (color.red, color.green, color.blue, color.alpha),
                offset: offset, blur: blur, angleDegrees: angleDegrees, opacity: opacity
            )
        }
    }
    /// A drop shadow from a pre-built ``Shadow`` value.
    public func shadow(_ shadow: Shadow) -> Element { modifying { $0.shadow = shadow } }
    /// Element opacity, 0…1.
    public func opacity(_ opacity: Double) -> Element { modifying { $0.opacity = opacity } }
    /// Rotation in degrees; positive rotates counterclockwise.
    public func rotation(degrees: Double) -> Element { modifying { $0.rotationDegrees = degrees } }
    /// A decoration on the line's start end (for `Shape(.line)`).
    public func startCap(_ cap: LineEnd) -> Element { modifying { $0.startCap = cap } }
    /// A decoration on the line's finish end (for `Shape(.line)`).
    public func endCap(_ cap: LineEnd) -> Element { modifying { $0.endCap = cap } }
    /// Locks the element so it can't be selected or edited in Keynote.
    public func locked(_ on: Bool = true) -> Element { modifying { $0.locked = on } }
    /// Flips the element horizontally (mirror left↔right).
    public func flippedHorizontally(_ on: Bool = true) -> Element { modifying { $0.flipHorizontal = on } }
    /// Flips the element vertically (mirror top↔bottom).
    public func flippedVertically(_ on: Bool = true) -> Element { modifying { $0.flipVertical = on } }
    /// Masks (clips) an image element to a shape — the image shows only
    /// through the shape. Any ``ShapeKind`` works.
    public func mask(_ kind: ShapeKind) -> Element { modifying { $0.mask = kind } }
    /// Applies a named ``ParagraphStyle`` (registered on the writer) to a text
    /// element.
    public func paragraphStyle(_ name: String) -> Element { modifying { $0.paragraphStyleName = name } }
    /// Lays a text element out in equal columns.
    public func columns(_ count: Int, gap: Double = 20) -> Element {
        modifying { $0.columns = count; $0.columnGap = gap }
    }
    /// Sets a text element's inset (padding between text and box edge).
    public func textInset(_ inset: Double) -> Element { modifying { $0.textInset = inset } }
    /// Turns a text element's paragraphs into a bulleted list.
    public func bulleted(_ marker: String = "\u{2022}") -> Element { modifying { $0.bulletMarker = marker } }

    private func modifying(_ change: (inout ElementStyle) -> Void) -> Element {
        var copy = self
        change(&copy.style)
        return copy
    }
}

/// Text element.
public func Text(_ string: String) -> Element { Element(.text(string)) }
/// Image element (file path resolved against the writer's `imageBaseURL`).
public func Image(path: String) -> Element { Element(.image(path: path)) }
/// A shape element — a rectangle by default, or any ``ShapeKind`` (ellipse,
/// rounded rectangle, polygon, star).
public func Shape(_ kind: ShapeKind = .rectangle) -> Element { Element(.shape(kind)) }
/// A group of elements, positioned by their own frames and grouped into one.
/// Groups can nest. The group's own frame is its members' bounding box.
public func Group(@ElementBuilder _ content: () -> [Element]) -> Element {
    Element(.group(content()))
}

/// A free-form slide built from absolutely-positioned elements, rather than
/// from a template layout's placeholders.
public struct Canvas: Sendable {
    public var elements: [Element]
    /// Slide background fill — a color, gradient, image, or `.none`. `nil`
    /// keeps the theme's background.
    public var background: Fill?

    public init(elements: [Element]) { self.elements = elements }
    public init(@ElementBuilder _ content: () -> [Element]) { self.elements = content() }

    /// Sets the slide background — a color, gradient, image, or `.none`.
    /// Chainable, SwiftUI-style: `Canvas { … }.background(.color(…))`.
    public func background(_ fill: Fill) -> Canvas {
        var copy = self
        copy.background = fill
        return copy
    }
}

@resultBuilder
public enum ElementBuilder {
    public static func buildExpression(_ element: Element) -> [Element] { [element] }
    public static func buildExpression(_ elements: [Element]) -> [Element] { elements }
    public static func buildBlock(_ groups: [Element]...) -> [Element] { groups.flatMap { $0 } }
    public static func buildArray(_ groups: [[Element]]) -> [Element] { groups.flatMap { $0 } }
    public static func buildOptional(_ elements: [Element]?) -> [Element] { elements ?? [] }
    public static func buildEither(first elements: [Element]) -> [Element] { elements }
    public static func buildEither(second elements: [Element]) -> [Element] { elements }
}
