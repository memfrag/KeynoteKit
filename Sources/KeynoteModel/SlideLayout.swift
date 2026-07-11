import Foundation
import IWAContainer
import KeynoteSchemas

/// A rectangle in slide coordinates (points; origin top-left).
public struct Frame: Equatable, Sendable, Codable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// One fillable region of a layout: a placeholder or a text shape, with the
/// semantic hints needed to decide what content belongs in it.
public struct PlaceholderField: Sendable, Codable {
    /// "title", "body", "object", "slideNumber", or "text" (a non-placeholder
    /// text shape such as a quote's attribution line).
    public let role: String
    /// The placeholder kind, e.g. "title", "body", "object" (nil for plain
    /// text shapes).
    public let kind: String?
    /// The master's prompt text, e.g. "Slide Title", "“Notable Quote”",
    /// "Attribution" — the strongest signal of what the field is for.
    public let prompt: String?
    /// "text" or "media" (object placeholders can hold an image/movie).
    public let contentType: String
    public let frame: Frame?
}

/// A structural description of one slide's layout — enough for a tool or an
/// AI to decide how to fill it without hard-coding theme knowledge.
public struct LayoutDescription: Sendable, Codable {
    public let index: Int
    public let masterName: String?
    public let fields: [PlaceholderField]
}

extension KeynoteDocument {

    /// Describes every slide's layout: its master and each fillable field
    /// with role, kind, prompt text, content type, and geometry. Reads the
    /// master (slide layout) each slide is built on, which is where the
    /// prompt text and canonical geometry live.
    public func layoutDescriptions() throws -> [LayoutDescription] {
        try (0..<slideCount).map { try layoutDescription(at: $0) }
    }

    public func layoutDescription(at index: Int) throws -> LayoutDescription {
        guard let master = try masterRecordAndComponent(forSlideAt: index) else {
            return LayoutDescription(index: index, masterName: nil, fields: [])
        }
        let (masterRecord, componentIndex) = master
        let slide = try masterRecord.decode(KN_SlideArchive.self)
        let component = components[componentIndex]

        // Placeholder id → role, from the master's named slots.
        var roleByID: [UInt64: String] = [:]
        if slide.hasTitlePlaceholder { roleByID[slide.titlePlaceholder.identifier] = "title" }
        if slide.hasBodyPlaceholder { roleByID[slide.bodyPlaceholder.identifier] = "body" }
        if slide.hasObjectPlaceholder { roleByID[slide.objectPlaceholder.identifier] = "object" }
        if slide.hasSlideNumberPlaceholder { roleByID[slide.slideNumberPlaceholder.identifier] = "slideNumber" }

        // Placeholder id → prompt, from the instructional text map.
        var promptByID: [UInt64: String] = [:]
        for entry in slide.instructionalTextMap.instructionalTextForInfos {
            promptByID[entry.info.identifier] = entry.instructionalText
        }

        // Every id worth reporting: named slots plus anything with a prompt.
        var ids = Array(roleByID.keys)
        for id in promptByID.keys where !ids.contains(id) { ids.append(id) }

        var fields: [PlaceholderField] = []
        for id in ids {
            guard let record = component.records.first(where: { $0.identifier == id }) else { continue }
            let role = roleByID[id] ?? "text"
            let kind = placeholderKind(of: record)
            let contentType = (role == "object" || kind == "object") ? "media" : "text"
            fields.append(PlaceholderField(
                role: role,
                kind: kind,
                prompt: promptByID[id],
                contentType: contentType,
                frame: frame(of: record)
            ))
        }

        // Stable, human-sensible ordering: title, body, object, then others.
        let order = ["title": 0, "body": 1, "object": 2, "slideNumber": 4]
        fields.sort { (order[$0.role] ?? 3) < (order[$1.role] ?? 3) }

        let name = slide.hasName ? slide.name : nil
        return LayoutDescription(index: index, masterName: name, fields: fields)
    }

    // MARK: Resolution helpers

    /// The master (slide layout) record for a slide, and the index of the
    /// component it lives in.
    func masterRecordAndComponent(forSlideAt index: Int) throws -> (ObjectRecord, Int)? {
        let nodeIDs = try slideNodeIdentifiers()
        guard nodeIDs.indices.contains(index) else {
            throw SlideContentError.slideIndexOutOfRange(index)
        }
        let node = try recordAnywhereOrNil(identifier: nodeIDs[index], type: 4)?.decode(KN_SlideNodeArchive.self)
        guard let slideRootID = node?.slide.identifier,
              let slideRecord = components.flatMap(\.records).first(where: { $0.identifier == slideRootID })
        else { return nil }
        let slide = try slideRecord.decode(KN_SlideArchive.self)
        guard slide.hasTemplateSlide else { return nil }
        let masterID = slide.templateSlide.identifier
        for (componentIndex, component) in components.enumerated() {
            if let record = component.records.first(where: { $0.identifier == masterID && $0.primaryType == 5 }) {
                return (record, componentIndex)
            }
        }
        return nil
    }

    private func recordAnywhereOrNil(identifier: UInt64, type: UInt32) -> ObjectRecord? {
        for component in components {
            if let record = component.records.first(where: {
                $0.identifier == identifier && $0.primaryType == type
            }) {
                return record
            }
        }
        return nil
    }

    private func placeholderKind(of record: ObjectRecord) -> String? {
        guard record.primaryType == 7,
              let placeholder = try? record.decode(KN_PlaceholderArchive.self)
        else { return nil }
        switch placeholder.kind {
        case .kKindTitlePlaceholder: return "title"
        case .kKindBodyPlaceholder: return "body"
        case .kKindObjectPlaceholder: return "object"
        case .kKindSlideNumberPlaceholder: return "slideNumber"
        case .kKindPlaceholder: return "placeholder"
        }
    }

    private func frame(of record: ObjectRecord) -> Frame? {
        let geometry: TSD_GeometryArchive
        switch record.primaryType {
        case 7:
            guard let p = try? record.decode(KN_PlaceholderArchive.self) else { return nil }
            geometry = p.super.super.super.geometry
        case 2011:
            guard let s = try? record.decode(TSWP_ShapeInfoArchive.self) else { return nil }
            geometry = s.super.super.geometry
        case 3005:
            guard let img = try? record.decode(TSD_ImageArchive.self) else { return nil }
            geometry = img.super.geometry
        default:
            return nil
        }
        return Frame(
            x: Double(geometry.position.x),
            y: Double(geometry.position.y),
            width: Double(geometry.size.width),
            height: Double(geometry.size.height)
        )
    }
}
