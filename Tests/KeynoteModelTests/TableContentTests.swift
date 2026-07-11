import Foundation
import Testing
@testable import KeynoteModel

@Suite("Table cells")
struct TableContentTests {

    static var fixtureURL: URL {
        Bundle.module.url(forResource: "Fixtures/tabledeck", withExtension: "key")!
    }

    private func tableNodeID(_ document: KeynoteDocument) throws -> UInt64 {
        try #require(
            try document.sceneTree(forSlideAt: 0).nodes.first { $0.type == "table" }?.id
        )
    }

    private func writeAndReread(_ document: KeynoteDocument) throws -> KeynoteDocument {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("table-\(UUID().uuidString).key")
        try document.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try KeynoteDocument(contentsOf: url)
    }

    @Test("reads the cell grid with text and numbers")
    func readsCells() throws {
        let document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        let cells = try document.tableCells(try tableNodeID(document))
        #expect(cells == [
            ["Product", "Units", "Revenue"],
            ["Widget", "1200", "24000"],
            ["Gadget", "800", "56000"],
        ])
    }

    @Test("table nodes surface their cells in the scene tree")
    func cellsInTree() throws {
        let document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        let table = try #require(
            try document.sceneTree(forSlideAt: 0).nodes.first { $0.type == "table" }
        )
        #expect(table.cells?[0][0] == "Product")
        #expect(table.frame != nil)
    }

    @Test("sets text and number cells, surviving a write/read cycle")
    func editCells() throws {
        var document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        let node = try tableNodeID(document)
        try document.setTableCellText(node, row: 1, column: 0, to: "Doohickey")
        try document.setTableCellNumber(node, row: 2, column: 2, to: 99500.75)
        try document.setTableCellNumber(node, row: 1, column: 1, to: -42)
        try document.setTableCellText(node, row: 2, column: 0, to: "Widget") // reuse dropped string

        let reread = try writeAndReread(document)
        let cells = try reread.tableCells(try tableNodeID(reread))
        #expect(cells[1][0] == "Doohickey")
        #expect(cells[2][2] == "99500.75")
        #expect(cells[1][1] == "-42")
        #expect(cells[2][0] == "Widget")
        // Untouched cells survive the row rebuilds.
        #expect(cells[0] == ["Product", "Units", "Revenue"])
    }

    @Test("out-of-range cells are rejected")
    func outOfRange() throws {
        var document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        let node = try tableNodeID(document)
        #expect(throws: TableError.self) {
            try document.setTableCellText(node, row: 9, column: 0, to: "x")
        }
    }

    @Test("reconciler applies cell edits from an edited tree")
    func reconcileCells() throws {
        var document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        var tree = try document.sceneTree(forSlideAt: 0)
        for index in tree.nodes.indices where tree.nodes[index].type == "table" {
            tree.nodes[index].cells?[0][0] = "Item"
            tree.nodes[index].cells?[1][2] = "31500"
        }
        try document.apply(tree)

        let reread = try writeAndReread(document)
        let cells = try reread.tableCells(try tableNodeID(reread))
        #expect(cells[0][0] == "Item")
        #expect(cells[1][2] == "31500")
    }
}
