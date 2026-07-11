import CryptoKit
import Foundation
import Testing
@testable import KeynoteModel

@Suite("Scene tree")
struct SceneTreeTests {

    static var twoSlideURL: URL {
        Bundle.module.url(forResource: "Fixtures/twoslides", withExtension: "key")!
    }

    static var imageDeckURL: URL {
        Bundle.module.url(forResource: "Fixtures/imagedeck", withExtension: "key")!
    }

    static var blueImageURL: URL {
        Bundle.module.url(forResource: "Fixtures/blue", withExtension: "png")!
    }

    private func writeAndReread(_ document: KeynoteDocument) throws -> KeynoteDocument {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scene-\(UUID().uuidString).key")
        try document.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try KeynoteDocument(contentsOf: url)
    }

    // MARK: Reading

    @Test("reads placeholders with roles, prompts, and authored text")
    func readsPlaceholders() throws {
        let document = try KeynoteDocument(contentsOf: Self.twoSlideURL)
        let tree = try document.sceneTree(forSlideAt: 0)
        #expect(tree.master != nil)

        let title = try #require(tree.nodes.first { $0.role == "title" })
        #expect(title.type == "placeholder")
        #expect(title.text == "First")
        #expect(title.frame != nil)

        // Node ids are unique across the tree.
        var seen: Set<UInt64> = []
        for node in tree.nodes {
            #expect(!seen.contains(node.id))
            seen.insert(node.id)
        }
    }

    @Test("reads image nodes with media references")
    func readsImages() throws {
        let document = try KeynoteDocument(contentsOf: Self.imageDeckURL)
        let tree = try document.sceneTree(forSlideAt: 0)
        let image = try #require(tree.nodes.first { $0.type == "image" })
        let media = try #require(image.media)
        #expect(media.file == "red-9075.png")
        #expect(image.frame != nil)
    }

    // MARK: Commands

    @Test("setNodeText targets a specific node")
    func setText() throws {
        var document = try KeynoteDocument(contentsOf: Self.twoSlideURL)
        let title = try #require(try document.sceneTree(forSlideAt: 1).nodes.first { $0.role == "title" })
        try document.setNodeText(title.id, to: "Node-addressed")

        let reread = try writeAndReread(document)
        #expect(try reread.slideTitle(at: 1) == "Node-addressed")
        #expect(try reread.slideTitle(at: 0) == "First")
    }

    @Test("setNodeFrame moves a drawable")
    func setFrame() throws {
        var document = try KeynoteDocument(contentsOf: Self.imageDeckURL)
        let image = try #require(try document.sceneTree(forSlideAt: 0).nodes.first { $0.type == "image" })
        let frame = Frame(x: 10, y: 20, width: 300, height: 200)
        try document.setNodeFrame(image.id, to: frame)

        let reread = try writeAndReread(document)
        let updated = try #require(try reread.sceneTree(forSlideAt: 0).nodes.first { $0.id == image.id })
        #expect(updated.frame == frame)
    }

    @Test("setNodeMedia replaces a materialized image in place")
    func setMedia() throws {
        var document = try KeynoteDocument(contentsOf: Self.imageDeckURL)
        let blue = try Data(contentsOf: Self.blueImageURL)
        let image = try #require(try document.sceneTree(forSlideAt: 0).nodes.first { $0.type == "image" })
        try document.setNodeMedia(image.id, to: blue)

        let reread = try writeAndReread(document)
        let updated = try #require(try reread.sceneTree(forSlideAt: 0).nodes.first { $0.id == image.id })
        let file = try #require(updated.media?.file)
        #expect(reread.dataForEntry(at: "Data/" + file) == blue)
    }

    @Test("deleteDrawable removes the node and slide bookkeeping")
    func deleteNode() throws {
        var document = try KeynoteDocument(contentsOf: Self.imageDeckURL)
        let image = try #require(try document.sceneTree(forSlideAt: 0).nodes.first { $0.type == "image" })
        try document.deleteDrawable(image.id)

        let reread = try writeAndReread(document)
        #expect(try reread.sceneTree(forSlideAt: 0).nodes.allSatisfy { $0.id != image.id })
    }

    @Test("placeholders can't be deleted")
    func placeholderDeletionRefused() throws {
        var document = try KeynoteDocument(contentsOf: Self.twoSlideURL)
        let title = try #require(try document.sceneTree(forSlideAt: 0).nodes.first { $0.role == "title" })
        #expect(throws: SceneEditError.self) {
            try document.deleteDrawable(title.id)
        }
    }

    // MARK: Reconciler

    @Test("apply() reconciles text, frame, notes, and deletion edits")
    func reconcile() throws {
        var document = try KeynoteDocument(contentsOf: Self.imageDeckURL)
        var tree = try document.sceneTree(forSlideAt: 0)

        let imageID = try #require(tree.nodes.first { $0.type == "image" }?.id)
        for index in tree.nodes.indices {
            if tree.nodes[index].role == "title" {
                tree.nodes[index].text = "Reconciled title"
            }
        }
        tree.nodes.removeAll { $0.id == imageID }
        tree.notes = "Reconciled notes"
        try document.apply(tree)

        let reread = try writeAndReread(document)
        let updated = try reread.sceneTree(forSlideAt: 0)
        #expect(updated.nodes.first { $0.role == "title" }?.text == "Reconciled title")
        #expect(updated.nodes.allSatisfy { $0.id != imageID })
        #expect(updated.notes == "Reconciled notes")
    }

    @Test("apply() rejects unknown nodes")
    func reconcileRejectsUnknown() throws {
        var document = try KeynoteDocument(contentsOf: Self.twoSlideURL)
        var tree = try document.sceneTree(forSlideAt: 0)
        tree.nodes.append(SceneNode(id: 999_999_999, type: "shape"))
        #expect(throws: SceneEditError.self) {
            try document.apply(tree)
        }
    }

    @Test("apply() replaces media via the media dictionary")
    func reconcileMedia() throws {
        var document = try KeynoteDocument(contentsOf: Self.imageDeckURL)
        let blue = try Data(contentsOf: Self.blueImageURL)
        let tree = try document.sceneTree(forSlideAt: 0)
        let imageID = try #require(tree.nodes.first { $0.type == "image" }?.id)
        try document.apply(tree, media: [imageID: blue])

        let reread = try writeAndReread(document)
        let updated = try #require(try reread.sceneTree(forSlideAt: 0).nodes.first { $0.id == imageID })
        let file = try #require(updated.media?.file)
        #expect(reread.dataForEntry(at: "Data/" + file) == blue)
    }
}
