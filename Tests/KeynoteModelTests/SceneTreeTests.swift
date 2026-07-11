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

    // MARK: Cloning

    @Test("cloneDrawable copies a node across slides with fresh identifiers")
    func cloneAcrossSlides() throws {
        var document = try KeynoteDocument(contentsOf: Self.twoSlideURL)
        // The title slide has a text shape (author/date line) we can clone.
        let source = try #require(
            try document.sceneTree(forSlideAt: 0).nodes.first { $0.type == "shape" }
        )
        let newID = try document.cloneDrawable(source.id, toSlideAt: 1)
        #expect(newID != source.id)

        let reread = try writeAndReread(document)
        let tree = try reread.sceneTree(forSlideAt: 1)
        let clone = try #require(tree.nodes.first { $0.id == newID })
        #expect(clone.type == "shape")
        #expect(clone.text == source.text)
        #expect(clone.frame == source.frame)

        // Identifiers stay unique document-wide.
        var seen: Set<UInt64> = []
        for component in reread.components {
            for record in component.records {
                if let id = record.identifier {
                    #expect(!seen.contains(id), "duplicate id \(id)")
                    seen.insert(id)
                }
            }
        }
    }

    @Test("replacing a cloned image's media does not disturb the original")
    func cloneImageIndependentMedia() throws {
        var document = try KeynoteDocument(contentsOf: Self.imageDeckURL)
        let source = try #require(
            try document.sceneTree(forSlideAt: 0).nodes.first { $0.type == "image" }
        )
        let originalFile = try #require(source.media?.file)
        let originalBytes = try #require(document.dataForEntry(at: "Data/" + originalFile))

        // Clone the image (the clone shares the source's data), then give the
        // clone new content.
        let cloneID = try document.cloneDrawable(source.id, toSlideAt: 0)
        let blue = try Data(contentsOf: Self.blueImageURL)
        try document.setNodeMedia(cloneID, to: blue)

        let reread = try writeAndReread(document)
        let nodes = try reread.sceneTree(forSlideAt: 0).nodes
        let originalNode = try #require(nodes.first { $0.id == source.id })
        let cloneNode = try #require(nodes.first { $0.id == cloneID })

        // The clone points at fresh data with the new bytes…
        let cloneFile = try #require(cloneNode.media?.file)
        #expect(reread.dataForEntry(at: "Data/" + cloneFile) == blue)
        // …and the original is byte-for-byte unchanged.
        let originalNodeFile = try #require(originalNode.media?.file)
        #expect(reread.dataForEntry(at: "Data/" + originalNodeFile) == originalBytes)
        #expect(cloneFile != originalNodeFile)
    }

    @Test("apply() adds nodes via cloneOf with edits applied to the clone")
    func reconcileCloneOf() throws {
        var document = try KeynoteDocument(contentsOf: Self.twoSlideURL)
        let source = try #require(
            try document.sceneTree(forSlideAt: 0).nodes.first { $0.type == "shape" }
        )
        var tree = try document.sceneTree(forSlideAt: 1)
        let frame = Frame(x: 50, y: 60, width: 700, height: 80)
        tree.nodes.append(SceneNode(
            id: 0, type: "shape", text: "Added by reconciler", frame: frame, cloneOf: source.id
        ))
        try document.apply(tree)

        let reread = try writeAndReread(document)
        let clone = try #require(
            try reread.sceneTree(forSlideAt: 1).nodes.first { $0.text == "Added by reconciler" }
        )
        #expect(clone.frame == frame)
        #expect(clone.id != source.id)
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
