//
//  MarkdownTableEditingTests.swift
//  MarkdownEngineTests
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine
import SwiftUI

@MainActor
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

    @Test func findsSelectedTableRangeAndCell() {
        let text = """
        Intro

        | A | B |
        | --- | --- |
        | a1 | b1 |
        | a2 | b2 |

        Tail
        """
        let ns = text as NSString
        let selection = MarkdownTable.selection(
            in: text,
            selectionRange: ns.range(of: "b2")
        )

        #expect(selection?.table.header == ["A", "B"])
        #expect(selection?.selectedRow == 1)
        #expect(selection?.selectedColumn == 1)
        #expect(selection.map { ns.substring(with: $0.range) } == "| A | B |\n| --- | --- |\n| a1 | b1 |\n| a2 | b2 |\n")
    }

    @Test func locatesHeaderAndBodyCellInsertionPoints() {
        let text = """
        | A | B |
        | --- | --- |
        | a1 | b1 |
        """
        let ns = text as NSString
        let selection = MarkdownTable.selection(in: text, selectionRange: ns.range(of: "a1"))

        let headerLocation = selection.flatMap {
            MarkdownTable.cellContentLocation(in: text, tableRange: $0.range, row: -1, column: 1)
        }
        let bodyLocation = selection.flatMap {
            MarkdownTable.cellContentLocation(in: text, tableRange: $0.range, row: 0, column: 1)
        }

        #expect(headerLocation == ns.range(of: "B").location)
        #expect(bodyLocation == ns.range(of: "b1").location)
    }

    @Test func redirectsSeparatorSyntaxToEditableBodyCell() {
        let text = """
        | A | B |
        | --- | --- |
        | a1 | b1 |
        """
        let ns = text as NSString
        let separatorLocation = ns.range(of: "---").location

        let directTarget = MarkdownTable.editTarget(
            in: text,
            selectionRange: NSRange(location: separatorLocation, length: 0)
        )
        let redirectTarget = MarkdownTable.syntaxRedirectTarget(
            in: text,
            selectionRange: NSRange(location: separatorLocation, length: 0)
        )

        #expect(directTarget == nil)
        #expect(redirectTarget?.cellRange.location == ns.range(of: "a1").location)
    }

    @Test func protectedEditRedirectsSyntaxTypingIntoCellContent() {
        let text = """
        | A | B |
        | --- | --- |
        | a1 | b1 |
        """
        let ns = text as NSString
        let textView = NativeTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        let coordinator = NativeTextViewCoordinator(
            text: .constant(""),
            fontName: "SF Pro Text",
            fontSize: 14,
            isWikiLinkActive: .constant(false),
            onLinkClick: nil,
            onInlineSelectionChange: nil
        )
        coordinator.textView = textView
        textView.string = text
        textView.setSelectedRange(ns.range(of: "---"))
        textView.delegate = coordinator

        let allowed = coordinator.textView(
            textView,
            shouldChangeTextIn: textView.selectedRange(),
            replacementString: "X"
        )

        #expect(!allowed)
        #expect(textView.string.contains("| Xa1 | b1 |"))
        #expect(textView.string.contains("| --- | --- |"))
    }

    @Test func selectionOnTableSyntaxRemapsToCellContent() {
        let text = """
        | A | B |
        | --- | --- |
        | a1 | b1 |
        """
        let ns = text as NSString
        let textView = NativeTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        let coordinator = NativeTextViewCoordinator(
            text: .constant(""),
            fontName: "SF Pro Text",
            fontSize: 14,
            isWikiLinkActive: .constant(false),
            onLinkClick: nil,
            onInlineSelectionChange: nil
        )
        coordinator.textView = textView
        textView.string = text
        textView.setSelectedRange(ns.range(of: "---"))

        let remapped = coordinator.remapTableSyntaxSelectionIfNeeded(textView: textView)

        #expect(remapped)
        #expect(textView.selectedRange() == NSRange(location: ns.range(of: "a1").location, length: 0))
    }

    @Test func arrowNavigationMovesThroughHeaderBodyAndOutOfTable() {
        let text = """
        Before
        | A | B |
        | --- | --- |
        | a1 | b1 |
        | a2 | b2 |
        After
        """
        let ns = text as NSString
        let headerBLocation = ns.range(of: " B |").location + 1

        let rightFromHeader = MarkdownTable.cellNavigationLocation(
            in: text,
            selectionRange: ns.range(of: "A"),
            direction: .right
        )
        let downFromHeader = MarkdownTable.cellNavigationLocation(
            in: text,
            selectionRange: NSRange(location: headerBLocation, length: 1),
            direction: .down
        )
        let leftFromFirstBodyCell = MarkdownTable.cellNavigationLocation(
            in: text,
            selectionRange: ns.range(of: "a1"),
            direction: .left
        )
        let rightFromLastBodyCell = MarkdownTable.cellNavigationLocation(
            in: text,
            selectionRange: ns.range(of: "b2"),
            direction: .right
        )

        #expect(rightFromHeader == headerBLocation)
        #expect(downFromHeader == ns.range(of: "b1").location)
        #expect(leftFromFirstBodyCell == headerBLocation)
        #expect(rightFromLastBodyCell == ns.range(of: "After").location)
    }

    @Test func activeTablesStayRenderedForToolbarEditing() {
        _ = NSApplication.shared
        let text = """
        | A | B |
        | --- | --- |
        | a1 | b1 |
        """
        let tokens = MarkdownTokenizer.parseTokensViaAST(in: text)
        let attrs = MarkdownStyler.styleAttributes(
            text: text,
            fontName: "Helvetica",
            fontSize: 14,
            caretLocation: 2,
            activeTokenIndices: [0],
            precomputedTokens: tokens
        )

        #expect(attrs.contains { _, attributes in attributes[.latexImage] is NSImage })
    }
}
