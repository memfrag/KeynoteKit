import Foundation
import KeynoteSchemas

/// The outline of a synthesized shape. Each kind is generated as a bezier
/// path filling the shape's frame, so it renders correctly in Keynote and
/// resizes with the frame.
public enum ShapeKind: Sendable {
    case rectangle
    /// A rectangle with rounded corners (radius in points, clamped to fit).
    case roundedRectangle(cornerRadius: Double)
    /// An ellipse filling the frame — a circle when the frame is square.
    case ellipse
    /// A regular polygon with `sides` vertices, pointing up.
    case regularPolygon(sides: Int)
    /// A star with `points` points; `innerRatio` (0…1) sets the notch depth.
    case star(points: Int, innerRatio: Double)
    /// An arbitrary bezier outline. Its bounding box maps to the element's
    /// frame, so you can draw in any coordinate space.
    case path(BezierPath)
    /// A native Keynote parametric shape. Unlike the bezier kinds above, these
    /// stay editable in Keynote's inspector (drag a star's points, a corner
    /// radius…), and include shapes with no bezier equivalent here (chevron,
    /// arrows, plus).
    case native(ParametricShape)
}

/// A shape Keynote draws from parameters, so it remains editable in the
/// inspector. Rendered by Keynote itself from the type + parameter + size.
public enum ParametricShape: Sendable {
    case roundedRectangle(cornerRadius: Double)
    case regularPolygon(sides: Int)
    case star(points: Int, innerRatio: Double)
    /// A chevron (arrow-tail) with notch `depth` (0…1).
    case chevron(depth: Double)
    case plus
    /// A single arrow pointing left.
    case leftArrow
    /// A single arrow pointing right.
    case rightArrow
    /// A double-headed arrow.
    case doubleArrow
}

/// An arbitrary 2-D outline, built from move/line/curve segments. Coordinates
/// are in your own space (the path's bounding box is scaled to fill the
/// shape's frame). The fluent methods each return a new path, so a shape can
/// be described inline:
///
/// ```swift
/// let triangle = BezierPath()
///     .move(to: 50, 0).line(to: 100, 100).line(to: 0, 100).close()
/// ```
public struct BezierPath: Sendable {
    public enum Segment: Sendable {
        case move(x: Double, y: Double)
        case line(x: Double, y: Double)
        case quadCurve(cx: Double, cy: Double, x: Double, y: Double)
        case curve(c1x: Double, c1y: Double, c2x: Double, c2y: Double, x: Double, y: Double)
        case close
    }

    public var segments: [Segment]
    public init(_ segments: [Segment] = []) { self.segments = segments }

    /// Starts a new subpath at a point.
    public func move(to x: Double, _ y: Double) -> BezierPath { adding(.move(x: x, y: y)) }
    /// Draws a straight line to a point.
    public func line(to x: Double, _ y: Double) -> BezierPath { adding(.line(x: x, y: y)) }
    /// Draws a cubic bezier curve to a point with two control points.
    public func curve(
        to x: Double, _ y: Double, control1: (Double, Double), control2: (Double, Double)
    ) -> BezierPath {
        adding(.curve(c1x: control1.0, c1y: control1.1, c2x: control2.0, c2y: control2.1, x: x, y: y))
    }
    /// Draws a quadratic bezier curve to a point with one control point.
    public func quadCurve(to x: Double, _ y: Double, control: (Double, Double)) -> BezierPath {
        adding(.quadCurve(cx: control.0, cy: control.1, x: x, y: y))
    }
    /// Closes the current subpath back to its start.
    public func close() -> BezierPath { adding(.close) }

    private func adding(_ segment: Segment) -> BezierPath {
        var copy = self
        copy.segments.append(segment)
        return copy
    }
}

extension BezierPath.Segment {
    /// Every coordinate the segment carries (endpoints and controls).
    var coordinates: [(Double, Double)] {
        switch self {
        case let .move(x, y), let .line(x, y): return [(x, y)]
        case let .quadCurve(cx, cy, x, y): return [(cx, cy), (x, y)]
        case let .curve(c1x, c1y, c2x, c2y, x, y): return [(c1x, c1y), (c2x, c2y), (x, y)]
        case .close: return []
        }
    }
}

extension BezierPath {
    /// The path's extent from the origin (at least 1×1, so the natural size is
    /// never degenerate).
    var extent: (Double, Double) {
        var maxX = 1.0, maxY = 1.0
        for segment in segments {
            for (x, y) in segment.coordinates {
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        return (maxX, maxY)
    }

    /// The path as a `TSP_Path`, with all coordinates scaled by `scaleX`/
    /// `scaleY` (used to fit the path's own space to the shape's frame).
    func tspPath(scaleX: Double = 1, scaleY: Double = 1) -> TSP_Path {
        func point(_ x: Double, _ y: Double) -> TSP_Point {
            TSP_Point.with { $0.x = Float(x * scaleX); $0.y = Float(y * scaleY) }
        }
        return TSP_Path.with {
            $0.elements = segments.map { segment in
                switch segment {
                case let .move(x, y):
                    return TSP_Path.Element.with { $0.type = .moveTo; $0.points = [point(x, y)] }
                case let .line(x, y):
                    return TSP_Path.Element.with { $0.type = .lineTo; $0.points = [point(x, y)] }
                case let .quadCurve(cx, cy, x, y):
                    return TSP_Path.Element.with { $0.type = .quadCurveTo; $0.points = [point(cx, cy), point(x, y)] }
                case let .curve(c1x, c1y, c2x, c2y, x, y):
                    return TSP_Path.Element.with {
                        $0.type = .curveTo
                        $0.points = [point(c1x, c1y), point(c2x, c2y), point(x, y)]
                    }
                case .close:
                    return TSP_Path.Element.with { $0.type = .closeSubpath }
                }
            }
        }
    }
}

extension KeynoteDocument {

    /// A path source (bezier) for a shape kind sized to `width`×`height`.
    /// Generated shapes are drawn at the frame size; a custom ``BezierPath``
    /// keeps its own coordinates and lets its bounding box scale to the frame.
    static func pathSource(for kind: ShapeKind, width w: Double, height h: Double) -> TSD_PathSourceArchive {
        let natural = TSP_Size.with { $0.width = Float(w); $0.height = Float(h) }
        if case let .native(shape) = kind {
            return parametricPathSource(shape, width: w, height: h, natural: natural)
        }
        return TSD_PathSourceArchive.with {
            $0.bezierPathSource = TSD_BezierPathSourceArchive.with {
                $0.naturalSize = natural
                $0.path = shapePath(for: kind, width: w, height: h)
            }
        }
    }

    /// A native parametric path source that Keynote regenerates on open, so
    /// the shape stays editable in the inspector.
    private static func parametricPathSource(
        _ shape: ParametricShape, width w: Double, height h: Double, natural: TSP_Size
    ) -> TSD_PathSourceArchive {
        func scalarSource(_ type: TSD_ScalarPathSourceArchive.ScalarPathSourceType, _ value: Double) -> TSD_PathSourceArchive {
            TSD_PathSourceArchive.with {
                $0.scalarPathSource = TSD_ScalarPathSourceArchive.with {
                    $0.type = type
                    $0.scalar = Float(value)
                    $0.naturalSize = natural
                }
            }
        }
        func pointSource(_ type: TSD_PointPathSourceArchive.PointPathSourceType, _ px: Double, _ py: Double) -> TSD_PathSourceArchive {
            TSD_PathSourceArchive.with {
                $0.pointPathSource = TSD_PointPathSourceArchive.with {
                    $0.type = type
                    $0.point = TSP_Point.with { $0.x = Float(px); $0.y = Float(py) }
                    $0.naturalSize = natural
                }
            }
        }
        switch shape {
        case let .roundedRectangle(cornerRadius):
            return scalarSource(.kTsdroundedRectangle, min(cornerRadius, min(w, h) / 2))
        case let .regularPolygon(sides):
            return scalarSource(.kTsdregularPolygon, Double(max(3, sides)))
        case let .chevron(depth):
            return scalarSource(.kTsdchevron, min(1, max(0, depth)))
        case let .star(points, innerRatio):
            return pointSource(.kTsdstar, Double(max(3, points)), min(max(innerRatio, 0.05), 0.95))
        case .plus:
            return pointSource(.kTsdplus, w / 3, h / 3)
        case .leftArrow:
            // point.x = arrowhead length (absolute); point.y = shaft thickness
            // (fraction of height) — verified against a Keynote-authored arrow.
            return pointSource(.kTsdleftSingleArrow, h * 0.4, 0.3)
        case .rightArrow:
            return pointSource(.kTsdrightSingleArrow, h * 0.4, 0.3)
        case .doubleArrow:
            return pointSource(.kTsddoubleArrow, h * 0.4, 0.3)
        }
    }

    /// The bezier outline for a non-native shape kind.
    static func shapePath(for kind: ShapeKind, width w: Double, height h: Double) -> TSP_Path {
        switch kind {
        case .rectangle, .native:
            return rectangleTSPPath(width: w, height: h)
        case let .roundedRectangle(cornerRadius):
            return roundedRectanglePath(width: w, height: h, radius: cornerRadius)
        case .ellipse:
            return ellipsePath(width: w, height: h)
        case let .regularPolygon(sides):
            return polygonPath(width: w, height: h, sides: max(3, sides))
        case let .star(points, innerRatio):
            return starPath(width: w, height: h, points: max(3, points),
                            innerRatio: min(max(innerRatio, 0.05), 0.95))
        case let .path(bezier):
            let (extentW, extentH) = bezier.extent
            return bezier.tspPath(scaleX: w / extentW, scaleY: h / extentH)
        }
    }

    // MARK: Path element helpers

    private static func point(_ x: Double, _ y: Double) -> TSP_Point {
        TSP_Point.with { $0.x = Float(x); $0.y = Float(y) }
    }
    private static func move(_ x: Double, _ y: Double) -> TSP_Path.Element {
        TSP_Path.Element.with { $0.type = .moveTo; $0.points = [point(x, y)] }
    }
    private static func line(_ x: Double, _ y: Double) -> TSP_Path.Element {
        TSP_Path.Element.with { $0.type = .lineTo; $0.points = [point(x, y)] }
    }
    private static func curve(
        _ c1: (Double, Double), _ c2: (Double, Double), _ end: (Double, Double)
    ) -> TSP_Path.Element {
        TSP_Path.Element.with {
            $0.type = .curveTo
            $0.points = [point(c1.0, c1.1), point(c2.0, c2.1), point(end.0, end.1)]
        }
    }
    private static var close: TSP_Path.Element {
        TSP_Path.Element.with { $0.type = .closeSubpath }
    }

    // MARK: Generators

    private static func ellipsePath(width w: Double, height h: Double) -> TSP_Path {
        let cx = w / 2, cy = h / 2, rx = w / 2, ry = h / 2
        let k = 0.5522847498307936  // 4/3·(√2−1): cubic circle approximation
        return TSP_Path.with {
            $0.elements = [
                move(cx + rx, cy),
                curve((cx + rx, cy + ry * k), (cx + rx * k, cy + ry), (cx, cy + ry)),
                curve((cx - rx * k, cy + ry), (cx - rx, cy + ry * k), (cx - rx, cy)),
                curve((cx - rx, cy - ry * k), (cx - rx * k, cy - ry), (cx, cy - ry)),
                curve((cx + rx * k, cy - ry), (cx + rx, cy - ry * k), (cx + rx, cy)),
                close,
            ]
        }
    }

    private static func roundedRectanglePath(width w: Double, height h: Double, radius: Double) -> TSP_Path {
        let r = min(max(radius, 0), min(w, h) / 2)
        let k = 0.5522847498307936
        return TSP_Path.with {
            $0.elements = [
                move(r, 0),
                line(w - r, 0),
                curve((w - r + r * k, 0), (w, r - r * k), (w, r)),
                line(w, h - r),
                curve((w, h - r + r * k), (w - r + r * k, h), (w - r, h)),
                line(r, h),
                curve((r - r * k, h), (0, h - r + r * k), (0, h - r)),
                line(0, r),
                curve((0, r - r * k), (r - r * k, 0), (r, 0)),
                close,
            ]
        }
    }

    private static func polygonPath(width w: Double, height h: Double, sides n: Int) -> TSP_Path {
        let cx = w / 2, cy = h / 2, rx = w / 2, ry = h / 2
        var elements: [TSP_Path.Element] = []
        for i in 0..<n {
            let angle = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(n)
            let x = cx + rx * cos(angle), y = cy + ry * sin(angle)
            elements.append(i == 0 ? move(x, y) : line(x, y))
        }
        elements.append(close)
        return TSP_Path.with { $0.elements = elements }
    }

    private static func starPath(width w: Double, height h: Double, points p: Int, innerRatio: Double) -> TSP_Path {
        let cx = w / 2, cy = h / 2, rx = w / 2, ry = h / 2
        var elements: [TSP_Path.Element] = []
        for i in 0..<(p * 2) {
            let outer = i % 2 == 0
            let radiusScale = outer ? 1.0 : innerRatio
            let angle = -Double.pi / 2 + Double.pi * Double(i) / Double(p)
            let x = cx + rx * radiusScale * cos(angle), y = cy + ry * radiusScale * sin(angle)
            elements.append(i == 0 ? move(x, y) : line(x, y))
        }
        elements.append(close)
        return TSP_Path.with { $0.elements = elements }
    }
}
