import Foundation
import IWAContainer
import KeynoteSchemas
import SwiftProtobuf

public enum ObjectRecordError: Error {
    case payloadIndexOutOfRange
    case unknownMessageType(UInt32)
}

/// A typed view over one `ArchiveRecord`: the decoded `TSP.ArchiveInfo`
/// plus each message's payload bytes.
///
/// Untouched records reserialize from their original bytes, so a document
/// that is parsed and written back stays byte-identical at the payload
/// level. Mutating a payload re-encodes the ArchiveInfo with updated
/// `MessageInfo.length` values.
public struct ObjectRecord {
    public private(set) var info: TSP_ArchiveInfo
    public private(set) var payloads: [Data]

    private let rawInfo: Data
    private var isDirty = false

    public init(_ record: ArchiveRecord) throws {
        self.info = try TSP_ArchiveInfo(serializedBytes: record.archiveInfo)
        self.rawInfo = record.archiveInfo

        var payloads: [Data] = []
        var offset = 0
        for length in record.messageLengths {
            payloads.append(record.payload.subdata(in: offset..<(offset + length)))
            offset += length
        }
        self.payloads = payloads
    }

    public var identifier: UInt64? {
        info.hasIdentifier ? info.identifier : nil
    }

    /// The message type ID of the primary (first) message.
    public var primaryType: UInt32? {
        info.messageInfos.first?.type
    }

    /// Decodes the payload at `index` as its registry type.
    public func decodeMessage(at index: Int = 0) throws -> any SwiftProtobuf.Message {
        guard index < payloads.count, index < info.messageInfos.count else {
            throw ObjectRecordError.payloadIndexOutOfRange
        }
        let typeID = info.messageInfos[index].type
        guard let messageType = TSPRegistry.messageType(for: typeID) else {
            throw ObjectRecordError.unknownMessageType(typeID)
        }
        return try messageType.init(serializedBytes: payloads[index])
    }

    /// Decodes the payload at `index` as a specific message type.
    public func decode<M: SwiftProtobuf.Message>(_ type: M.Type, at index: Int = 0) throws -> M {
        guard index < payloads.count else { throw ObjectRecordError.payloadIndexOutOfRange }
        return try M(serializedBytes: payloads[index])
    }

    /// Replaces the payload at `index` with a re-encoded message.
    public mutating func setMessage(_ message: any SwiftProtobuf.Message, at index: Int = 0) throws {
        guard index < payloads.count, index < info.messageInfos.count else {
            throw ObjectRecordError.payloadIndexOutOfRange
        }
        let bytes: Data = try message.serializedData()
        payloads[index] = bytes
        info.messageInfos[index].length = UInt32(bytes.count)
        isDirty = true
    }

    /// Lowers back to a raw `ArchiveRecord`.
    public func lowered() throws -> ArchiveRecord {
        let infoBytes: Data = isDirty ? try info.serializedData() : rawInfo
        return ArchiveRecord(
            identifier: identifier,
            messageTypes: info.messageInfos.map(\.type),
            messageLengths: payloads.map(\.count),
            archiveInfo: infoBytes,
            payload: payloads.reduce(into: Data()) { $0.append($1) }
        )
    }
}
