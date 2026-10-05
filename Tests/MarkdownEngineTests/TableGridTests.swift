//
//  TableGridTests.swift
//  MarkdownEngineTests
//
//  Tables edited as a grid (syntax hidden): the model, the cell a source
//  location falls in, and the grid editor writing back. Headless.
//

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Table grid")
struct TableGridTests {

    @Test func modelRoundTrips() {
        let model = TableModel(source: "| a | b |\n|:---:|---:|\n| 1 | 2 |")!
        #expect(model.rows == [["a", "b"], ["1", "2"]])
        #expect(model.alignments == [.center, .right])
        #expect(model.markdown == "| a | b |\n| :---: | ---: |\n| 1 | 2 |")
        #expect(TableModel(source: model.markdown) == model)
    }

    @Test func structureChanges() {
        var model = TableModel(source: "| a | b |\n|---|---|\n| 1 | 2 |")!
        model.insertRow(at: 0)                 // never above the header
        #expect(model.rows == [["a", "b"], ["", ""], ["1", "2"]])
        model.deleteRow(0)                     // the header stays
        #expect(model.rowCount == 3)
        model.insertColumn(at: 1)
        #expect(model.rows[0] == ["a", "", "b"])
        let first = model.deleteColumn(1), second = model.deleteColumn(0), last = model.deleteColumn(0)
        #expect(first && second && !last)      // the last column stays
        model.set("x | y\nz", row: 1, column: 0)
        #expect(model.rows[1][0] == "x ∣ y z")
    }

    @Test func aLocationFallsInACell() {
        let source = "| a | b |\n|---|---|\n| 1 | 2 |"
        #expect(TableModel.cell(at: 2, in: source) == (0, 0))
        #expect(TableModel.cell(at: 6, in: source) == (0, 1))
        #expect(TableModel.cell(at: 12, in: source) == (1, 0))   // the rule reads as the first body row
        #expect(TableModel.cell(at: 26, in: source) == (1, 1))
    }

    // MARK: The grid editor

    private static var keep: [AnyObject] = []
    private static let layoutDelegate = MarkdownLayoutManagerDelegate()

    private func editor(_ text: String) -> (NativeTextView, NativeTextViewCoordinator) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: true)
        let tv = NativeTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        window.contentView = tv
        tv.isEditable = true
        tv.allowsUndo = true
        var config = MarkdownEditorConfiguration.default
        config.revealsSyntax = false
        tv.configuration = config
        let c = NativeTextViewCoordinator(
            text: .constant(""), fontName: "SF Pro", fontSize: 16,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil
        )
        c.configuration = config
        c.textView = tv
        tv.delegate = c
        tv.textLayoutManager?.delegate = Self.layoutDelegate
        let bridge = LayoutBridge(tv.textLayoutManager!)
        c.layoutBridge = bridge
        tv.layoutBridge = bridge
        Self.keep += [window, c, bridge]
        c.rebuildTextStorageAndStyle(tv, from: text)
        return (tv, c)
    }

    @Test func theGridOpensOverTheTableAndWritesBack() {
        let text = "Before\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nAfter"
        let (tv, _) = editor(text)
        let source = (text as NSString).range(of: "| a | b |\n|---|---|\n| 1 | 2 |")
        #expect(tv.tableSource(at: source.location + 3) == source)
        tv.openTableGrid(source, cell: (1, 1))
        let grid = try! #require(tv.tableGridEditor)
        #expect(tv.editingTableLocation == source.location)
        #expect(grid.focused == (1, 1))

        let field = grid.subviews.compactMap { $0 as? GridCellField }.first { $0.row == 1 && $0.column == 1 }!
        field.stringValue = "two"
        grid.commitFocused()
        #expect(tv.string.contains("| 1 | two |"))
        #expect(tv.tableGridEditor === grid)          // its own write keeps it open

        grid.insertRowBelow()
        #expect(tv.string.contains("| 1 | two |\n|   |   |"))
        grid.deleteRow()
        #expect(!tv.string.contains("|   |   |"))

        tv.closeTableGrid(placing: .after)
        #expect(tv.tableGridEditor == nil)
        #expect(tv.editingTableLocation == nil)
        #expect(tv.string.hasPrefix("Before\n\n| a | b |\n| --- | --- |\n| 1 | two |"))
    }

    @Test func deletingTheTableTakesItsLine() {
        let text = "x\n| a |\n|---|\n| 1 |\ny"
        let (tv, _) = editor(text)
        let source = (text as NSString).range(of: "| a |\n|---|\n| 1 |")
        tv.openTableGrid(source, cell: (0, 0))
        tv.tableGridEditor?.deleteTable()
        #expect(tv.string == "x\ny")
        #expect(tv.tableGridEditor == nil)
    }
}
