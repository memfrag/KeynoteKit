import Foundation
import KeynoteSchemas

/// Lightweight structural checks, useful as a graph lint before handing a
/// document to Keynote.
extension KeynoteDocument {

    /// Whether every registered data blob has a distinct content digest.
    ///
    /// Keynote's persistence layer aborts on open if two `DataInfo` entries
    /// share a SHA-1 digest, so image operations dedup by digest; this
    /// verifies that invariant holds for the whole document.
    public func dataDigestsAreUnique() throws -> Bool {
        let location = try locateRecord(type: 11006, orThrow: MediaOperationError.packageMetadataNotFound)
        let metadata = try components[location.component].records[location.record].decode(TSP_PackageMetadata.self)
        var seen = Set<Data>()
        for data in metadata.datas where !data.digest.isEmpty {
            if !seen.insert(data.digest).inserted { return false }
        }
        return true
    }
}
