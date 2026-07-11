import Foundation
import ZIPFoundation

public enum KeyArchiveError: Error {
    case notAZipFile(URL)
    case entryReadFailed(String)
}

/// A .key file at the zip level: ordered entries, contents untouched.
/// `Index/*.iwa` entries can be decoded further via `IWA`/`IWAFile`.
public struct KeyArchive {
    public struct Entry {
        public let path: String
        public var data: Data

        public init(path: String, data: Data) {
            self.path = path
            self.data = data
        }

        public var isIWA: Bool { path.hasSuffix(".iwa") }
    }

    public var entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    public var iwaEntries: [Entry] { entries.filter(\.isIWA) }

    // MARK: Reading

    public static func read(from url: URL) throws -> KeyArchive {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw KeyArchiveError.notAZipFile(url)
        }
        var entries: [Entry] = []
        for entry in archive where entry.type == .file {
            var data = Data()
            do {
                _ = try archive.extract(entry, skipCRC32: false) { chunk in
                    data.append(chunk)
                }
            } catch {
                throw KeyArchiveError.entryReadFailed(entry.path)
            }
            entries.append(Entry(path: entry.path, data: data))
        }
        return KeyArchive(entries: entries)
    }

    // MARK: Writing

    /// Writes entries as a zip. Entries are stored uncompressed, matching
    /// Keynote's own output (.iwa content is already Snappy-compressed).
    public func write(to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let archive = try Archive(url: url, accessMode: .create)
        for entry in entries {
            let data = entry.data
            try archive.addEntry(
                with: entry.path,
                type: .file,
                uncompressedSize: Int64(data.count),
                compressionMethod: .none
            ) { position, size in
                let start = Int(position)
                return data.subdata(in: start..<(start + size))
            }
        }
    }

    // MARK: Convenience

    public func entry(at path: String) -> Entry? {
        entries.first { $0.path == path }
    }

    public mutating func replaceEntry(at path: String, with data: Data) {
        guard let index = entries.firstIndex(where: { $0.path == path }) else { return }
        entries[index].data = data
    }
}
