import Foundation
import Testing
@testable import IWAContainer

@Suite("Raw Snappy codec")
struct SnappyTests {

    @Test("round-trips empty data")
    func emptyRoundTrip() throws {
        let compressed = Snappy.compress(Data())
        #expect(try Snappy.decompress(compressed) == Data())
    }

    @Test("round-trips short literals")
    func shortLiteral() throws {
        let input = Data("Keynote".utf8)
        #expect(try Snappy.decompress(Snappy.compress(input)) == input)
    }

    @Test("round-trips highly repetitive data and actually compresses it")
    func repetitiveData() throws {
        let input = Data(repeating: 0xAB, count: 100_000)
        let compressed = Snappy.compress(input)
        #expect(compressed.count < input.count / 10)
        #expect(try Snappy.decompress(compressed) == input)
    }

    @Test("round-trips text with mid-range matches")
    func textRoundTrip() throws {
        let text = String(repeating: "the quick brown fox jumps over the lazy dog. ", count: 500)
            + String(repeating: "pack my box with five dozen liquor jugs. ", count: 500)
        let input = Data(text.utf8)
        let compressed = Snappy.compress(input)
        #expect(compressed.count < input.count)
        #expect(try Snappy.decompress(compressed) == input)
    }

    @Test("round-trips pseudo-random data (incompressible)")
    func randomRoundTrip() throws {
        // Deterministic xorshift so failures are reproducible.
        var state: UInt64 = 0x9E3779B97F4A7C15
        var input = Data(capacity: 200_000)
        for _ in 0..<200_000 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            input.append(UInt8(truncatingIfNeeded: state))
        }
        #expect(try Snappy.decompress(Snappy.compress(input)) == input)
    }

    @Test("decodes a known reference vector")
    func referenceVector() throws {
        // "Wikipedia" spec example: literal "Wiki" + copy(offset 4, len 4) would
        // be tooling-specific; instead verify a hand-built stream:
        // varint(11), literal(len 6) "abcdef", copy1(offset 6, len 5) → "abcdefabcde"
        var stream = Data()
        stream.append(11) // uncompressed length
        stream.append(UInt8(5) << 2) // literal, length 6
        stream.append(contentsOf: Array("abcdef".utf8))
        stream.append(0x01 | UInt8((5 - 4) << 2)) // copy, 1-byte offset, len 5
        stream.append(6)
        let decoded = try Snappy.decompress(stream)
        #expect(decoded == Data("abcdefabcde".utf8))
    }

    @Test("rejects truncated input")
    func truncated() {
        var stream = Data()
        stream.append(20) // claims 20 bytes
        stream.append(UInt8(9) << 2) // literal of length 10
        stream.append(contentsOf: Array("short".utf8)) // only 5 bytes present
        #expect(throws: SnappyError.truncated) {
            _ = try Snappy.decompress(stream)
        }
    }

    @Test("rejects invalid back-reference offsets")
    func invalidOffset() {
        var stream = Data()
        stream.append(8)
        stream.append(UInt8(0) << 2) // literal, 1 byte
        stream.append(0x41)
        stream.append(0x01 | UInt8((4 - 4) << 2)) // copy len 4, offset 200 (> output so far)
        stream.append(200)
        #expect(throws: SnappyError.invalidCopyOffset) {
            _ = try Snappy.decompress(stream)
        }
    }
}

@Suite("IWA chunk framing")
struct IWAChunkTests {

    @Test("round-trips data larger than one chunk")
    func multiChunk() throws {
        let text = String(repeating: "slide content and more slide content. ", count: 8000)
        let input = Data(text.utf8) // ~300 KB → several 64 KiB chunks
        let framed = IWA.compress(input)
        #expect(framed[framed.startIndex] == 0x00)
        #expect(try IWA.decompress(framed) == input)
    }

    @Test("round-trips empty input as a single empty chunk")
    func emptyInput() throws {
        let framed = IWA.compress(Data())
        #expect(try IWA.decompress(framed).isEmpty)
    }

    @Test("rejects unknown chunk types")
    func badChunkType() {
        let framed = Data([0x01, 0x01, 0x00, 0x00, 0x00])
        #expect(throws: SnappyError.unsupportedChunkType(0x01)) {
            _ = try IWA.decompress(framed)
        }
    }
}
