import Foundation
import IWAContainer
import KeynoteSchemas

/// Schema-guided wire-format walker: finds and rewrites every
/// `TSP.Reference` inside a message payload without fully decoding it.
///
/// Guided by `MessageFieldMap` (generated from the .proto set), it descends
/// only into fields whose declared type is a message, treats
/// `TSP.Reference` fields as identifiers to remap, and copies everything
/// else verbatim. Identifiers absent from the map are left unchanged, so a
/// map containing only a cloned subtree's IDs rewrites internal references
/// while preserving external ones (stylesheet entries, theme objects, …).
public enum ReferenceRewriter {

    static let referenceTypeName = "TSP.Reference"

    /// Rewrites all reference identifiers found in `payload` through `map`.
    public static func rewrite(
        _ payload: Data,
        typeName: String,
        using map: [UInt64: UInt64]
    ) throws -> Data {
        var out = Data(capacity: payload.count + 64)
        try walk(Array(payload), typeName: typeName, map: map, out: &out)
        return out
    }

    /// Collects every reference identifier reachable in `payload`.
    public static func collectReferences(in payload: Data, typeName: String) throws -> [UInt64] {
        var seen: [UInt64] = []
        var sink = Data()
        try walk(Array(payload), typeName: typeName, map: [:], out: &sink) { seen.append($0) }
        return seen
    }

    // MARK: Wire walking

    private static func walk(
        _ bytes: [UInt8],
        typeName: String,
        map: [UInt64: UInt64],
        out: inout Data,
        onReference: ((UInt64) -> Void)? = nil
    ) throws {
        let fields = MessageFieldMap.messageFields[typeName]
        var scanner = ProtoScanner(bytes: bytes)

        while let (fieldNumber, wireType) = try scanner.readFieldKey() {
            appendVarint(UInt64(fieldNumber) << 3 | UInt64(wireType), to: &out)

            switch wireType {
            case 0:
                appendVarint(try scanner.readVarint(), to: &out)
            case 1:
                let start = scanner.position
                try scanner.skipField(wireType: 1)
                out.append(contentsOf: bytes[start..<scanner.position])
            case 5:
                let start = scanner.position
                try scanner.skipField(wireType: 5)
                out.append(contentsOf: bytes[start..<scanner.position])
            case 2:
                let sub = try scanner.readLengthDelimited()
                guard let subType = fields?[fieldNumber] else {
                    appendVarint(UInt64(sub.count), to: &out)
                    out.append(contentsOf: sub)
                    continue
                }
                var rewritten = Data(capacity: sub.count + 8)
                if subType == referenceTypeName {
                    try rewriteReference(Array(sub), map: map, out: &rewritten, onReference: onReference)
                } else if MessageFieldMap.messageFields[subType] != nil {
                    try walk(Array(sub), typeName: subType, map: map, out: &rewritten, onReference: onReference)
                } else {
                    // Enum, packed scalars, or a message with no typed fields.
                    rewritten.append(contentsOf: sub)
                }
                appendVarint(UInt64(rewritten.count), to: &out)
                out.append(rewritten)
            default:
                // Groups (wire types 3/4) never occur in the iWork schemas.
                throw ProtoScanError.unsupportedWireType(wireType)
            }
        }
    }

    private static func rewriteReference(
        _ bytes: [UInt8],
        map: [UInt64: UInt64],
        out: inout Data,
        onReference: ((UInt64) -> Void)?
    ) throws {
        var scanner = ProtoScanner(bytes: bytes)
        while let (fieldNumber, wireType) = try scanner.readFieldKey() {
            if fieldNumber == 1, wireType == 0 {
                let identifier = try scanner.readVarint()
                onReference?(identifier)
                appendVarint(1 << 3 | 0, to: &out)
                appendVarint(map[identifier] ?? identifier, to: &out)
            } else {
                appendVarint(UInt64(fieldNumber) << 3 | UInt64(wireType), to: &out)
                let start = scanner.position
                try scanner.skipField(wireType: wireType)
                out.append(contentsOf: bytes[start..<scanner.position])
            }
        }
    }

    static func appendVarint(_ value: UInt64, to out: inout Data) {
        var value = value
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            out.append(byte)
        } while value != 0
    }
}
