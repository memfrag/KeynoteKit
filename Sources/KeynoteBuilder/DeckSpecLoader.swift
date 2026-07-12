import CoreGraphics
import Foundation
import ImageIO
import KeynoteModel

public enum DeckSpecError: Error, CustomStringConvertible {
    case invalidColor(String)
    /// One or more validation problems, each already formatted with its path.
    case validation([String])
    case decoding(String)

    public var description: String {
        switch self {
        case .invalidColor(let s): return "invalid color \"\(s)\""
        case .decoding(let s): return "could not parse JSON: \(s)"
        case .validation(let issues):
            return "invalid deck spec:\n" + issues.map { "  • \($0)" }.joined(separator: "\n")
        }
    }
}

/// Reads a ``DeckSpec`` JSON file and writes a `.key`. Free-form slides are
/// synthesized element-by-element via the `Canvas` DSL; `use` slides instantiate
/// an in-JSON template; transitions and builds are layered on afterward.
public final class DeckSpecLoader {

    // 16:9 canvas the cover/fit/coverBox helpers lay out against.
    static let canvasWidth = 1920.0
    static let canvasHeight = 1080.0

    public static func write(specURL: URL, to outputURL: URL) throws {
        let data = try Data(contentsOf: specURL)
        let spec: DeckSpec
        do {
            spec = try JSONDecoder().decode(DeckSpec.self, from: data)
        } catch {
            throw DeckSpecError.decoding("\(error)")
        }

        let specDir = specURL.deletingLastPathComponent()
        let baseDir = spec.imageBaseDir.map {
            URL(fileURLWithPath: $0, relativeTo: specDir)
        } ?? specDir

        let loader = DeckSpecLoader(spec: spec, baseDir: baseDir, specDir: specDir)
        defer { loader.cleanupTempImages() }

        // 1. Validate the whole spec; report every problem at once.
        let issues = loader.validate()
        guard issues.isEmpty else { throw DeckSpecError.validation(issues) }

        // 2. Named paragraph styles, document-wide.
        let styles = (spec.paragraphStyles ?? []).map { loader.paragraphStyle($0) }
        let buildRequests = spec.slides.map { $0.builds ?? [] }

        // 3. Build the base document — from an external template (clone + fill)
        // or by synthesizing free-form/`use` slides onto the bundled seed.
        var document: KeynoteDocument
        if spec.template != nil {
            document = try loader.assembleTemplateDeck(styles: styles)
        } else {
            var canvases: [Canvas] = []
            for slide in spec.slides { canvases.append(try loader.canvas(for: slide).0) }
            document = try CanvasWriter().build(canvases, paragraphStyles: styles)
        }

        // 4. Per-slide: transition, notes, title, builds.
        for (index, slide) in spec.slides.enumerated() {
            if let t = slide.transition {
                try document.setSlideTransition(at: index, to: loader.transition(t))
            }
            if let notes = slide.notes {
                try document.setSlideText(at: index, .notes, to: notes)
            }
            // `title` sets the title-placeholder text (the real navigator/outline
            // title). Only slides with a title placeholder (external-template
            // slides) have one; validation blocks it on free-form slides.
            if let title = slide.title {
                try document.setSlideTitle(at: index, to: title)
            }
            if !buildRequests[index].isEmpty {
                let nodes = try document.sceneTree(forSlideAt: index).nodes
                for build in buildRequests[index] {
                    guard let node = nodes.first(where: { $0.label == build.target }) else { continue }
                    try document.addBuild(loader.build(build, nodeID: node.id), toSlideAt: index)
                }
            }
        }
        try document.write(to: outputURL)
    }

    // MARK: - State

    let spec: DeckSpec
    let baseDir: URL
    let specDir: URL
    private var tempImages: [URL] = []

    init(spec: DeckSpec, baseDir: URL, specDir: URL) {
        self.spec = spec
        self.baseDir = baseDir
        self.specDir = specDir
    }

    func cleanupTempImages() {
        for url in tempImages { try? FileManager.default.removeItem(at: url) }
        tempImages = []
    }

    // MARK: - Validation (accumulate every problem)

    func validate() -> [String] {
        var issues: [String] = []
        for (styleIndex, style) in (spec.paragraphStyles ?? []).enumerated() where style.alignment != nil {
            if (try? textAlignment(style.alignment)) == nil {
                issues.append("paragraphStyles[\(styleIndex)]: unknown alignment \"\(style.alignment!)\"")
            }
        }
        // External-template decks are validated against the template's layouts.
        let templateLibrary: TemplateLibrary? = spec.template.flatMap {
            try? TemplateLibrary(templateURL: URL(fileURLWithPath: $0, relativeTo: specDir))
        }
        if spec.template != nil, templateLibrary == nil {
            issues.append("template: cannot load template \"\(spec.template!)\"")
        }

        for (slideIndex, slide) in spec.slides.enumerated() {
            let path = "slides[\(slideIndex)]"

            // Template deck: every slide clones a layout via `from`.
            if spec.template != nil {
                if slide.elements != nil || slide.use != nil {
                    issues.append("\(path): a template deck's slides use `from` (not `elements`/`use`)")
                }
                if let from = slide.from {
                    if let library = templateLibrary, let layout = from.layout,
                       library.slideIndex(for: layout) == nil {
                        issues.append("\(path): unknown layout \"\(layout)\"; available: \(templateLibrary?.availableLayouts.joined(separator: ", ") ?? "")")
                    }
                } else {
                    issues.append("\(path): slide needs a `from` (this is a template deck)")
                }
                if let transition = slide.transition, let d = transition.direction, direction(d) == nil {
                    issues.append("\(path).transition: unknown direction \"\(d)\"")
                }
                continue
            }

            // Free-form / in-JSON template deck.
            if slide.from != nil { issues.append("\(path): `from` needs a deck-level `template`") }
            if slide.override != nil { issues.append("\(path): `override` requires an external-template slide") }
            if let use = slide.use, spec.templates?[use] == nil {
                issues.append("\(path): unknown template \"\(use)\"")
            }
            if slide.title != nil {
                issues.append("\(path): `title` requires an external-template slide (a layout with a title placeholder)")
            }

            var elementSpecs: [ElementSpec] = []
            if let use = slide.use, let template = spec.templates?[use] {
                elementSpecs += template.elements.map { merged($0, with: slide.set) }
            }
            elementSpecs += slide.elements ?? []
            if elementSpecs.isEmpty {
                issues.append("\(path): slide has no elements")
            }

            var names = Set<String>()
            for (elementIndex, element) in elementSpecs.enumerated() {
                let elementPath = "\(path).elements[\(elementIndex)]"
                if let name = element.name, !names.insert(name).inserted {
                    issues.append("\(elementPath): duplicate element name \"\(name)\"")
                }
                if element.frame == nil {
                    issues.append("\(elementPath): missing frame")
                }
                if element.type == "image", let ref = element.image,
                   let url = imageURLForValidation(ref), !FileManager.default.fileExists(atPath: url.path) {
                    issues.append("\(elementPath): image not found: \(ref)")
                }
                do {
                    _ = try self.element(element)
                } catch let error as DeckSpecError {
                    if case .validation(let messages) = error {
                        issues.append(contentsOf: messages.map { "\(elementPath): \($0)" })
                    } else {
                        issues.append("\(elementPath): \(error)")
                    }
                } catch {
                    issues.append("\(elementPath): \(error)")
                }
            }

            for (buildIndex, build) in (slide.builds ?? []).enumerated() where !names.contains(build.target) {
                issues.append("\(path).builds[\(buildIndex)]: target \"\(build.target)\" is not a named element on this slide")
            }
            if let transition = slide.transition, let d = transition.direction, direction(d) == nil {
                issues.append("\(path).transition: unknown direction \"\(d)\"")
            }
        }
        return issues
    }

    // MARK: - Slide → Canvas

    /// Resolves a slide to a `Canvas` and its ordered build requests. `use`
    /// slides merge their template's named elements with per-name `set` values.
    func canvas(for slide: SlideSpec) throws -> (Canvas, [BuildSpec]) {
        var elementSpecs: [ElementSpec] = []
        if let use = slide.use, let template = spec.templates?[use] {
            elementSpecs += template.elements.map { merged($0, with: slide.set) }
        }
        elementSpecs += slide.elements ?? []

        let elements = try elementSpecs.map { try element($0) }
        var canvas = Canvas(elements: elements)
        if let bg = slide.background { canvas = canvas.background(try fill(bg)) }
        return (canvas, slide.builds ?? [])
    }

    /// Applies `set` overrides (by element name) to a template element.
    private func merged(_ element: ElementSpec, with set: [String: SetValue]?) -> ElementSpec {
        guard let name = element.name, let value = set?[name] else { return element }
        var copy = element
        if let text = value.text { copy.text = text }
        if let image = value.image { copy.image = image }
        return copy
    }

    // MARK: - External template (clone layout slides + fill)

    /// Builds a document by cloning layout slides from the deck's `template`
    /// `.key` (one per spec slide) and filling placeholders / named nodes.
    func assembleTemplateDeck(styles: [ParagraphStyle]) throws -> KeynoteDocument {
        let templateURL = URL(fileURLWithPath: spec.template!, relativeTo: specDir)
        var document = try KeynoteDocument(contentsOf: templateURL)
        for style in styles { _ = try document.defineParagraphStyle(style) }

        let library = try TemplateLibrary(document: document)
        let templateCount = document.slideCount

        // Clone the chosen layout per spec slide, moving each clone to the tail
        // so the original example slides stay at the front for removal.
        for slide in spec.slides {
            let layoutIndex = try resolveLayout(slide.from, library: library)
            try document.duplicateSlide(at: layoutIndex)
            try document.moveSlide(from: layoutIndex + 1, to: document.slideCount - 1)
        }
        for _ in 0..<templateCount { try document.removeSlide(at: 0) }

        for (index, slide) in spec.slides.enumerated() {
            try fillTemplateSlide(slide, at: index, in: &document)
        }
        return document
    }

    private func resolveLayout(_ from: FromSpec?, library: TemplateLibrary) throws -> Int {
        guard let from else { throw DeckSpecError.validation(["template slide needs a `from`"]) }
        if let layout = from.layout {
            guard let index = library.slideIndex(for: layout) else {
                throw DeckSpecError.validation([
                    "unknown layout \"\(layout)\"; available: \(library.availableLayouts.joined(separator: ", "))"])
            }
            return index
        }
        return from.slideIndex ?? 0
    }

    private func fillTemplateSlide(_ slide: SlideSpec, at index: Int, in document: inout KeynoteDocument) throws {
        for (key, value) in slide.set ?? [:] {
            if let text = value.text {
                switch key {
                case "title": try document.setSlideText(at: index, .title, to: text)
                case "body": try document.setSlideText(at: index, .body, to: text)
                default: try document.setSlideText(at: index, block: key, to: text)
                }
            }
            if let imageRef = value.image {
                try document.setSlideImage(at: index, matching: key, to: try Data(contentsOf: resolveImageURL(imageRef)))
            }
        }
        for over in slide.override ?? [] {
            let nodes = try document.sceneTree(forSlideAt: index).nodes
            guard let node = nodes.first(where: { $0.label == over.target }) else { continue }
            if let text = over.text { try document.setNodeText(node.id, to: text) }
            if let imageRef = over.image {
                try document.setNodeMedia(node.id, to: try Data(contentsOf: resolveImageURL(imageRef)))
            }
            if let frame = over.frame { try document.setNodeFrame(node.id, to: try explicitFrame(frame)) }
            if over.fill != nil || over.border != nil || over.shadow != nil || over.opacity != nil {
                try document.setNodeStyle(
                    node.id,
                    fill: try over.fill.map(fill),
                    border: try over.border.map(border),
                    shadow: over.shadow.map(shadow),
                    opacity: over.opacity)
            }
        }
    }

    private func explicitFrame(_ spec: FrameSpec) throws -> Frame {
        guard case .explicit(let frame) = spec.layout else {
            throw DeckSpecError.validation(["override frame must be explicit x/y/width/height"])
        }
        return frame
    }

    // MARK: - ElementSpec → Element

    func element(_ spec: ElementSpec) throws -> Element {
        var element: Element
        switch spec.type {
        case "text":
            element = Text(spec.text ?? "")
        case "image":
            let url = try resolveImageURL(spec.image ?? "")
            element = Image(path: url.path)
        case "shape":
            element = Shape(try shapeKind(spec.shape))
        case "group":
            element = Group(try (spec.children ?? []).map { try self.element($0) })
        default:
            throw DeckSpecError.validation(["unknown element type \"\(spec.type)\""])
        }

        if let f = spec.frame { element = element.frame(try resolveFrame(f, for: spec)) }

        // Font: element font, else the deck default (text elements only).
        if spec.type == "text" {
            if let font = spec.font ?? spec.defaultFontApplies(deck: self.spec) { element = element.font(font) }
        } else if let font = spec.font {
            element = element.font(font)
        }
        if let v = spec.fontSize { element = element.fontSize(v) }
        if let v = spec.bold { element = element.bold(v) }
        if let v = spec.italic { element = element.italic(v) }
        if let v = spec.underline { element = element.underline(v) }
        if let v = spec.strikethrough { element = element.strikethrough(v) }
        if let c = spec.color { element = element.foregroundColor(c.rgba) }
        if let a = spec.alignment { element = element.alignment(try textAlignment(a)) }
        if let v = spec.verticalAlignment { element = element.verticalAlignment(try verticalAlignment(v)) }
        if let f = spec.fill { element = element.fill(try fill(f)) }
        if let b = spec.border { element = element.border(try border(b)) }
        if let s = spec.shadow { element = element.shadow(shadow(s)) }
        if let v = spec.opacity { element = element.opacity(v) }
        if let v = spec.rotation { element = element.rotation(degrees: v) }
        if let v = spec.startCap { element = element.startCap(try lineEnd(v)) }
        if let v = spec.endCap { element = element.endCap(try lineEnd(v)) }
        if let m = spec.mask { element = element.mask(try shapeKind(m)) }
        if let v = spec.paragraphStyle { element = element.paragraphStyle(v) }
        if let n = spec.columns { element = element.columns(n, gap: spec.columnGap ?? 20) }
        if let v = spec.textInset { element = element.textInset(v) }
        if let b = spec.bulleted { element = element.bulleted(b.marker ?? "\u{2022}", color: b.color?.rgba) }
        if let n = spec.numbered { element = element.numbered(try numberFormat(n.format), color: n.color?.rgba) }
        if let d = spec.dropCap { element = element.dropCap(lines: d.lines ?? 3, characters: d.characters ?? 1) }
        if let v = spec.locked { element = element.locked(v) }
        if spec.flippedHorizontally == true { element = element.flippedHorizontally() }
        if spec.flippedVertically == true { element = element.flippedVertically() }
        if let v = spec.name { element = element.name(v) }
        return element
    }

    // MARK: - Frames

    func resolveFrame(_ spec: FrameSpec, for element: ElementSpec) throws -> Frame {
        switch spec.layout {
        case .explicit(let frame): return frame
        case .cover:
            return Self.coverBox(try aspect(for: element), Frame(x: 0, y: 0, width: Self.canvasWidth, height: Self.canvasHeight))
        case .fit(let box):
            return Self.fit(try aspect(for: element), in: box)
        case .coverBox(let box):
            return Self.coverBox(try aspect(for: element), box)
        }
    }

    private func aspect(for element: ElementSpec) throws -> Double {
        if let a = element.aspect { return a }
        guard element.type == "image", let ref = element.image else {
            throw DeckSpecError.validation(["cover/fit/coverBox frame requires an image element or an explicit aspect"])
        }
        return try imageAspect(try resolveImageURL(ref))
    }

    static func coverBox(_ aspect: Double, _ box: Frame) -> Frame {
        var w = box.width
        var h = w / aspect
        if h < box.height { h = box.height; w = h * aspect }
        return Frame(x: box.x + (box.width - w) / 2, y: box.y + (box.height - h) / 2, width: w, height: h)
    }

    static func fit(_ aspect: Double, in box: Frame) -> Frame {
        var w = box.width, h = box.height
        if aspect > box.width / box.height { h = w / aspect } else { w = h * aspect }
        return Frame(x: box.x + (box.width - w) / 2, y: box.y + (box.height - h) / 2, width: w, height: h)
    }

    // MARK: - Images (path or base64/data:)

    /// Resolves an image reference to an absolute file URL, writing a temp file
    /// for a base64/`data:` blob.
    func resolveImageURL(_ ref: String) throws -> URL {
        if ref.hasPrefix("data:") || Self.looksLikeBase64(ref) {
            let base64 = ref.hasPrefix("data:") ? String(ref.drop(while: { $0 != "," }).dropFirst()) : ref
            guard let data = Data(base64Encoded: base64) else {
                throw DeckSpecError.validation(["invalid base64 image data"])
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("deckspec-\(tempImages.count)-\(data.count).img")
            try data.write(to: url)
            tempImages.append(url)
            return url
        }
        return URL(fileURLWithPath: ref, relativeTo: baseDir).standardizedFileURL
    }

    /// Non-mutating variant for validation (does not persist temp files).
    func imageURLForValidation(_ ref: String) -> URL? {
        if ref.hasPrefix("data:") || Self.looksLikeBase64(ref) { return nil }
        return URL(fileURLWithPath: ref, relativeTo: baseDir).standardizedFileURL
    }

    private static func looksLikeBase64(_ s: String) -> Bool {
        s.count > 256 && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=" }
    }

    func imageAspect(_ url: URL) throws -> Double {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Double,
              let h = props[kCGImagePropertyPixelHeight] as? Double, h > 0
        else { throw DeckSpecError.validation(["cannot read image dimensions: \(url.lastPathComponent)"]) }
        return w / h
    }

    // MARK: - Fills / shapes / borders / shadows

    func fill(_ spec: FillSpec) throws -> Fill {
        switch spec.type ?? "color" {
        case "none": return .none
        case "color":
            guard let c = spec.color else { throw DeckSpecError.validation(["color fill needs a color"]) }
            return .color(c.r, c.g, c.b, c.a)
        case "linearGradient":
            return .linearGradient(stops: gradientStops(spec.stops), angleDegrees: spec.angleDegrees ?? 90)
        case "radialGradient":
            return .radialGradient(stops: gradientStops(spec.stops))
        case "image":
            let url = try resolveImageURL(spec.image ?? "")
            let data = try Data(contentsOf: url)
            return .image(data, mode: try imageFillMode(spec.mode), tint: spec.tint?.tuple)
        default:
            throw DeckSpecError.validation(["unknown fill type \"\(spec.type ?? "")\""])
        }
    }

    private func gradientStops(_ specs: [GradientStopSpec]?) -> [GradientStop] {
        (specs ?? []).map { GradientStop(color: $0.color.tuple, location: $0.location) }
    }

    func shapeKind(_ spec: ShapeSpec?) throws -> ShapeKind {
        guard let spec else { return .rectangle }
        switch spec.kind {
        case "rectangle": return .rectangle
        case "roundedRectangle": return .roundedRectangle(cornerRadius: spec.cornerRadius ?? 0)
        case "ellipse": return .ellipse
        case "line": return .line
        case "regularPolygon": return .regularPolygon(sides: spec.sides ?? 5)
        case "star": return .star(points: spec.points ?? 5, innerRatio: spec.innerRatio ?? 0.5)
        case "path": return .path(bezierPath(spec.segments))
        case "native": return .native(try parametricShape(spec.native))
        default: throw DeckSpecError.validation(["unknown shape kind \"\(spec.kind)\""])
        }
    }

    private func parametricShape(_ spec: ParametricShapeSpec?) throws -> ParametricShape {
        guard let spec else { throw DeckSpecError.validation(["native shape needs a shape name"]) }
        switch spec.shape {
        case "roundedRectangle": return .roundedRectangle(cornerRadius: spec.cornerRadius ?? 0)
        case "regularPolygon": return .regularPolygon(sides: spec.sides ?? 5)
        case "star": return .star(points: spec.points ?? 5, innerRatio: spec.innerRatio ?? 0.5)
        case "chevron": return .chevron(depth: spec.depth ?? 0.5)
        case "plus": return .plus
        case "leftArrow": return .leftArrow
        case "rightArrow": return .rightArrow
        case "doubleArrow": return .doubleArrow
        default: throw DeckSpecError.validation(["unknown native shape \"\(spec.shape)\""])
        }
    }

    private func bezierPath(_ segments: [PathSegmentSpec]?) -> BezierPath {
        var path = BezierPath()
        for s in segments ?? [] {
            switch s.op {
            case "move": path = path.move(to: s.x ?? 0, s.y ?? 0)
            case "line": path = path.line(to: s.x ?? 0, s.y ?? 0)
            case "quadCurve": path = path.quadCurve(to: s.x ?? 0, s.y ?? 0, control: (s.cx ?? 0, s.cy ?? 0))
            case "curve": path = path.curve(to: s.x ?? 0, s.y ?? 0, control1: (s.c1x ?? 0, s.c1y ?? 0), control2: (s.c2x ?? 0, s.c2y ?? 0))
            case "close": path = path.close()
            default: break
            }
        }
        return path
    }

    func border(_ spec: BorderSpec) throws -> Border {
        let color = spec.color?.tuple ?? (0, 0, 0, 1)
        if let style = spec.style {
            switch style {
            case "dashed": return .dashed(color: color, width: spec.width ?? 1)
            case "dotted": return .dotted(color: color, width: spec.width ?? 1)
            default: throw DeckSpecError.validation(["unknown border style \"\(style)\""])
            }
        }
        return Border(color: color, width: spec.width ?? 1, dash: spec.dash ?? [], roundCap: spec.roundCap ?? false)
    }

    func shadow(_ spec: ShadowSpec) -> Shadow {
        Shadow(color: spec.color?.tuple ?? (0, 0, 0, 1), offset: spec.offset ?? 5,
               blur: spec.blur ?? 6, angleDegrees: spec.angleDegrees ?? 315, opacity: spec.opacity ?? 0.5)
    }

    // MARK: - Paragraph styles / transitions / builds

    func paragraphStyle(_ s: ParagraphStyleSpec) -> ParagraphStyle {
        ParagraphStyle(
            name: s.name, font: s.font, fontSize: s.fontSize, bold: s.bold, italic: s.italic,
            color: s.color?.tuple, alignment: try? textAlignment(s.alignment),
            spaceBefore: s.spaceBefore, spaceAfter: s.spaceAfter,
            firstLineIndent: s.firstLineIndent, leftIndent: s.leftIndent, rightIndent: s.rightIndent,
            lineSpacing: s.lineSpacing, background: s.background?.tuple,
            tabs: s.tabs?.map { TabStop(position: $0.position, alignment: (try? tabAlignment($0.alignment)) ?? .left, leader: $0.leader) })
    }

    func transition(_ s: TransitionSpec) -> SlideTransition {
        SlideTransition(
            effect: s.effect, duration: s.duration ?? 0.4, delay: s.delay ?? 0.5,
            direction: direction(s.direction), isAutomatic: s.isAutomatic ?? false,
            color: s.color, textDelivery: s.textDelivery, twist: s.twist, mosaicSize: s.mosaicSize,
            bounce: s.bounce, motionBlur: s.motionBlur, travelDistance: s.travelDistance)
    }

    func build(_ s: BuildSpec, nodeID: UInt64) -> SlideBuild {
        SlideBuild(
            nodeID: nodeID, kind: s.kind ?? "In", effect: s.effect,
            duration: s.duration ?? 0.3, delay: s.delay ?? 0,
            delivery: s.delivery, textDelivery: s.textDelivery, deliveryOption: s.deliveryOption,
            direction: direction(s.direction), travelDistance: s.travelDistance,
            rotationAngle: s.rotationAngle, scaleSize: s.scaleSize, opacity: s.opacity)
    }

    // MARK: - Enum-from-string

    func direction(_ name: String?) -> UInt32? {
        switch name {
        case "fromLeft": return PushDirection.fromLeft.rawValue
        case "fromRight": return PushDirection.fromRight.rawValue
        case "fromTop": return PushDirection.fromTop.rawValue
        case "fromBottom": return PushDirection.fromBottom.rawValue
        case .some(let s): return UInt32(s)   // numeric fallback
        case .none: return nil
        }
    }

    func textAlignment(_ name: String?) throws -> TextAlignment {
        switch name {
        case "left": return .left
        case "right": return .right
        case "center": return .center
        case "justified": return .justified
        case "natural", nil: return .natural
        default: throw DeckSpecError.validation(["unknown alignment \"\(name!)\""])
        }
    }

    func verticalAlignment(_ name: String) throws -> VerticalAlignment {
        switch name {
        case "top": return .top
        case "middle": return .middle
        case "bottom": return .bottom
        case "justified": return .justified
        default: throw DeckSpecError.validation(["unknown vertical alignment \"\(name)\""])
        }
    }

    func lineEnd(_ name: String) throws -> LineEnd {
        switch name {
        case "none": return .none
        case "arrow": return .arrow
        case "filledArrow": return .filledArrow
        case "openArrow": return .openArrow
        case "invertedArrow": return .invertedArrow
        case "filledCircle": return .filledCircle
        case "openCircle": return .openCircle
        case "diamond": return .diamond
        case "filledSquare": return .filledSquare
        case "openSquare": return .openSquare
        case "bar": return .bar
        default: throw DeckSpecError.validation(["unknown line end \"\(name)\""])
        }
    }

    func numberFormat(_ name: String?) throws -> NumberFormat {
        switch name {
        case "decimal", nil: return .decimal
        case "decimalParen": return .decimalParen
        case "romanUpper": return .romanUpper
        case "romanLower": return .romanLower
        case "alphaUpper": return .alphaUpper
        case "alphaLower": return .alphaLower
        default: throw DeckSpecError.validation(["unknown number format \"\(name!)\""])
        }
    }

    func imageFillMode(_ name: String?) throws -> ImageFillMode {
        switch name {
        case "original": return .original
        case "stretch": return .stretch
        case "tile": return .tile
        case "scaleToFill", nil: return .scaleToFill
        case "scaleToFit": return .scaleToFit
        default: throw DeckSpecError.validation(["unknown image fill mode \"\(name!)\""])
        }
    }

    func tabAlignment(_ name: String?) throws -> TabStop.Alignment {
        switch name {
        case "left", nil: return .left
        case "center": return .center
        case "right": return .right
        case "decimal": return .decimal
        default: throw DeckSpecError.validation(["unknown tab alignment \"\(name!)\""])
        }
    }
}

private extension ElementSpec {
    /// The deck default font, when this text element sets neither `font` nor a
    /// paragraph style (which would carry its own font).
    func defaultFontApplies(deck: DeckSpec) -> String? {
        guard font == nil, paragraphStyle == nil else { return nil }
        return deck.defaultFont
    }
}
