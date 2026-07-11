import Foundation
import Testing
@testable import KeynoteModel

@Suite("Chart data")
struct ChartContentTests {

    static var fixtureURL: URL {
        Bundle.module.url(forResource: "Fixtures/chartdeck", withExtension: "key")!
    }

    private func chartNodeID(_ document: KeynoteDocument) throws -> UInt64 {
        try #require(
            try document.sceneTree(forSlideAt: 0).nodes.first { $0.type == "chart" }?.id
        )
    }

    private func writeAndReread(_ document: KeynoteDocument) throws -> KeynoteDocument {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chart-\(UUID().uuidString).key")
        try document.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try KeynoteDocument(contentsOf: url)
    }

    @Test("reads the data grid")
    func reads() throws {
        let document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        let data = try document.chartData(try chartNodeID(document))
        #expect(data.rowNames == ["Q1", "Q2", "Q3"])
        #expect(data.columnNames == ["Revenue", "Costs"])
        #expect(data.values == [[100, 60], [150, 80], [210, 95]])
    }

    @Test("replaces the grid, including its dimensions")
    func replaces() throws {
        var document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        let node = try chartNodeID(document)
        try document.setChartData(node, to: ChartData(
            rowNames: ["Q1", "Q2", "Q3", "Q4"],
            columnNames: ["Revenue", "Costs"],
            values: [[100, 60], [150, 80], [210, 95], [320, 110]]
        ))

        let reread = try writeAndReread(document)
        let data = try reread.chartData(try chartNodeID(reread))
        #expect(data.rowNames.count == 4)
        #expect(data.values[3] == [320, 110])
    }

    @Test("rejects mismatched dimensions")
    func rejectsMismatch() throws {
        var document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        let node = try chartNodeID(document)
        #expect(throws: ChartError.self) {
            try document.setChartData(node, to: ChartData(
                rowNames: ["A"], columnNames: ["X", "Y"], values: [[1]]
            ))
        }
    }

    @Test("reconciler applies chart edits from the tree")
    func reconcile() throws {
        var document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        var tree = try document.sceneTree(forSlideAt: 0)
        for index in tree.nodes.indices where tree.nodes[index].type == "chart" {
            tree.nodes[index].chart?.values[0] = [999, 1]
        }
        try document.apply(tree)

        let reread = try writeAndReread(document)
        let data = try reread.chartData(try chartNodeID(reread))
        #expect(data.values[0] == [999, 1])
    }
}
