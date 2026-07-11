import Foundation

public enum IWAFileError: Error {
    case malformedArchiveInfo
    case truncatedPayload(identifier: UInt64)
}

/// One `TSP.ArchiveInfo`-framed record inside an .iwa component: the raw
/// ArchiveInfo header bytes plus the concatenated message payloads it
/// describes. Bytes are kept verbatim so an untouched record reserializes
/// byte-identically.
public struct ArchiveRecord: Sendable {
    /// Object identifier (`ArchiveInfo.identifier`, field 1), if present.
    public let identifier: UInt64?
    /// Message type IDs (`MessageInfo.type`, field 1 of each entry).
    public let messageTypes: [UInt32]
    /// Payload length of each message (`MessageInfo.length`, field 3).
    public let messageLengths: [Int]
    /// Raw ArchiveInfo bytes, without the leading record-length varint.
    public let archiveInfo: Data
    /// Concatenated payloads of all messages in this record.
    public let payload: Data

    public init(identifier: UInt64?, messageTypes: [UInt32], messageLengths: [Int], archiveInfo: Data, payload: Data) {
        self.identifier = identifier
        self.messageTypes = messageTypes
        self.messageLengths = messageLengths
        self.archiveInfo = archiveInfo
        self.payload = payload
    }
}

/// The decoded contents of a single `Index/*.iwa` component: an ordered list
/// of records. `serialize()` of an unmodified file reproduces the exact
/// decompressed bytes it was parsed from.
public struct IWAFile: Sendable {
    public var records: [ArchiveRecord]

    public init(records: [ArchiveRecord]) {
        self.records = records
    }

    /// Parses decompressed (post-Snappy) .iwa content.
    public static func parse(_ data: Data) throws -> IWAFile {
        var scanner = ProtoScanner(data)
        var records: [ArchiveRecord] = []

        while !scanner.isAtEnd {
            let infoBytes = try scanner.readLengthDelimited()
            let info = try parseArchiveInfo(infoBytes)
            let payloadLength = info.lengths.reduce(0, +)
            guard scanner.position + payloadLength <= scanner.bytes.count else {
                throw IWAFileError.truncatedPayload(identifier: info.identifier ?? 0)
            }
            let payload = Data(scanner.bytes[scanner.position..<(scanner.position + payloadLength)])
            scanner = ProtoScanner(bytes: scanner.bytes, position: scanner.position + payloadLength)
            records.append(ArchiveRecord(
                identifier: info.identifier,
                messageTypes: info.types,
                messageLengths: info.lengths,
                archiveInfo: Data(infoBytes),
                payload: payload
            ))
        }
        return IWAFile(records: records)
    }

    /// Reserializes all records to decompressed .iwa content.
    public func serialize() -> Data {
        var out = Data()
        for record in records {
            var length = UInt64(record.archiveInfo.count)
            repeat {
                var byte = UInt8(length & 0x7F)
                length >>= 7
                if length != 0 { byte |= 0x80 }
                out.append(byte)
            } while length != 0
            out.append(record.archiveInfo)
            out.append(record.payload)
        }
        return out
    }

    // MARK: ArchiveInfo scanning

    private static func parseArchiveInfo(
        _ slice: ArraySlice<UInt8>
    ) throws -> (identifier: UInt64?, types: [UInt32], lengths: [Int]) {
        var scanner = ProtoScanner(bytes: Array(slice))
        var identifier: UInt64?
        var types: [UInt32] = []
        var lengths: [Int] = []

        do {
            while let (fieldNumber, wireType) = try scanner.readFieldKey() {
                if fieldNumber == 1, wireType == 0 {
                    identifier = try scanner.readVarint()
                } else if fieldNumber == 2, wireType == 2 {
                    let messageInfo = try scanner.readLengthDelimited()
                    let parsed = try parseMessageInfo(messageInfo)
                    types.append(parsed.type)
                    lengths.append(parsed.length)
                } else {
                    try scanner.skipField(wireType: wireType)
                }
            }
        } catch {
            throw IWAFileError.malformedArchiveInfo
        }
        return (identifier, types, lengths)
    }

    private static func parseMessageInfo(_ slice: ArraySlice<UInt8>) throws -> (type: UInt32, length: Int) {
        var scanner = ProtoScanner(bytes: Array(slice))
        var type: UInt32 = 0
        var length = 0
        while let (fieldNumber, wireType) = try scanner.readFieldKey() {
            if fieldNumber == 1, wireType == 0 {
                type = UInt32(truncatingIfNeeded: try scanner.readVarint())
            } else if fieldNumber == 3, wireType == 0 {
                length = Int(try scanner.readVarint())
            } else {
                try scanner.skipField(wireType: wireType)
            }
        }
        return (type, length)
    }
}
