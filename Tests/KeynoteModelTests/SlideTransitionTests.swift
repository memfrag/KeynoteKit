import Foundation
import Testing
@testable import KeynoteModel

@Suite("Slide transitions")
struct SlideTransitionTests {

    static var fixtureURL: URL {
        Bundle.module.url(forResource: "Fixtures/transdeck", withExtension: "key")!
    }

    private func writeAndReread(_ document: KeynoteDocument) throws -> KeynoteDocument {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transition-\(UUID().uuidString).key")
        try document.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try KeynoteDocument(contentsOf: url)
    }

    @Test("reads Keynote-authored transitions")
    func reads() throws {
        let document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        let first = try #require(try document.slideTransition(at: 0))
        #expect(first.effect == "apple:dissolve")
        #expect(first.duration == 2.0)
        let second = try #require(try document.slideTransition(at: 1))
        #expect(second.effect == "apple:3D-cube")
        // The last slide has no transition ("none").
        #expect(try document.slideTransition(at: 2) == nil)
    }

    @Test("sets and removes transitions")
    func setAndRemove() throws {
        var document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        try document.setSlideTransition(
            at: 2, to: SlideTransition(effect: "apple:push", duration: 1.25)
        )
        try document.setSlideTransition(at: 0, to: nil)

        let reread = try writeAndReread(document)
        let added = try #require(try reread.slideTransition(at: 2))
        #expect(added.effect == "apple:push")
        #expect(added.duration == 1.25)
        #expect(try reread.slideTransition(at: 0) == nil)
        // Slide 1 untouched.
        #expect(try reread.slideTransition(at: 1)?.effect == "apple:3D-cube")
    }

    @Test("reconciler applies transition edits from the tree")
    func reconcile() throws {
        var document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        var tree = try document.sceneTree(forSlideAt: 2)
        #expect(tree.transition == nil)
        tree.transition = SlideTransition(effect: "apple:wipe", duration: 0.75)
        try document.apply(tree)

        let reread = try writeAndReread(document)
        #expect(try reread.slideTransition(at: 2)?.effect == "apple:wipe")
    }
}
