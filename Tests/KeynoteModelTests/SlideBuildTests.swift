import Foundation
import Testing
@testable import KeynoteModel

@Suite("Element builds")
struct SlideBuildTests {

    static var fixtureURL: URL {
        Bundle.module.url(forResource: "Fixtures/builds", withExtension: "key")!
    }

    static var twoSlideURL: URL {
        Bundle.module.url(forResource: "Fixtures/twoslides", withExtension: "key")!
    }

    private func writeAndReread(_ document: KeynoteDocument) throws -> KeynoteDocument {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("build-\(UUID().uuidString).key")
        try document.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try KeynoteDocument(contentsOf: url)
    }

    @Test("reads Keynote-authored builds in playback order")
    func reads() throws {
        let document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        let builds = try document.slideBuilds(at: 0)
        #expect(builds.count == 2)
        #expect(builds[0].kind == "In")
        #expect(builds[0].effect == "apple:bc-appear")
        #expect(builds[1].kind == "Out")
        #expect(builds[1].effect.hasPrefix("apple:dissolve"))
        #expect(builds[0].nodeID != builds[1].nodeID)
    }

    @Test("adds a build from scratch and reads it back")
    func adds() throws {
        var document = try KeynoteDocument(contentsOf: Self.twoSlideURL)
        let shape = try #require(
            try document.sceneTree(forSlideAt: 0).nodes.first { $0.type == "shape" }
        )
        let buildID = try document.addBuild(
            SlideBuild(nodeID: shape.id, kind: "In", effect: "apple:dissolve", duration: 1.5),
            toSlideAt: 0
        )

        let reread = try writeAndReread(document)
        let builds = try reread.slideBuilds(at: 0)
        #expect(builds.count == 1)
        #expect(builds[0].id == buildID)
        #expect(builds[0].nodeID == shape.id)
        #expect(builds[0].effect == "apple:dissolve")
        #expect(builds[0].duration == 1.5)
    }

    @Test("removes a build and its chunks")
    func removes() throws {
        var document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        let first = try #require(try document.slideBuilds(at: 0).first)
        try document.removeBuild(first.id, fromSlideAt: 0)

        let reread = try writeAndReread(document)
        let builds = try reread.slideBuilds(at: 0)
        #expect(builds.count == 1)
        #expect(builds.allSatisfy { $0.id != first.id })
    }

    @Test("rejects builds targeting drawables on other slides")
    func rejectsForeignNode() throws {
        var document = try KeynoteDocument(contentsOf: Self.twoSlideURL)
        #expect(throws: BuildError.self) {
            try document.addBuild(
                SlideBuild(nodeID: 999_999, kind: "In", effect: "apple:dissolve"),
                toSlideAt: 0
            )
        }
    }
}
