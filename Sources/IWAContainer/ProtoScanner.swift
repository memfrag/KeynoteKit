import Foundation

public enum ProtoScanError: Error {
    case truncatedVarint
    case truncatedField
    case unsupportedWireType(UInt8)
}

/// A minimal protobuf wire-format reader. The container layer only needs to
/// peek inside `TSP.ArchiveInfo` far enough to learn each record's payload
/// lengths; full schema-typed decoding lives in the (generated) schema layer.
public struct ProtoScanner {
    public let bytes: [UInt8]
    public private(set) var position: Int

    public init(_ data: Data) {
        self.bytes = [UInt8](data)
        self.position = 0
    }

    public init(bytes: [UInt8], position: Int = 0) {
        self.bytes = bytes
        self.position = position
    }

    public var isAtEnd: Bool { position >= bytes.count }

    public mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard position < bytes.count else { throw ProtoScanError.truncatedVarint }
            let byte = bytes[position]
            position += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            guard shift <= 63 else { throw ProtoScanError.truncatedVarint }
        }
    }

    /// Reads a field key; returns nil at end of input.
    public mutating func readFieldKey() throws -> (fieldNumber: Int, wireType: UInt8)? {
        guard !isAtEnd else { return nil }
        let key = try readVarint()
        return (Int(key >> 3), UInt8(key & 0x07))
    }

    public mutating func readLengthDelimited() throws -> ArraySlice<UInt8> {
        let length = Int(try readVarint())
        guard position + length <= bytes.count else { throw ProtoScanError.truncatedField }
        defer { position += length }
        return bytes[position..<(position + length)]
    }

    public mutating func skipField(wireType: UInt8) throws {
        switch wireType {
        case 0:
            _ = try readVarint()
        case 1:
            guard position + 8 <= bytes.count else { throw ProtoScanError.truncatedField }
            position += 8
        case 2:
            _ = try readLengthDelimited()
        case 5:
            guard position + 4 <= bytes.count else { throw ProtoScanError.truncatedField }
            position += 4
        default:
            throw ProtoScanError.unsupportedWireType(wireType)
        }
    }
}
