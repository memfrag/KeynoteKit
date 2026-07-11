import Foundation
import IWAContainer
import KeynoteSchemas

public enum TableError: Error {
    case notATable(UInt64)
    case cellOutOfRange(row: Int, column: Int)
    case unsupportedCellStorage(version: Int)
    case unsupportedValue(String)
}

/// Table cell reading and writing.
///
/// Keynote tables (`TST.TableInfoArchive`, drawable type 6000) keep their
/// cells outside the slide component: the table model references a
/// `DataStore` whose tiles (`TST.Tile`, in `Index/Tables/Tile*.iwa`) pack
/// each row's cells into a binary buffer (storage version 5): per cell —
/// version byte, cell-type byte, padding, a u32 flags word at offset 8, then
/// fixed-size fields in flag-bit order. Text cells store a key into the
/// table's string list (`TST.TableDataList`); numbers store a 16-byte
/// decimal (base-10 mantissa/exponent, bias 6176). Per-column u16 offsets
/// (0xFFFF = empty) index the row buffer. The `*_pre_bnc` twin buffers are a
/// legacy format that modern Keynote ignores.
extension KeynoteDocument {

    // MARK: Reading

    /// The cell grid of a table node (a `"table"` scene-tree node), as
    /// display strings. `nil` = empty cell.
    public func tableCells(_ nodeID: UInt64) throws -> [[String?]] {
        let table = try tableParts(nodeID)
        let strings = try stringsByKey(table)

        var grid: [[String?]] = Array(
            repeating: Array(repeating: nil, count: table.columns),
            count: table.rows
        )
        for (rowIndex, rowInfo) in try tileRows(table) {
            guard rowIndex < table.rows else { continue }
            for column in 0..<table.columns {
                guard let cell = try cellBytes(in: rowInfo, column: column) else { continue }
                grid[rowIndex][column] = try displayValue(of: cell, strings: strings)
            }
        }
        return grid
    }

    // MARK: Writing

    /// Sets a cell to text or — when `value` parses as a number and the
    /// cell's column is numeric in spirit — call `setTableCellNumber`.
    public mutating func setTableCellText(_ nodeID: UInt64, row: Int, column: Int, to text: String) throws {
        let table = try tableParts(nodeID)
        let key = try internString(text, in: table, releasing: try currentStringKey(table, row: row, column: column))

        var cell = Data([5, 3, 0, 0, 0, 0, 0, 0])
        appendUInt32(0x8, to: &cell)         // flags: string id only
        appendUInt32(UInt32(key), to: &cell) // the interned string
        try replaceCell(in: table, row: row, column: column, with: cell)
    }

    /// Sets a cell to a number (decimal128-encoded, like Keynote's own).
    public mutating func setTableCellNumber(_ nodeID: UInt64, row: Int, column: Int, to value: Double) throws {
        let table = try tableParts(nodeID)
        if let oldKey = try currentStringKey(table, row: row, column: column) {
            try releaseString(key: oldKey, in: table)
        }
        var cell = Data([5, 2, 0, 0, 0, 0, 0, 0])
        appendUInt32(0x1, to: &cell)         // flags: decimal only
        cell.append(try packDecimal(value))
        try replaceCell(in: table, row: row, column: column, with: cell)
    }

    // MARK: Table plumbing

    struct TableParts {
        let rows: Int
        let columns: Int
        let modelLocation: RecordLocation
        let stringTableID: UInt64
        let tileIDs: [(tileID: UInt32, recordID: UInt64)]
    }

    func tableParts(_ nodeID: UInt64) throws -> TableParts {
        let infoLocation = try locateSceneNode(nodeID)
        let infoRecord = components[infoLocation.component].records[infoLocation.record]
        guard infoRecord.primaryType == 6000 else { throw TableError.notATable(nodeID) }
        let info = try infoRecord.decode(TST_TableInfoArchive.self)

        let modelLocation = try locateSceneNode(info.tableModel.identifier)
        let model = try components[modelLocation.component].records[modelLocation.record]
            .decode(TST_TableModelArchive.self)
        return TableParts(
            rows: Int(model.numberOfRows),
            columns: Int(model.numberOfColumns),
            modelLocation: modelLocation,
            stringTableID: model.baseDataStore.stringTable.identifier,
            tileIDs: model.baseDataStore.tiles.tiles.map { ($0.tileid, $0.tile.identifier) }
        )
    }

    /// All tile rows as (absolute row index, rowInfo).
    private func tileRows(_ table: TableParts) throws -> [(Int, TST_TileRowInfo)] {
        var result: [(Int, TST_TileRowInfo)] = []
        for (tileID, recordID) in table.tileIDs {
            let location = try locateSceneNode(recordID)
            let tile = try components[location.component].records[location.record].decode(TST_Tile.self)
            for rowInfo in tile.rowInfos {
                result.append((Int(tileID) * 256 + Int(rowInfo.tileRowIndex), rowInfo))
            }
        }
        return result
    }

    // MARK: Cell buffer codec

    /// Field sizes in flag-bit order, per storage version 5.
    private static let cellFieldSizes: [(flag: UInt32, size: Int)] = [
        (0x1, 16), (0x2, 8), (0x4, 8), (0x8, 4), (0x10, 4), (0x20, 4), (0x40, 4),
        (0x80, 4), (0x100, 4), (0x200, 4), (0x400, 4), (0x800, 4), (0x1000, 4),
        (0x2000, 4), (0x4000, 4), (0x8000, 4), (0x10000, 4), (0x20000, 4),
        (0x40000, 4), (0x80000, 4), (0x100000, 4),
    ]

    private func cellLength(_ bytes: [UInt8], at offset: Int) throws -> Int {
        guard bytes[offset] == 5 else {
            throw TableError.unsupportedCellStorage(version: Int(bytes[offset]))
        }
        let flags = readUInt32(bytes, at: offset + 8)
        var length = 12
        for field in Self.cellFieldSizes where flags & field.flag != 0 {
            length += field.size
        }
        return length
    }

    private func fieldOffset(_ cell: [UInt8], flag: UInt32) -> Int? {
        let flags = readUInt32(cell, at: 8)
        guard flags & flag != 0 else { return nil }
        var offset = 12
        for field in Self.cellFieldSizes {
            if field.flag == flag { return offset }
            if flags & field.flag != 0 { offset += field.size }
        }
        return nil
    }

    /// The bytes of one cell in a row, or nil when empty.
    private func cellBytes(in rowInfo: TST_TileRowInfo, column: Int) throws -> [UInt8]? {
        let offsets = [UInt8](rowInfo.cellOffsets)
        guard column * 2 + 1 < offsets.count else { return nil }
        let offset = Int(offsets[column * 2]) | Int(offsets[column * 2 + 1]) << 8
        guard offset != 0xFFFF else { return nil }
        let buffer = [UInt8](rowInfo.cellStorageBuffer)
        guard offset + 12 <= buffer.count else { return nil }
        let length = try cellLength(buffer, at: offset)
        guard offset + length <= buffer.count else { return nil }
        return Array(buffer[offset..<(offset + length)])
    }

    private func displayValue(of cell: [UInt8], strings: [UInt32: String]) throws -> String? {
        switch cell[1] {
        case 0: // empty
            return nil
        case 3, 9: // text (9 = rich text; show plain string when present)
            guard let offset = fieldOffset(cell, flag: 0x8) else { return nil }
            return strings[readUInt32(cell, at: offset)]
        case 2, 10: // number, currency
            guard let offset = fieldOffset(cell, flag: 0x1) else { return nil }
            return formatNumber(unpackDecimal(Array(cell[offset..<(offset + 16)])))
        case 6: // bool
            guard let offset = fieldOffset(cell, flag: 0x2) else { return nil }
            let raw = readUInt64(cell, at: offset)
            return Double(bitPattern: raw) > 0 ? "TRUE" : "FALSE"
        default:
            return nil
        }
    }

    /// Rebuilds one row's storage with `newCell` at `column`.
    private mutating func replaceCell(in table: TableParts, row: Int, column: Int, with newCell: Data) throws {
        guard row >= 0, row < table.rows, column >= 0, column < table.columns else {
            throw TableError.cellOutOfRange(row: row, column: column)
        }
        guard let (tileID, recordID) = table.tileIDs.first(where: { Int($0.tileID) * 256 <= row && row < Int($0.tileID) * 256 + 256 })
        else {
            throw TableError.cellOutOfRange(row: row, column: column)
        }
        let location = try locateSceneNode(recordID)
        var record = components[location.component].records[location.record]
        var tile = try record.decode(TST_Tile.self)
        let tileRow = UInt32(row - Int(tileID) * 256)
        guard let rowIndex = tile.rowInfos.firstIndex(where: { $0.tileRowIndex == tileRow }) else {
            throw TableError.cellOutOfRange(row: row, column: column)
        }
        var rowInfo = tile.rowInfos[rowIndex]

        // Collect existing cells, swap in the new one, and re-pack.
        var cells: [Data?] = []
        var wasEmpty = true
        for c in 0..<table.columns {
            if c == column {
                wasEmpty = (try cellBytes(in: rowInfo, column: c)) == nil
                cells.append(newCell)
            } else {
                cells.append(try cellBytes(in: rowInfo, column: c).map { Data($0) })
            }
        }
        var buffer = Data()
        var offsets = Data()
        for cell in cells {
            if let cell {
                appendUInt16(UInt16(buffer.count), to: &offsets)
                buffer.append(cell)
            } else {
                appendUInt16(0xFFFF, to: &offsets)
            }
        }
        // Preserve the original offsets-array length (padded with 0xFFFF).
        while offsets.count < rowInfo.cellOffsets.count {
            appendUInt16(0xFFFF, to: &offsets)
        }
        rowInfo.cellStorageBuffer = buffer
        rowInfo.cellOffsets = offsets
        if wasEmpty {
            rowInfo.cellCount += 1
        }
        tile.rowInfos[rowIndex] = rowInfo
        try record.setMessage(tile)
        components[location.component].records[location.record] = record
    }

    // MARK: String list

    private func stringsByKey(_ table: TableParts) throws -> [UInt32: String] {
        let location = try locateSceneNode(table.stringTableID)
        let list = try components[location.component].records[location.record].decode(TST_TableDataList.self)
        return Dictionary(
            list.entries.compactMap { $0.hasString ? ($0.key, $0.string) : nil },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func currentStringKey(_ table: TableParts, row: Int, column: Int) throws -> UInt32? {
        for (rowIndex, rowInfo) in try tileRows(table) where rowIndex == row {
            guard let cell = try cellBytes(in: rowInfo, column: column),
                  cell[1] == 3,
                  let offset = fieldOffset(cell, flag: 0x8)
            else { return nil }
            return readUInt32(cell, at: offset)
        }
        return nil
    }

    /// Adds `text` to the table's string list (reusing an existing entry when
    /// possible) and releases `oldKey`. Returns the interned key.
    private mutating func internString(_ text: String, in table: TableParts, releasing oldKey: UInt32?) throws -> UInt32 {
        let location = try locateSceneNode(table.stringTableID)
        var record = components[location.component].records[location.record]
        var list = try record.decode(TST_TableDataList.self)

        if let oldKey, let index = list.entries.firstIndex(where: { $0.key == oldKey }) {
            list.entries[index].refcount -= 1
            if list.entries[index].refcount == 0 {
                list.entries.remove(at: index)
            }
        }
        let key: UInt32
        if let index = list.entries.firstIndex(where: { $0.hasString && $0.string == text }) {
            list.entries[index].refcount += 1
            key = list.entries[index].key
        } else {
            key = list.nextListID
            list.nextListID += 1
            list.entries.append(TST_TableDataList.ListEntry.with {
                $0.key = key
                $0.refcount = 1
                $0.string = text
            })
        }
        try record.setMessage(list)
        components[location.component].records[location.record] = record
        return key
    }

    private mutating func releaseString(key: UInt32, in table: TableParts) throws {
        let location = try locateSceneNode(table.stringTableID)
        var record = components[location.component].records[location.record]
        var list = try record.decode(TST_TableDataList.self)
        if let index = list.entries.firstIndex(where: { $0.key == key }) {
            list.entries[index].refcount -= 1
            if list.entries[index].refcount == 0 {
                list.entries.remove(at: index)
            }
            try record.setMessage(list)
            components[location.component].records[location.record] = record
        }
    }

    // MARK: Decimal codec (base-10 mantissa/exponent, bias 6176)

    private func unpackDecimal(_ bytes: [UInt8]) -> Double {
        let exponent = Int((UInt32(bytes[15] & 0x7F) << 7) | UInt32(bytes[14] >> 1)) - 6176
        var mantissa = Double(bytes[14] & 1)
        for index in stride(from: 13, through: 0, by: -1) {
            mantissa = mantissa * 256 + Double(bytes[index])
        }
        let sign: Double = bytes[15] & 0x80 != 0 ? -1 : 1
        return sign * mantissa * pow(10, Double(exponent))
    }

    private func packDecimal(_ value: Double) throws -> Data {
        guard value.isFinite else { throw TableError.unsupportedValue("\(value)") }
        var bytes = [UInt8](repeating: 0, count: 16)
        if value != 0 {
            // Derive an exact (mantissa, exponent) pair from the shortest
            // decimal representation.
            var text = "\(abs(value))"
            var exponent = 0
            if let eRange = text.range(of: "e") {
                exponent = Int(text[eRange.upperBound...]) ?? 0
                text = String(text[..<eRange.lowerBound])
            }
            if let dot = text.firstIndex(of: ".") {
                exponent -= text.distance(from: text.index(after: dot), to: text.endIndex)
                text.remove(at: dot)
            }
            guard let mantissa = UInt64(text) else {
                throw TableError.unsupportedValue("\(value)")
            }
            var remaining = mantissa
            var index = 0
            while remaining > 0 {
                bytes[index] = UInt8(remaining & 0xFF)
                remaining >>= 8
                index += 1
            }
            let biased = exponent + 6176
            bytes[14] = UInt8((biased & 0x7F) << 1)
            bytes[15] = UInt8(biased >> 7)
        } else {
            bytes[14] = UInt8((6176 & 0x7F) << 1)
            bytes[15] = UInt8(6176 >> 7)
        }
        if value < 0 {
            bytes[15] |= 0x80
        }
        return Data(bytes)
    }

    // MARK: Byte helpers

    private func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    private func readUInt64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in (0..<8).reversed() {
            value = value << 8 | UInt64(bytes[offset + index])
        }
        return value
    }

    private func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8(value >> 8))
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private func formatNumber(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return "\(value)"
    }
}
