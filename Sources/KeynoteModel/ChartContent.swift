import Foundation
import IWAContainer
import KeynoteSchemas
import SwiftProtobuf

public enum ChartError: Error {
    case notAChart(UInt64)
    case noChartData(UInt64)
    case dimensionMismatch(String)
}

/// A chart's data grid: values are `values[row][column]`, with `rowNames`
/// labeling the categories and `columnNames` the series (for a standard
/// bar/line/area chart).
public struct ChartData: Codable, Equatable, Sendable {
    public var rowNames: [String]
    public var columnNames: [String]
    public var values: [[Double?]]

    public init(rowNames: [String], columnNames: [String], values: [[Double?]]) {
        self.rowNames = rowNames
        self.columnNames = columnNames
        self.values = values
    }
}

/// Chart data reading and editing.
///
/// A chart drawable (`TSCH.ChartDrawableArchive`, type 5021) carries its
/// model as the `TSCH.ChartArchive` extension (field 10000, "unity"), whose
/// `grid` holds row names, column names, and numeric values directly —
/// unlike tables, no external tiles are involved.
extension KeynoteDocument {

    public func chartData(_ nodeID: UInt64) throws -> ChartData {
        let (_, chart) = try chartArchive(nodeID)
        guard chart.hasGrid else { throw ChartError.noChartData(nodeID) }
        return ChartData(
            rowNames: chart.grid.rowName,
            columnNames: chart.grid.columnName,
            values: chart.grid.gridRow.map { row in
                row.value.map { $0.hasNumericValue ? $0.numericValue : nil }
            }
        )
    }

    /// Replaces the chart's data grid. The number of rows and columns may
    /// change; Keynote lays the chart out from the new grid.
    public mutating func setChartData(_ nodeID: UInt64, to data: ChartData) throws {
        guard data.values.count == data.rowNames.count,
              data.values.allSatisfy({ $0.count == data.columnNames.count })
        else {
            throw ChartError.dimensionMismatch(
                "values must be rowNames.count x columnNames.count"
            )
        }
        let (location, chart) = try chartArchive(nodeID)
        var updated = chart
        updated.grid.rowName = data.rowNames
        updated.grid.columnName = data.columnNames
        updated.grid.gridRow = data.values.map { row in
            TSCH_GridRow.with {
                $0.value = row.map { value in
                    TSCH_GridValue.with {
                        if let value { $0.numericValue = value }
                    }
                }
            }
        }
        // Row/column UUID maps describe a grid we just replaced wholesale;
        // stale entries confuse Keynote's model, so drop them.
        updated.grid.clearIDMap()

        var record = components[location.component].records[location.record]
        var drawable = try decodeChartDrawable(record)
        drawable.TSCH_ChartArchive_unity = updated
        try record.setMessage(drawable)
        components[location.component].records[location.record] = record
    }

    // MARK: Plumbing

    private func chartArchive(_ nodeID: UInt64) throws -> (RecordLocation, TSCH_ChartArchive) {
        let location = try locateSceneNode(nodeID)
        let record = components[location.component].records[location.record]
        guard record.primaryType == 5021 else { throw ChartError.notAChart(nodeID) }
        let drawable = try decodeChartDrawable(record)
        guard drawable.hasTSCH_ChartArchive_unity else { throw ChartError.noChartData(nodeID) }
        return (location, drawable.TSCH_ChartArchive_unity)
    }

    /// Chart drawables must be decoded with the TSCH extension map so the
    /// field-10000 chart model becomes typed instead of an unknown field.
    private func decodeChartDrawable(_ record: ObjectRecord) throws -> TSCH_ChartDrawableArchive {
        try TSCH_ChartDrawableArchive(
            serializedBytes: record.payloads[0],
            extensions: TSCH_Tscharchives_Extensions
        )
    }
}
