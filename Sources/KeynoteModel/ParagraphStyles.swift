import Foundation
import KeynoteSchemas

/// Horizontal alignment of a paragraph.
public enum TextAlignment: Sendable {
    case left, right, center, justified, natural

    var archiveValue: TSWP_ParagraphStylePropertiesArchive.TextAlignmentType {
        switch self {
        case .left: return .tatvalue0
        case .right: return .tatvalue1
        case .center: return .tatvalue2
        case .justified: return .tatvalue3
        case .natural: return .tatvalue4
        }
    }
}

/// A tab stop in a paragraph style.
public struct TabStop: Sendable {
    public enum Alignment: Sendable { case left, center, right, decimal }
    /// Position from the left margin, in points.
    public var position: Double
    public var alignment: Alignment
    /// Optional leader (e.g. "." for a dotted leader to the tab).
    public var leader: String?

    public init(position: Double, alignment: Alignment = .left, leader: String? = nil) {
        self.position = position
        self.alignment = alignment
        self.leader = leader
    }

    var archiveAlignment: TSWP_TabArchive.TabAlignmentType {
        switch alignment {
        case .left: return .kTabAlignmentLeft
        case .center: return .kTabAlignmentCenter
        case .right: return .kTabAlignmentRight
        case .decimal: return .kTabAlignmentDecimal
        }
    }
}

/// The label on a list's paragraphs.
public enum ListMarker: Sendable {
    /// A string bullet (e.g. "•", "—", "▸").
    case bullet(String)
    /// An auto-incrementing number in the given format.
    case numbered(NumberFormat)
}

/// A numbered-list format.
public enum NumberFormat: Sendable {
    case decimal        // 1. 2. 3.
    case decimalParen   // 1) 2) 3)
    case romanUpper     // I. II. III.
    case romanLower     // i. ii. iii.
    case alphaUpper     // A. B. C.
    case alphaLower     // a. b. c.

    var numberType: TSWP_ListStyleArchive.NumberType {
        switch self {
        case .decimal: return .kNumericDecimal
        case .decimalParen: return .kNumericRightParen
        case .romanUpper: return .kRomanUpperDecimal
        case .romanLower: return .kRomanLowerDecimal
        case .alphaUpper: return .kAlphaUpperDecimal
        case .alphaLower: return .kAlphaLowerDecimal
        }
    }
}

/// A named paragraph style you can register into a document's stylesheet and
/// then apply to text — appearing alongside the theme's own paragraph styles
/// in Keynote's panel. Combines paragraph formatting (alignment, spacing,
/// indents, background) with the font it uses.
public struct ParagraphStyle: Sendable {
    public var name: String
    // Font (character) properties.
    public var fontSize: Double?
    public var bold: Bool?
    public var italic: Bool?
    public var color: (Double, Double, Double, Double)?
    // Paragraph properties.
    public var alignment: TextAlignment?
    public var spaceBefore: Double?
    public var spaceAfter: Double?
    public var firstLineIndent: Double?
    public var leftIndent: Double?
    public var rightIndent: Double?
    /// A paragraph background fill (RGBA 0…1).
    public var background: (Double, Double, Double, Double)?
    /// Tab stops.
    public var tabs: [TabStop]?

    public init(
        name: String, fontSize: Double? = nil, bold: Bool? = nil, italic: Bool? = nil,
        color: (Double, Double, Double, Double)? = nil, alignment: TextAlignment? = nil,
        spaceBefore: Double? = nil, spaceAfter: Double? = nil,
        firstLineIndent: Double? = nil, leftIndent: Double? = nil, rightIndent: Double? = nil,
        background: (Double, Double, Double, Double)? = nil,
        tabs: [TabStop]? = nil
    ) {
        self.name = name
        self.fontSize = fontSize
        self.bold = bold
        self.italic = italic
        self.color = color
        self.alignment = alignment
        self.spaceBefore = spaceBefore
        self.spaceAfter = spaceAfter
        self.firstLineIndent = firstLineIndent
        self.leftIndent = leftIndent
        self.rightIndent = rightIndent
        self.background = background
        self.tabs = tabs
    }
}

extension KeynoteDocument {

    /// Registers a paragraph style into the document's stylesheet — it joins
    /// the theme's paragraph styles (visible in Keynote's panel) and can be
    /// applied to text. Returns the new style's id.
    @discardableResult
    public mutating func defineParagraphStyle(_ style: ParagraphStyle) throws -> UInt64 {
        guard let base = defaultTextStyles() else {
            throw SceneEditError.unsupportedEdit("no theme paragraph style to inherit")
        }
        let baseParaID = base.para
        let styleSheetID = base.styleSheet
        guard let stylesheetComponent = components.firstIndex(where: {
            $0.records.contains { $0.identifier == styleSheetID }
        }), let stylesheetIndex = components[stylesheetComponent].records.firstIndex(where: {
            $0.identifier == styleSheetID
        }) else {
            throw SceneEditError.unsupportedEdit("cannot locate the document stylesheet")
        }

        let newID = try allocateIdentifier()
        let identifier = "kk-para-\(newID)"

        var overrideCount: UInt32 = 0
        var charProperties = TSWP_CharacterStylePropertiesArchive()
        if let fontSize = style.fontSize { charProperties.fontSize = Float(fontSize); overrideCount += 1 }
        if let bold = style.bold { charProperties.bold = bold; overrideCount += 1 }
        if let italic = style.italic { charProperties.italic = italic; overrideCount += 1 }
        if let color = style.color {
            charProperties.fontColor = Self.color(color)
            charProperties.tsdFill = TSD_FillArchive.with { $0.color = Self.color(color) }
            overrideCount += 1
        }

        var paraProperties = TSWP_ParagraphStylePropertiesArchive()
        if let alignment = style.alignment { paraProperties.alignment = alignment.archiveValue; overrideCount += 1 }
        if let spaceBefore = style.spaceBefore { paraProperties.spaceBefore = Float(spaceBefore); overrideCount += 1 }
        if let spaceAfter = style.spaceAfter { paraProperties.spaceAfter = Float(spaceAfter); overrideCount += 1 }
        if let firstLineIndent = style.firstLineIndent { paraProperties.firstLineIndent = Float(firstLineIndent); overrideCount += 1 }
        if let leftIndent = style.leftIndent { paraProperties.leftIndent = Float(leftIndent); overrideCount += 1 }
        if let rightIndent = style.rightIndent { paraProperties.rightIndent = Float(rightIndent); overrideCount += 1 }
        if let background = style.background { paraProperties.fill = Self.color(background); overrideCount += 1 }
        if let tabs = style.tabs {
            paraProperties.tabs = TSWP_TabsArchive.with {
                $0.tabs = tabs.map { stop in
                    TSWP_TabArchive.with {
                        $0.position = Float(stop.position)
                        $0.alignment = stop.archiveAlignment
                        if let leader = stop.leader { $0.leader = leader }
                    }
                }
            }
            overrideCount += 1
        }

        let paragraphStyle = TSWP_ParagraphStyleArchive.with {
            $0.super = TSS_StyleArchive.with {
                $0.name = style.name
                $0.styleIdentifier = identifier
                $0.parent = reference(baseParaID)
                $0.stylesheet = reference(styleSheetID)
            }
            $0.overrideCount = overrideCount
            $0.charProperties = charProperties
            $0.paraProperties = paraProperties
        }
        let styleRecord = try makeRecord(
            identifier: newID, type: 2022, message: paragraphStyle,
            version: [1, 0, 5], objectReferences: [baseParaID]
        )
        components[stylesheetComponent].records.append(styleRecord)

        // Register the style in the stylesheet so Keynote lists it.
        var stylesheetRecord = components[stylesheetComponent].records[stylesheetIndex]
        var stylesheet = try stylesheetRecord.decode(TSS_StylesheetArchive.self)
        stylesheet.styles.append(reference(newID))
        stylesheet.identifierToStyleMap.append(TSS_StylesheetArchive.IdentifiedStyleEntry.with {
            $0.identifier = identifier
            $0.style = reference(newID)
        })
        try stylesheetRecord.setMessage(stylesheet)
        var refs = stylesheetRecord.info.messageInfos[0].objectReferences
        if !refs.contains(newID) { refs.append(newID) }
        try stylesheetRecord.setObjectReferences(refs, at: 0)
        components[stylesheetComponent].records[stylesheetIndex] = stylesheetRecord

        return newID
    }

    /// Turns a text node's paragraphs into a bulleted list. Convenience for
    /// ``setNodeList(_:_:indent:)`` with a string bullet.
    public mutating func setNodeBulleted(_ nodeID: UInt64, bullet: String = "\u{2022}", indent: Double = 35) throws {
        try setNodeList(nodeID, .bullet(bullet), indent: indent)
    }

    /// Turns a text node's paragraphs into a numbered list. Convenience for
    /// ``setNodeList(_:_:indent:)`` with a number format.
    public mutating func setNodeNumbered(_ nodeID: UInt64, _ format: NumberFormat = .decimal, indent: Double = 35) throws {
        try setNodeList(nodeID, .numbered(format), indent: indent)
    }

    /// Turns a text node's paragraphs into a list with the given marker. Builds
    /// a list style from the theme's own (full per-level arrays) so the text
    /// lays out correctly, then points every paragraph at it.
    public mutating func setNodeList(_ nodeID: UInt64, _ marker: ListMarker, indent: Double = 35) throws {
        guard let styles = defaultTextStyles(), let baseListID = styles.list,
              let stylesheetComponent = components.firstIndex(where: {
                  $0.records.contains { $0.identifier == baseListID }
              }),
              let baseRecord = components[stylesheetComponent].records.first(where: { $0.identifier == baseListID }),
              var list = try? baseRecord.decode(TSWP_ListStyleArchive.self)
        else { throw SceneEditError.unsupportedEdit("no theme list style to base a list on") }

        // Keynote's list styles carry one entry per indent level; a marker
        // needs a full set (a single-entry array corrupts text layout).
        let levels = max(9, list.labelTypes.count)
        switch marker {
        case let .bullet(character):
            list.labelTypes = Array(repeating: .kString, count: levels)
            list.strings = Array(repeating: character, count: levels)
            list.numberTypes = []
        case let .numbered(format):
            list.labelTypes = Array(repeating: .kNumber, count: levels)
            list.numberTypes = Array(repeating: format.numberType, count: levels)
            list.strings = []
        }
        list.textIndents = Array(repeating: 1.09375, count: levels)  // theme's value
        list.indents = (0..<levels).map { Float(Double($0) * indent) }
        let geometry = TSWP_ListStyleArchive.LabelGeometry.with {
            $0.scale = 1; $0.baselineOffset = 0; $0.scaleWithText = true
        }
        list.geometries = Array(repeating: geometry, count: levels)

        let listID = try allocateIdentifier()
        list.super.name = "List"
        list.super.styleIdentifier = "kk-list-\(listID)"
        list.super.clearParent()
        let listRecord = try makeRecord(
            identifier: listID, type: 2023, message: list, version: [1, 0, 5], objectReferences: []
        )
        components[stylesheetComponent].records.append(listRecord)

        // Point every paragraph's list-style entry at the list style.
        let location = try locateSceneNode(nodeID)
        guard let storageID = try storageIdentifier(forNodeAt: location),
              let storageIndex = components[location.component].records.firstIndex(where: { $0.identifier == storageID })
        else { throw SceneEditError.nodeHasNoText(nodeID) }
        var storageRecord = components[location.component].records[storageIndex]
        var storage = try storageRecord.decode(TSWP_StorageArchive.self)
        if storage.tableListStyle.entries.isEmpty {
            storage.tableListStyle.entries = [TSWP_ObjectAttributeTable.ObjectAttribute.with { $0.characterIndex = 0 }]
        }
        for i in storage.tableListStyle.entries.indices {
            storage.tableListStyle.entries[i].object = reference(listID)
        }
        try storageRecord.setMessage(storage)
        var refs = storageRecord.info.messageInfos[0].objectReferences
        if !refs.contains(listID) { refs.append(listID) }
        try storageRecord.setObjectReferences(refs, at: 0)
        components[location.component].records[storageIndex] = storageRecord
        try declareExternalReference(fromComponent: location.component, toObject: listID)
    }

    /// Lays a text box out in `count` equal columns with a `gap` between them.
    public mutating func setNodeColumns(_ nodeID: UInt64, count: Int, gap: Double = 20) throws {
        try varyTextContainer(nodeID) {
            $0.columns = TSWP_ColumnsArchive.with {
                $0.equalColumns = TSWP_ColumnsArchive.EqualColumnsArchive.with {
                    $0.count = UInt32(max(1, count))
                    $0.gap = Float(gap)
                }
            }
        }
    }

    /// Sets a text box's inset — the padding between the text and the box edge
    /// (points, applied to all four sides).
    public mutating func setNodeTextInset(_ nodeID: UInt64, _ inset: Double) throws {
        try varyTextContainer(nodeID) {
            $0.padding = TSWP_PaddingArchive.with {
                $0.left = Float(inset); $0.top = Float(inset)
                $0.right = Float(inset); $0.bottom = Float(inset)
            }
        }
    }

    /// Overrides a text box's container properties (columns, padding) via a
    /// shape-style variation, mirroring how it carries the fill/stroke.
    private mutating func varyTextContainer(
        _ nodeID: UInt64, _ apply: (inout TSWP_ShapeStylePropertiesArchive) -> Void
    ) throws {
        let location = try locateSceneNode(nodeID)
        var record = components[location.component].records[location.record]
        guard record.primaryType == 2011 else {
            throw SceneEditError.unsupportedEdit("node \(nodeID) is not a text box")
        }
        var shape = try record.decode(TSWP_ShapeInfoArchive.self)
        guard shape.super.hasStyle else {
            throw SceneEditError.unsupportedEdit("text box \(nodeID) has no base style to inherit")
        }
        let baseStyleID = shape.super.style.identifier
        guard let stylesheetComponent = components.firstIndex(where: {
            $0.records.contains { $0.identifier == baseStyleID }
        }), let baseRecord = components[stylesheetComponent].records.first(where: { $0.identifier == baseStyleID }),
            let baseStyle = try? baseRecord.decode(TSWP_ShapeStyleArchive.self)
        else {
            throw SceneEditError.unsupportedEdit("cannot locate the base style for text box \(nodeID)")
        }
        let styleSheetID = baseStyle.super.super.hasStylesheet ? baseStyle.super.super.stylesheet.identifier : nil

        var properties = TSWP_ShapeStylePropertiesArchive()
        apply(&properties)

        let newStyleID = try allocateIdentifier()
        let style = TSWP_ShapeStyleArchive.with {
            $0.super = TSD_ShapeStyleArchive.with {
                $0.super = TSS_StyleArchive.with {
                    $0.parent = reference(baseStyleID)
                    $0.isVariation = true
                    if let styleSheetID { $0.stylesheet = reference(styleSheetID) }
                }
                $0.overrideCount = 1
            }
            $0.overrideCount = 1
            $0.shapeProperties = properties
        }
        let styleRecord = try makeRecord(
            identifier: newStyleID, type: 2025, message: style,
            version: record.info.messageInfos[0].version, objectReferences: [baseStyleID]
        )
        components[stylesheetComponent].records.append(styleRecord)

        shape.super.style = reference(newStyleID)
        try record.setMessage(shape)
        var refs = record.info.messageInfos[0].objectReferences
        if !refs.contains(newStyleID) { refs.append(newStyleID) }
        try record.setObjectReferences(refs, at: 0)
        components[location.component].records[location.record] = record
        try declareExternalReference(fromComponent: location.component, toObject: newStyleID)
    }

    /// Applies a registered paragraph style (from ``defineParagraphStyle(_:)``)
    /// to every paragraph of a text node.
    public mutating func applyParagraphStyle(_ styleID: UInt64, to nodeID: UInt64) throws {
        let location = try locateSceneNode(nodeID)
        guard let storageID = try storageIdentifier(forNodeAt: location),
              let storageIndex = components[location.component].records.firstIndex(where: { $0.identifier == storageID })
        else { throw SceneEditError.nodeHasNoText(nodeID) }

        var storageRecord = components[location.component].records[storageIndex]
        var storage = try storageRecord.decode(TSWP_StorageArchive.self)
        for i in storage.tableParaStyle.entries.indices {
            storage.tableParaStyle.entries[i].object = reference(styleID)
        }
        // Clear character overrides so the paragraph style's font takes effect.
        for i in storage.tableCharStyle.entries.indices {
            storage.tableCharStyle.entries[i].clearObject()
        }
        try storageRecord.setMessage(storage)
        var refs = storageRecord.info.messageInfos[0].objectReferences
        if !refs.contains(styleID) { refs.append(styleID) }
        try storageRecord.setObjectReferences(refs, at: 0)
        components[location.component].records[storageIndex] = storageRecord

        try declareExternalReference(fromComponent: location.component, toObject: styleID)
    }
}
