import Foundation
import IWAContainer
import KeynoteSchemas
import SwiftProtobuf

/// A .key file with every `Index/*.iwa` component parsed into typed records.
/// Non-IWA entries (media, metadata) pass through untouched.
public struct KeynoteDocument {
    public struct Component {
        public let path: String
        public var records: [ObjectRecord]
    }

    private var archive: KeyArchive
    public var components: [Component]

    public init(contentsOf url: URL) throws {
        self.archive = try KeyArchive.read(from: url)
        self.components = try archive.iwaEntries.map { entry in
            let decompressed = try IWA.decompress(entry.data)
            let file = try IWAFile.parse(decompressed)
            return Component(path: entry.path, records: try file.records.map(ObjectRecord.init))
        }
    }

    public func write(to url: URL) throws {
        var output = archive
        for component in components {
            let file = IWAFile(records: try component.records.map { try $0.lowered() })
            output.replaceEntry(at: component.path, with: IWA.compress(file.serialize()))
        }
        try output.write(to: url)
    }

    // MARK: Lookup

    /// Visits every record of a given message type across all components.
    /// The `body` closure returns a mutated record to store back, or nil to
    /// leave it unchanged.
    public mutating func forEachRecord(
        ofType typeID: UInt32,
        _ body: (ObjectRecord) throws -> ObjectRecord?
    ) rethrows {
        for c in components.indices {
            for r in components[c].records.indices where components[c].records[r].primaryType == typeID {
                if let updated = try body(components[c].records[r]) {
                    components[c].records[r] = updated
                }
            }
        }
    }

    public func record(withIdentifier identifier: UInt64) -> ObjectRecord? {
        for component in components {
            if let record = component.records.first(where: { $0.identifier == identifier }) {
                return record
            }
        }
        return nil
    }
}
