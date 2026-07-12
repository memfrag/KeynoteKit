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
}

extension KeynoteDocument {

    /// A path source (bezier) for a shape kind sized to `width`×`height`.
    static func pathSource(for kind: ShapeKind, width: Double, height: Double) -> TSD_PathSourceArchive {
        TSD_PathSourceArchive.with {
            $0.bezierPathSource = TSD_BezierPathSourceArchive.with {
                $0.naturalSize = TSP_Size.with { $0.width = Float(width); $0.height = Float(height) }
                $0.path = shapePath(for: kind, width: width, height: height)
            }
        }
    }

    static func shapePath(for kind: ShapeKind, width w: Double, height h: Double) -> TSP_Path {
        switch kind {
        case .rectangle:
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
