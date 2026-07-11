# Tables and Charts

Read and edit table cell grids and chart data.

## Tables

A table appears in the scene tree as a `"table"` node whose `cells` grid
holds each cell's display string (`nil` for empty cells). The same grid is
available directly:

```swift
let tableID = tree.nodes.first { $0.type == "table" }!.id
let cells = try document.tableCells(tableID)
// [["Product", "Units", "Revenue"],
//  ["Widget",  "1200",  "24000"],
//  ["Gadget",  "800",   "56000"]]
```

Edit cells as text or numbers. Numbers are encoded in Keynote's own
base-10 decimal format, so they behave as real numeric cells (formatting,
locale display, chart references):

```swift
try document.setTableCellText(tableID, row: 0, column: 2, to: "Sales")
try document.setTableCellNumber(tableID, row: 2, column: 2, to: 99500.75)
```

Or edit the grid in a scene tree and apply it — changed entries that parse
as numbers become number cells, everything else becomes text:

```swift
var tree = try document.sceneTree(forSlideAt: 0)
for index in tree.nodes.indices where tree.nodes[index].type == "table" {
    tree.nodes[index].cells?[1][0] = "Doohickey"
    tree.nodes[index].cells?[1][2] = "31500"
}
try document.apply(tree)
```

Behind the scenes this decodes and rebuilds Keynote's binary tile storage
and manages the table's shared string list (interning duplicate strings,
releasing orphaned ones).

**Structure is fixed**: the row and column counts come from the table as it
exists. To generate a deck with an N-row table, keep a template slide whose
table is already sized to fit, clone it, and fill the cells.

## Charts

A chart appears as a `"chart"` node carrying a ``ChartData`` grid: row
names (categories), column names (series), and numeric values.

```swift
let chartID = tree.nodes.first { $0.type == "chart" }!.id
var data = try document.chartData(chartID)
// rowNames:    ["Q1", "Q2", "Q3"]
// columnNames: ["Revenue", "Costs"]
// values:      [[100, 60], [150, 80], [210, 95]]
```

Unlike tables, a chart's grid may be replaced wholesale — including
changing its dimensions; Keynote lays the chart out from the new data:

```swift
data.rowNames.append("Q4")
data.values.append([320, 110])
try document.setChartData(chartID, to: data)
```

`values` must be `rowNames.count × columnNames.count`; a `nil` value leaves
that point empty. The chart's type and styling are untouched — to get a
different chart type, template it: author the chart you want in Keynote,
then replace its data programmatically.

Charts are also editable through the reconciler via the node's `chart`
field, exactly like table `cells`.
