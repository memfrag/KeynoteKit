import Foundation

/// Errors thrown by the raw Snappy codec and the IWA chunk framing layer.
public enum SnappyError: Error, Equatable {
    case truncated
    case invalidVarint
    case invalidCopyOffset
    case decompressedLengthMismatch(expected: Int, actual: Int)
    case unsupportedChunkType(UInt8)
}

/// Raw (non-framed) Snappy compression, as used inside each IWA chunk.
///
/// Apple's .iwa files wrap raw Snappy blocks in their own 4-byte chunk
/// headers (see `IWA`), *not* the standard Snappy framing format — there is
/// no stream identifier chunk and no CRC-32C.
public enum Snappy {

    // MARK: Decompression

    public static func decompress(_ input: Data) throws -> Data {
        let bytes = [UInt8](input)
        var pos = 0

        // Preamble: uncompressed length as a little-endian varint.
        var expectedLength: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard pos < bytes.count else { throw SnappyError.truncated }
            let byte = bytes[pos]
            pos += 1
            expectedLength |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
            guard shift <= 63 else { throw SnappyError.invalidVarint }
        }

        var out = [UInt8]()
        out.reserveCapacity(Int(expectedLength))

        while pos < bytes.count {
            let tag = bytes[pos]
            pos += 1
            switch tag & 0x03 {
            case 0x00: // literal
                var length = Int(tag >> 2)
                if length >= 60 {
                    let extraBytes = length - 59 // 60 → 1 … 63 → 4
                    guard pos + extraBytes <= bytes.count else { throw SnappyError.truncated }
                    length = 0
                    for i in 0..<extraBytes {
                        length |= Int(bytes[pos + i]) << (8 * i)
                    }
                    pos += extraBytes
                }
                length += 1
                guard pos + length <= bytes.count else { throw SnappyError.truncated }
                out.append(contentsOf: bytes[pos..<(pos + length)])
                pos += length

            case 0x01: // copy, 1-byte offset
                guard pos < bytes.count else { throw SnappyError.truncated }
                let length = 4 + Int((tag >> 2) & 0x07)
                let offset = (Int(tag & 0xE0) << 3) | Int(bytes[pos])
                pos += 1
                try copyBackReference(into: &out, offset: offset, length: length)

            case 0x02: // copy, 2-byte little-endian offset
                guard pos + 2 <= bytes.count else { throw SnappyError.truncated }
                let length = Int(tag >> 2) + 1
                let offset = Int(bytes[pos]) | Int(bytes[pos + 1]) << 8
                pos += 2
                try copyBackReference(into: &out, offset: offset, length: length)

            default: // 0x03: copy, 4-byte little-endian offset
                guard pos + 4 <= bytes.count else { throw SnappyError.truncated }
                let length = Int(tag >> 2) + 1
                let offset = Int(bytes[pos])
                    | Int(bytes[pos + 1]) << 8
                    | Int(bytes[pos + 2]) << 16
                    | Int(bytes[pos + 3]) << 24
                pos += 4
                try copyBackReference(into: &out, offset: offset, length: length)
            }
        }

        guard out.count == Int(expectedLength) else {
            throw SnappyError.decompressedLengthMismatch(expected: Int(expectedLength), actual: out.count)
        }
        return Data(out)
    }

    private static func copyBackReference(into out: inout [UInt8], offset: Int, length: Int) throws {
        guard offset > 0, offset <= out.count else { throw SnappyError.invalidCopyOffset }
        var src = out.count - offset
        for _ in 0..<length {
            out.append(out[src])
            src += 1
        }
    }

    // MARK: Compression

    private static let hashTableBits = 14
    private static let blockSize = 1 << 16

    public static func compress(_ input: Data) -> Data {
        var out = [UInt8]()
        out.reserveCapacity(input.count / 2 + 16)

        var remaining = UInt64(input.count)
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 { byte |= 0x80 }
            out.append(byte)
        } while remaining != 0

        let bytes = [UInt8](input)
        var blockStart = 0
        while blockStart < bytes.count {
            let blockEnd = min(blockStart + blockSize, bytes.count)
            compressBlock(bytes, from: blockStart, to: blockEnd, into: &out)
            blockStart = blockEnd
        }
        return Data(out)
    }

    /// Greedy match finder over one 64 KiB block, mirroring the reference
    /// implementation's structure. Back-references never cross block
    /// boundaries, so 2-byte offsets always suffice.
    private static func compressBlock(_ bytes: [UInt8], from start: Int, to end: Int, into out: inout [UInt8]) {
        let length = end - start
        if length < 4 {
            emitLiteral(bytes, from: start, to: end, into: &out)
            return
        }

        var table = [Int32](repeating: -1, count: 1 << hashTableBits)
        var anchor = start
        var pos = start
        let matchLimit = end - 4

        while pos <= matchLimit {
            let h = hash(load32(bytes, at: pos))
            let candidate = Int(table[h])
            table[h] = Int32(pos)

            if candidate >= start,
               pos - candidate <= 0xFFFF,
               load32(bytes, at: candidate) == load32(bytes, at: pos) {
                if anchor < pos {
                    emitLiteral(bytes, from: anchor, to: pos, into: &out)
                }
                var matchLength = 4
                while pos + matchLength < end && bytes[candidate + matchLength] == bytes[pos + matchLength] {
                    matchLength += 1
                }
                emitCopy(offset: pos - candidate, length: matchLength, into: &out)
                pos += matchLength
                anchor = pos
            } else {
                pos += 1
            }
        }

        if anchor < end {
            emitLiteral(bytes, from: anchor, to: end, into: &out)
        }
    }

    private static func load32(_ bytes: [UInt8], at index: Int) -> UInt32 {
        UInt32(bytes[index])
            | UInt32(bytes[index + 1]) << 8
            | UInt32(bytes[index + 2]) << 16
            | UInt32(bytes[index + 3]) << 24
    }

    private static func hash(_ value: UInt32) -> Int {
        Int((value &* 0x1E35A7BD) >> (32 - UInt32(hashTableBits)))
    }

    private static func emitLiteral(_ bytes: [UInt8], from start: Int, to end: Int, into out: inout [UInt8]) {
        var start = start
        while start < end {
            // A single literal element can carry up to 2^32 bytes, but cap
            // emission at what one extra length byte covers to keep it simple.
            let chunk = min(end - start, 65536)
            let n = chunk - 1
            if n < 60 {
                out.append(UInt8(n) << 2)
            } else if n < 256 {
                out.append(60 << 2)
                out.append(UInt8(n))
            } else {
                out.append(61 << 2)
                out.append(UInt8(n & 0xFF))
                out.append(UInt8(n >> 8))
            }
            out.append(contentsOf: bytes[start..<(start + chunk)])
            start += chunk
        }
    }

    private static func emitCopy(offset: Int, length: Int, into out: inout [UInt8]) {
        var length = length
        // Prefer the compact 1-byte-offset form where it applies (4–11 byte
        // matches within 2 KiB), otherwise 2-byte-offset ops of up to 64 bytes.
        while length > 0 {
            if length >= 4 && length <= 11 && offset < 2048 {
                out.append(0x01 | UInt8((length - 4) << 2) | UInt8((offset >> 8) << 5))
                out.append(UInt8(offset & 0xFF))
                return
            }
            let chunk = min(length, 64)
            // Avoid leaving a tail shorter than 4 that the 1-byte form
            // can't represent — not required for 2-byte ops, but emitting a
            // 1-byte trailing copy is wasteful; just fold it in.
            out.append(0x02 | UInt8((chunk - 1) << 2))
            out.append(UInt8(offset & 0xFF))
            out.append(UInt8(offset >> 8))
            length -= chunk
        }
    }
}

/// Apple's IWA chunk framing: a sequence of `[type: UInt8 = 0x00,
/// length: UInt24 little-endian]` headers, each followed by `length` bytes
/// of raw Snappy data. Uncompressed chunk payloads are ~64 KiB.
public enum IWA {

    public static func decompress(_ input: Data) throws -> Data {
        let bytes = [UInt8](input)
        var pos = 0
        var out = Data()
        while pos < bytes.count {
            guard pos + 4 <= bytes.count else { throw SnappyError.truncated }
            let chunkType = bytes[pos]
            guard chunkType == 0x00 else { throw SnappyError.unsupportedChunkType(chunkType) }
            let chunkLength = Int(bytes[pos + 1])
                | Int(bytes[pos + 2]) << 8
                | Int(bytes[pos + 3]) << 16
            pos += 4
            guard pos + chunkLength <= bytes.count else { throw SnappyError.truncated }
            out += try Snappy.decompress(Data(bytes[pos..<(pos + chunkLength)]))
            pos += chunkLength
        }
        return out
    }

    public static func compress(_ input: Data) -> Data {
        var out = Data()
        var offset = 0
        let chunkSize = 1 << 16
        repeat {
            let end = min(offset + chunkSize, input.count)
            let compressed = Snappy.compress(input.subdata(in: input.startIndex.advanced(by: offset)..<input.startIndex.advanced(by: end)))
            out.append(0x00)
            out.append(UInt8(compressed.count & 0xFF))
            out.append(UInt8((compressed.count >> 8) & 0xFF))
            out.append(UInt8((compressed.count >> 16) & 0xFF))
            out.append(compressed)
            offset = end
        } while offset < input.count
        return out
    }
}
