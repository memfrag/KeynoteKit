import Foundation
import Testing
@testable import KeynoteModel
import KeynoteSchemas

@Suite("ReferenceRewriter against real payloads")
struct ReferenceRewriterTests {

    static var fixtureURL: URL {
        Bundle.module.url(forResource: "Fixtures/basic", withExtension: "key")!
    }

    @Test("identity rewrite is byte-stable for every record in the fixture")
    func identityRewriteIsStable() throws {
        let document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        var checked = 0
        for component in document.components {
            for record in component.records {
                for (index, info) in record.info.messageInfos.enumerated() {
                    guard let typeName = TSPRegistry.protoNames[info.type] else { continue }
                    let rewritten = try ReferenceRewriter.rewrite(
                        record.payloads[index], typeName: typeName, using: [:]
                    )
                    #expect(
                        rewritten == record.payloads[index],
                        "identity rewrite changed bytes: \(component.path) id \(record.identifier ?? 0) type \(info.type)"
                    )
                    checked += 1
                }
            }
        }
        #expect(checked > 600)
    }

    /// Every reference Keynote declares in `object_references` must be found
    /// by the walker — a missed one would survive cloning un-remapped. The
    /// walker may legitimately find MORE (parent back-references like a
    /// style's stylesheet, which Keynote excludes from its bookkeeping).
    @Test("walker finds every reference declared in object_references")
    func collectCoversObjectReferences() throws {
        let document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        for component in document.components {
            for record in component.records {
                for (index, info) in record.info.messageInfos.enumerated() {
                    guard let typeName = TSPRegistry.protoNames[info.type] else { continue }
                    let collected = Set(try ReferenceRewriter.collectReferences(
                        in: record.payloads[index], typeName: typeName
                    ))
                    let declared = Set(info.objectReferences)
                    #expect(
                        declared.subtracting(collected).isEmpty,
                        "\(component.path) id \(record.identifier ?? 0) type \(info.type) (\(typeName)): walker missed \(declared.subtracting(collected).sorted())"
                    )
                }
            }
        }
    }
}
