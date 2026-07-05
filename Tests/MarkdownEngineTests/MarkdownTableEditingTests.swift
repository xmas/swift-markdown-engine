//
//  MarkdownTableEditingTests.swift
//  MarkdownEngineTests
//

import Testing
@testable import MarkdownEngine

@Suite("Markdown table source editing")
struct MarkdownTableEditingTests {

    @Test func parsesAndSerializesTableSource() {
        let table = MarkdownTable.parse("""
        | Name | Count |
        | :--- | ---: |
        | Alpha | 1 |
        """)

        #expect(table?.header == ["Name", "Count"])
        #expect(table?.alignments == [.left, .right])
        #expect(table?.rows == [["Alpha", "1"]])
        #expect(table?.serialized() == """
        | Name | Count |
        | --- | ---: |
        | Alpha | 1 |
        """)
    }

    @Test func movesRowsAndColumns() {
        var table = MarkdownTable(
            header: ["A", "B", "C"],
            alignments: [.left, .center, .right],
            rows: [["a1", "b1", "c1"], ["a2", "b2", "c2"]]
        )

        let movedRow = table.moveRow(from: 1, to: 0)
        #expect(movedRow)
        #expect(table.rows == [["a2", "b2", "c2"], ["a1", "b1", "c1"]])

        let movedColumn = table.moveColumn(from: 2, to: 0)
        #expect(movedColumn)
        #expect(table.header == ["C", "A", "B"])
        #expect(table.alignments == [.right, .left, .center])
        #expect(table.rows == [["c2", "a2", "b2"], ["c1", "a1", "b1"]])
    }

    @Test func insertsAndRemovesRowsAndColumns() {
        var table = MarkdownTable(header: ["A"], alignments: [.left], rows: [["a1"]])

        let insertedColumn = table.insertColumn(at: 1, header: "B", alignment: .center, cells: ["b1"])
        let insertedRow = table.insertRow(at: 1, cells: ["a2", "b2"])
        #expect(insertedColumn)
        #expect(insertedRow)
        #expect(table.header == ["A", "B"])
        #expect(table.rows == [["a1", "b1"], ["a2", "b2"]])

        let removedColumn = table.removeColumn(at: 0)
        #expect(removedColumn)
        #expect(table.header == ["B"])
        #expect(table.rows == [["b1"], ["b2"]])

        let removedRow = table.removeRow(at: 0)
        #expect(removedRow)
        #expect(table.rows == [["b2"]])
    }

    @Test func escapedPipesRoundTripAsCellContent() {
        let table = MarkdownTable.parse("""
        | A | B |
        | --- | --- |
        | a\\|b | c |
        """)

        #expect(table?.rows == [["a|b", "c"]])
        #expect(table?.serialized().contains("a\\|b") == true)
    }
}
