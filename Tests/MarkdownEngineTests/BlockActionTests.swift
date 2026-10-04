//
//  BlockActionTests.swift
//  MarkdownEngineTests
//
//  Lists and tables from a toolbar: toggleList over the selected lines,
//  insertTable, add row, add column; and a hidden-syntax editor still opens
//  a table under the caret. Headless.
//

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Block actions")
struct BlockActionTests {

    private func r(_ location: Int, _ length: Int) -> NSRange { NSRange(location: location, length: length) }

    private func apply(_ text: String, _ selection: NSRange, action: (NativeTextViewCoordinator) -> Void) -> NativeTextView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let tv = NativeTextView(frame: scroll.contentView.bounds)
        tv.isEditable = true
        tv.configuration = .default
        let c = NativeTextViewCoordinator(
            text: .constant(""), fontName: "SF Pro Text", fontSize: 14,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil
        )
        c.textView = tv
        tv.string = text
        tv.setSelectedRange(selection)
        action(c)
        return tv
    }

    // MARK: Lists

    @Test func bulletsOneLineKeepingTheCaret() {
        let tv = apply("milk", r(2, 0)) { $0.toggleList(.bullet) }
        #expect(tv.string == "- milk")
        #expect(tv.selectedRange() == r(4, 0))
    }

    @Test func bulletsEveryLineOfTheSelection() {
        let tv = apply("milk\neggs\nbread", r(1, 10)) { $0.toggleList(.bullet) }
        #expect(tv.string == "- milk\n- eggs\n- bread")
    }

    @Test func togglesOffWhenAllAlready() {
        let tv = apply("- milk\n- eggs", r(0, 13)) { $0.toggleList(.bullet) }
        #expect(tv.string == "milk\neggs")
    }

    @Test func switchesKindAndNumbers() {
        let tv = apply("- milk\n- eggs\n- bread", r(0, 20)) { $0.toggleList(.ordered) }
        #expect(tv.string == "1. milk\n2. eggs\n3. bread")
    }

    @Test func checklistKeepsTicks() {
        let tv = apply("- [x] milk\neggs", r(0, 15)) { $0.toggleList(.task) }
        #expect(tv.string == "- [x] milk\n- [ ] eggs")
    }

    @Test func keepsIndentAndSkipsBlankLines() {
        let tv = apply("a\n\n  b", r(0, 5)) { $0.toggleList(.bullet) }
        #expect(tv.string == "- a\n\n  - b")
    }

    // MARK: Tables

    @Test func insertsATableAsItsOwnBlock() {
        let tv = apply("Notes", r(5, 0)) { $0.insertTable(columns: 2, rows: 1) }
        #expect(tv.string == "Notes\n\n|   |   |\n|---|---|\n|   |   |\n")
        #expect(tv.selectedRange() == r(9, 0))
    }

    @Test func insertsIntoAnEmptyNote() {
        let tv = apply("", r(0, 0)) { $0.insertTable(columns: 2, rows: 1) }
        #expect(tv.string == "|   |   |\n|---|---|\n|   |   |\n")
        #expect(tv.selectedRange() == r(2, 0))
    }

    @Test func addsARowUnderTheCaretsRow() {
        let table = "| a | b |\n|---|---|\n| 1 | 2 |"
        let tv = apply(table, r(22, 0)) { $0.didMarkdownTableAddRow(nil) }
        #expect(tv.string == "| a | b |\n|---|---|\n| 1 | 2 |\n|   |   |")
    }

    @Test func aRowAddedFromTheHeaderGoesUnderTheRule() {
        let table = "| a | b |\n|---|---|\n| 1 | 2 |\n"
        let tv = apply(table, r(2, 0)) { $0.didMarkdownTableAddRow(nil) }
        #expect(tv.string == "| a | b |\n|---|---|\n|   |   |\n| 1 | 2 |\n")
    }

    @Test func addsAColumnAfterTheCaretsColumn() {
        let table = "| a | b |\n|---|---|\n| 1 | 2 |\n"
        let tv = apply(table, r(2, 0)) { $0.didMarkdownTableAddColumn(nil) }
        #expect(tv.string == "| a |   | b |\n|---|---|---|\n| 1 |   | 2 |\n")
    }

    @Test("Hidden syntax still opens a table under the caret, not a mark")
    func tableOpensWhenHidden() {
        let text = "**b** x\n\n| a | b |\n|---|---|\n| 1 | 2 |\n"
        let tokens = MarkdownTokenizer.parseTokensViaAST(in: text)
        let ns = text as NSString
        let inTable = MarkdownDetection.computeActiveTokenIndices(
            selectionRange: r(12, 0), tokens: tokens, in: ns, revealing: MarkdownDetection.editableBlockKinds)
        #expect(inTable.contains { tokens[$0].kind == .table })
        let inBold = MarkdownDetection.computeActiveTokenIndices(
            selectionRange: r(2, 0), tokens: tokens, in: ns, revealing: MarkdownDetection.editableBlockKinds)
        #expect(inBold.isEmpty)
    }
}
