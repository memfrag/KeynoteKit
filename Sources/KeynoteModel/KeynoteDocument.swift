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
            output.setEntry(at: component.path, data: IWA.compress(file.serialize()))
        }
        try output.write(to: url)
    }

    // MARK: Component management

    /// Adds a new .iwa component (e.g. a cloned slide). Its zip entry is
    /// placed after `anchor`'s when given, and its records are serialized
    /// on the next `write`.
    public mutating func addComponent(path: String, records: [ObjectRecord], after anchor: String? = nil) {
        archive.setEntry(at: path, data: Data(), after: anchor)
        let component = Component(path: path, records: records)
        if let anchor, let index = components.firstIndex(where: { $0.path == anchor }) {
            components.insert(component, at: index + 1)
        } else {
            components.append(component)
        }
    }

    public mutating func removeComponent(path: String) {
        archive.removeEntry(at: path)
        components.removeAll { $0.path == path }
    }

    // MARK: Archive entries

    public var entryPaths: [String] {
        archive.entries.map(\.path)
    }

    public func dataForEntry(at path: String) -> Data? {
        archive.entry(at: path)?.data
    }

    public mutating func replaceEntryData(at path: String, with data: Data) {
        archive.replaceEntry(at: path, with: data)
    }

    /// Replaces the entry if present, otherwise appends it (used when adding
    /// new media files).
    public mutating func setEntryData(at path: String, to data: Data) {
        archive.setEntry(at: path, data: data)
    }

    // MARK: Lookup

    struct RecordLocation {
        let component: Int
        let record: Int
    }

    /// Locates the first record with the given primary message type.
    func locateRecord(type: UInt32, orThrow error: any Error) throws -> RecordLocation {
        for (componentIndex, component) in components.enumerated() {
            if let recordIndex = component.records.firstIndex(where: { $0.primaryType == type }) {
                return RecordLocation(component: componentIndex, record: recordIndex)
            }
        }
        throw error
    }

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
