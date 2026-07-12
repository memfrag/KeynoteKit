import Foundation
import KeynoteModel

/// Declarative, `Codable` representation of a deck — the JSON `build-json`
/// reads. These DTOs mirror the `Canvas` DSL but are decoupled from it so the
/// format can be authored by hand or by an LLM. `DeckSpecLoader` translates a
/// `DeckSpec` into a `KeynoteDocument`.
///
/// Enum-like fields are kept as `String` (not `RawRepresentable` enums) so that
/// unknown values surface in the loader's accumulating validation pass rather
/// than aborting `JSONDecoder` at the first bad value.
public struct DeckSpec: Decodable {
    public var name: String?
    /// External template `.key` (relative to the spec) used as the base
    /// document; its layout slides can be cloned by `SlideSpec.from`.
    public var template: String?
    /// Directory (relative to the spec) that image paths resolve against.
    public var imageBaseDir: String?
    /// Font applied to all text unless an element or paragraph style overrides it.
    public var defaultFont: String?
    public var paragraphStyles: [ParagraphStyleSpec]?
    /// Reusable in-JSON slide templates, addressed by `SlideSpec.use`.
    public var templates: [String: TemplateSpec]?
    public var slides: [SlideSpec]

    private enum CodingKeys: String, CodingKey {
        case name, template, imageBaseDir, defaultFont, paragraphStyles, templates, slides
        // `$schema` is allowed but ignored.
    }
}

/// A reusable in-JSON template: a set of named elements instances fill by name.
public struct TemplateSpec: Decodable {
    public var elements: [ElementSpec]
}

public struct SlideSpec: Decodable {
    public var background: FillSpec?
    public var transition: TransitionSpec?

    // Slide kind (mutually exclusive base; `use`/`from` may also carry `elements`).
    public var elements: [ElementSpec]?      // free-form
    public var use: String?                  // in-JSON template instance
    public var from: FromSpec?               // external-template clone

    public var set: [String: SetValue]?      // placeholder / named-element fills
    public var override: [OverrideSpec]?     // named-node overrides on a cloned slide
    public var builds: [BuildSpec]?          // ordered animations (playback order = array order)
    public var notes: String?                // presenter notes
    public var title: String?                // navigator/outline title
}

/// Selects a slide/layout in the external template deck.
public struct FromSpec: Decodable {
    public var template: String?             // defaults to the deck-level `template`
    public var layout: String?               // layout tag / master name
    public var slideIndex: Int?
}

/// An override applied to a named node on a cloned template slide.
public struct OverrideSpec: Decodable {
    public var target: String
    public var text: String?
    public var image: String?                // path or data: / base64
    public var frame: FrameSpec?
    public var fill: FillSpec?
    public var border: BorderSpec?
    public var shadow: ShadowSpec?
    public var opacity: Double?
}

/// A `set` value: a bare string (placeholder text) or `{ text?, image? }`.
public struct SetValue: Decodable {
    public var text: String?
    public var image: String?

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let string = try? single.decode(String.self) {
            self.text = string
            self.image = nil
        } else {
            let keyed = try decoder.container(keyedBy: CodingKeys.self)
            self.text = try keyed.decodeIfPresent(String.self, forKey: .text)
            self.image = try keyed.decodeIfPresent(String.self, forKey: .image)
        }
    }
    private enum CodingKeys: String, CodingKey { case text, image }
}

public struct ElementSpec: Decodable {
    public var type: String                  // text / image / shape / group

    // Content
    public var text: String?
    public var image: String?                // path or data: / base64
    public var shape: ShapeSpec?
    public var children: [ElementSpec]?

    // Geometry
    public var frame: FrameSpec?
    public var aspect: Double?               // image-aspect override for cover/fit

    // Character
    public var font: String?
    public var fontSize: Double?
    public var bold: Bool?
    public var italic: Bool?
    public var underline: Bool?
    public var strikethrough: Bool?
    /// Text (foreground) color.
    public var color: ColorSpec?
    public var alignment: String?
    public var verticalAlignment: String?

    // Paragraph / list / layout
    public var paragraphStyle: String?
    public var columns: Int?
    public var columnGap: Double?
    public var textInset: Double?
    public var bulleted: BulletSpec?
    public var numbered: NumberedSpec?
    public var dropCap: DropCapSpec?

    // Appearance
    public var fill: FillSpec?
    public var border: BorderSpec?
    public var shadow: ShadowSpec?
    public var opacity: Double?
    public var rotation: Double?
    public var startCap: String?
    public var endCap: String?
    public var mask: ShapeSpec?

    // Misc
    public var locked: Bool?
    public var flippedHorizontally: Bool?
    public var flippedVertically: Bool?
    public var name: String?
}

public struct BulletSpec: Decodable { public var marker: String?; public var color: ColorSpec? }
public struct NumberedSpec: Decodable { public var format: String?; public var color: ColorSpec? }
public struct DropCapSpec: Decodable { public var lines: Int?; public var characters: Int? }

public struct BorderSpec: Decodable {
    public var color: ColorSpec?
    public var width: Double?
    public var dash: [Double]?
    public var roundCap: Bool?
    public var style: String?                // "dashed" / "dotted" convenience
}

public struct ShadowSpec: Decodable {
    public var color: ColorSpec?
    public var offset: Double?
    public var blur: Double?
    public var angleDegrees: Double?
    public var opacity: Double?
}

public struct ParagraphStyleSpec: Decodable {
    public var name: String
    public var font: String?
    public var fontSize: Double?
    public var bold: Bool?
    public var italic: Bool?
    public var color: ColorSpec?
    public var alignment: String?
    public var spaceBefore: Double?
    public var spaceAfter: Double?
    public var firstLineIndent: Double?
    public var leftIndent: Double?
    public var rightIndent: Double?
    public var lineSpacing: Double?
    public var background: ColorSpec?
    public var tabs: [TabStopSpec]?
}

public struct TabStopSpec: Decodable {
    public var position: Double
    public var alignment: String?
    public var leader: String?
}

public struct GradientStopSpec: Decodable {
    public var color: ColorSpec
    public var location: Double
}

public struct TransitionSpec: Decodable {
    public var effect: String
    public var duration: Double?
    public var delay: Double?
    public var direction: String?
    public var isAutomatic: Bool?
    public var color: [Double]?
    public var textDelivery: String?
    public var twist: Double?
    public var mosaicSize: UInt32?
    public var bounce: Bool?
    public var motionBlur: Bool?
    public var travelDistance: Double?
}

public struct BuildSpec: Decodable {
    public var target: String                // element name
    public var kind: String?                 // In / Out / action (default In)
    public var effect: String
    public var duration: Double?
    public var delay: Double?
    public var delivery: String?
    public var textDelivery: String?
    public var deliveryOption: String?
    public var direction: String?
    public var travelDistance: Double?
    public var rotationAngle: Double?
    public var scaleSize: Double?
    public var opacity: Double?
}

/// A color: a hex string (`"#RRGGBB"` / `"#RRGGBBAA"`) or an array
/// `[r,g,b]` / `[r,g,b,a]` of 0…1 floats.
public struct ColorSpec: Decodable {
    public let r, g, b, a: Double

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let hex = try? container.decode(String.self) {
            (r, g, b, a) = try ColorSpec.parseHex(hex)
        } else {
            let comps = try container.decode([Double].self)
            guard comps.count == 3 || comps.count == 4 else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "color array must have 3 or 4 components")
            }
            r = comps[0]; g = comps[1]; b = comps[2]; a = comps.count == 4 ? comps[3] : 1
        }
    }

    public var rgba: RGBAColor { RGBAColor(red: r, green: g, blue: b, alpha: a) }
    public var tuple: (Double, Double, Double, Double) { (r, g, b, a) }

    static func parseHex(_ raw: String) throws -> (Double, Double, Double, Double) {
        var hex = raw.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let value = UInt32(hex, radix: 16) else {
            throw DeckSpecError.invalidColor(raw)
        }
        let hasAlpha = hex.count == 8
        let rr = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let gg = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let bb = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let aa = hasAlpha ? Double(value & 0xFF) / 255 : 1
        return (rr, gg, bb, aa)
    }
}

/// A fill: `{ "type": "color"|"none"|"linearGradient"|"radialGradient"|"image", … }`
/// or a bare hex string (shorthand for a color fill).
public struct FillSpec: Decodable {
    public var type: String?
    public var color: ColorSpec?
    public var stops: [GradientStopSpec]?
    public var angleDegrees: Double?
    public var image: String?                // path or data: / base64
    public var mode: String?
    public var tint: ColorSpec?

    public init(from decoder: Decoder) throws {
        // Shorthand: a bare hex string or [r,g,b(,a)] array is a color fill.
        if let color = try? ColorSpec(from: decoder) {
            self.type = "color"
            self.color = color
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try c.decodeIfPresent(String.self, forKey: .type)
        self.color = try c.decodeIfPresent(ColorSpec.self, forKey: .color)
        self.stops = try c.decodeIfPresent([GradientStopSpec].self, forKey: .stops)
        self.angleDegrees = try c.decodeIfPresent(Double.self, forKey: .angleDegrees)
        self.image = try c.decodeIfPresent(String.self, forKey: .image)
        self.mode = try c.decodeIfPresent(String.self, forKey: .mode)
        self.tint = try c.decodeIfPresent(ColorSpec.self, forKey: .tint)
    }
    private enum CodingKeys: String, CodingKey { case type, color, stops, angleDegrees, image, mode, tint }
}

/// A shape: `{ "kind": "rectangle"|"roundedRectangle"|…|"native"|"path", … }`.
public struct ShapeSpec: Decodable {
    public var kind: String
    public var cornerRadius: Double?
    public var sides: Int?
    public var points: Int?
    public var innerRatio: Double?
    public var depth: Double?
    public var segments: [PathSegmentSpec]?
    public var native: ParametricShapeSpec?
}

public struct ParametricShapeSpec: Decodable {
    public var shape: String
    public var cornerRadius: Double?
    public var sides: Int?
    public var points: Int?
    public var innerRatio: Double?
    public var depth: Double?
}

public struct PathSegmentSpec: Decodable {
    public var op: String                    // move / line / quadCurve / curve / close
    public var x: Double?
    public var y: Double?
    public var cx: Double?
    public var cy: Double?
    public var c1x: Double?
    public var c1y: Double?
    public var c2x: Double?
    public var c2y: Double?
}

/// A frame: explicit `{x,y,width,height}` or a helper `{mode:"cover"|"fit"|"coverBox", box?}`.
public struct FrameSpec: Decodable {
    public enum Layout {
        case explicit(Frame)
        case cover
        case fit(box: Frame)
        case coverBox(box: Frame)
    }
    public var layout: Layout

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let mode = try c.decodeIfPresent(String.self, forKey: .mode) {
            switch mode {
            case "cover": layout = .cover
            case "fit": layout = .fit(box: try c.decode(Frame.self, forKey: .box))
            case "coverBox": layout = .coverBox(box: try c.decode(Frame.self, forKey: .box))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .mode, in: c, debugDescription: "unknown frame mode \"\(mode)\"")
            }
        } else {
            layout = .explicit(Frame(
                x: try c.decode(Double.self, forKey: .x),
                y: try c.decode(Double.self, forKey: .y),
                width: try c.decode(Double.self, forKey: .width),
                height: try c.decode(Double.self, forKey: .height)))
        }
    }
    private enum CodingKeys: String, CodingKey { case mode, box, x, y, width, height }
}

// MARK: - Internal helpers

extension ColorSpec {
    init(hex: (Double, Double, Double, Double)) { r = hex.0; g = hex.1; b = hex.2; a = hex.3 }
}
