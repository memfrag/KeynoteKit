import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import IWAContainer
import KeynoteSchemas

public enum MediaOperationError: Error {
    case dataEntryNotFound(String)
    case dataInfoNotFound(String)
    case documentMetadataNotFound
    case packageMetadataNotFound
}

/// Media (image/movie data) replacement.
///
/// Every `Data/` file is registered in `TSP.PackageMetadata.datas` as a
/// `DataInfo` whose `digest` is the SHA-1 of the file bytes, and mirrored in
/// `TSP.DocumentMetadata.data_properties_v1` (a digest list with
/// `expects_matched_digest`). Replacing media in place — same data
/// identifier, same file name — keeps every `TSP.DataReference` valid; only
/// the bytes, digests, and lengths change.
extension KeynoteDocument {

    /// Replaces one `Data/` file's bytes and updates digest bookkeeping.
    /// `fileName` is the name inside `Data/`, e.g. `"red-9075.png"`.
    public mutating func replaceMediaFile(named fileName: String, with newData: Data) throws {
        let path = "Data/" + fileName
        guard let oldData = dataForEntry(at: path) else {
            throw MediaOperationError.dataEntryNotFound(fileName)
        }
        let oldDigest = Data(Insecure.SHA1.hash(data: oldData))
        let newDigest = Data(Insecure.SHA1.hash(data: newData))
        replaceEntryData(at: path, with: newData)

        // PackageMetadata: the DataInfo for this file.
        let metadataLocation = try locateRecord(type: 11006, orThrow: MediaOperationError.packageMetadataNotFound)
        var metadataRecord = components[metadataLocation.component].records[metadataLocation.record]
        var metadata = try metadataRecord.decode(TSP_PackageMetadata.self)
        guard let dataIndex = metadata.datas.firstIndex(where: {
            $0.fileName == fileName || $0.digest == oldDigest
        }) else {
            throw MediaOperationError.dataInfoNotFound(fileName)
        }
        metadata.datas[dataIndex].digest = newDigest
        metadata.datas[dataIndex].materializedLength = UInt64(newData.count)
        try metadataRecord.setMessage(metadata)
        components[metadataLocation.component].records[metadataLocation.record] = metadataRecord

        // DocumentMetadata: the parallel digest list.
        let documentMetadataLocation = try locateRecord(type: 11011, orThrow: MediaOperationError.documentMetadataNotFound)
        var documentMetadataRecord = components[documentMetadataLocation.component].records[documentMetadataLocation.record]
        var documentMetadata = try documentMetadataRecord.decode(TSP_DocumentMetadata.self)
        for index in documentMetadata.dataPropertiesV1.properties.indices
        where documentMetadata.dataPropertiesV1.properties[index].digest == oldDigest {
            documentMetadata.dataPropertiesV1.properties[index].digest = newDigest
        }
        try documentMetadataRecord.setMessage(documentMetadata)
        components[documentMetadataLocation.component].records[documentMetadataLocation.record] = documentMetadataRecord
    }

    /// Replaces an image by its original (preferred) file name, e.g.
    /// `"red.png"`, updating both the full-size data and any Keynote-generated
    /// `-small-` preview variant. The preview is re-rendered from the new
    /// image at the old preview's pixel size — never byte-identical to the
    /// full-size data, because two `DataInfo` entries sharing one digest
    /// violates the persistence layer's dedup invariant and crashes Keynote.
    /// The replacement should have the same pixel dimensions as the original
    /// (the drawable's geometry and stored natural size are unchanged).
    /// Returns the `Data/` file names that were replaced.
    @discardableResult
    public mutating func replaceImage(named preferredFileName: String, with newData: Data) throws -> [String] {
        let metadataLocation = try locateRecord(type: 11006, orThrow: MediaOperationError.packageMetadataNotFound)
        let metadata = try components[metadataLocation.component]
            .records[metadataLocation.record]
            .decode(TSP_PackageMetadata.self)

        let stem = (preferredFileName as NSString).deletingPathExtension
        let ext = (preferredFileName as NSString).pathExtension
        let previewName = ext.isEmpty ? "\(stem)-small" : "\(stem)-small.\(ext)"

        guard let main = metadata.datas.first(where: {
            !$0.fileName.isEmpty && $0.preferredFileName == preferredFileName
        }) else {
            throw MediaOperationError.dataInfoNotFound(preferredFileName)
        }
        try replaceMediaFile(named: main.fileName, with: newData)
        var replaced = [main.fileName]

        if let preview = metadata.datas.first(where: {
            !$0.fileName.isEmpty && $0.preferredFileName == previewName
        }),
            let oldPreview = dataForEntry(at: "Data/" + preview.fileName),
            let scaled = Self.imageData(newData, scaledToMatch: oldPreview) {
            try replaceMediaFile(named: preview.fileName, with: scaled)
            replaced.append(preview.fileName)
        }
        return replaced
    }

    /// Renders `data` at the pixel size and container format of `original`.
    private static func imageData(_ data: Data, scaledToMatch original: Data) -> Data? {
        guard let originalSource = CGImageSourceCreateWithData(original as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(originalSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let type = CGImageSourceGetType(originalSource),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, scaled, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Names of all files under `Data/`.
    public var mediaFileNames: [String] {
        entryPaths.filter { $0.hasPrefix("Data/") }.map { String($0.dropFirst("Data/".count)) }
    }
}
