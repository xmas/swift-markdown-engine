//
//  HiddenSyntaxTests.swift
//  MarkdownEngineTests
//
//  `revealsSyntax = false`: markers stay hidden under the caret, the caret
//  steps over them, and deleting beside them deletes visible text. Headless.
//

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor
struct HiddenSyntaxTests {

    private func editor(_ text: String, caret: Int) -> (NativeTextView, NativeTextViewCoordinator) {
        _ = NSApplication.shared  // the selection delegate reads NSApp.currentEvent
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let tv = NativeTextView(frame: scroll.contentView.bounds)
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
        c.rebuildTextStorageAndStyle(tv, from: text)
        tv.setSelectedRange(NSRange(location: caret, length: 0))
        let full = NSRange(location: 0, length: (tv.string as NSString).length)
        c.restyleParagraphs([full], in: tv)
        return (tv, c)
    }

    private func caret(_ tv: NSTextView) -> Int { tv.selectedRange().location }

    @Test("The caret inside a mark leaves its markers hidden")
    func markersStayHidden() {
        let (tv, _) = editor("a **bold** c", caret: 5)
        #expect(tv.isHiddenMarker(at: 2) && tv.isHiddenMarker(at: 3))
        #expect(tv.isHiddenMarker(at: 8) && tv.isHiddenMarker(at: 9))
        #expect(!tv.isHiddenMarker(at: 5))
    }

    @Test("← → move one visible character, over hidden markers")
    func arrowsStepOverMarkers() {
        // a0 *1 *2 B3 B4 *5 *6 c7
        let (tv, _) = editor("a**BB**c", caret: 1)
        tv.moveRight(nil); #expect(caret(tv) == 4)
        tv.moveRight(nil); #expect(caret(tv) == 5)
        tv.moveRight(nil); #expect(caret(tv) == 8)
        tv.moveLeft(nil); #expect(caret(tv) == 7)
        tv.moveLeft(nil); #expect(caret(tv) == 4)
        tv.moveLeft(nil); #expect(caret(tv) == 3)
        tv.moveLeft(nil); #expect(caret(tv) == 0)
    }

    @Test("A caret set between two hidden markers rests at the nearer edge")
    func caretNeverRestsAmongMarkers() {
        let (tv, _) = editor("a**BB**c", caret: 0)
        tv.setSelectedRange(NSRange(location: 2, length: 0))
        #expect([1, 3].contains(caret(tv)))
        tv.setSelectedRange(NSRange(location: 6, length: 0))
        #expect([5, 7].contains(caret(tv)))
    }

    @Test("⌫ after a mark deletes its last visible character")
    func backspaceDeletesVisibleText() {
        let (tv, _) = editor("a**BB**c", caret: 7)
        tv.deleteBackward(nil)
        #expect(tv.string == "a**B**c")
        #expect(caret(tv) == 4)
    }

    @Test("⌦ before a mark's closing markers deletes the next visible character")
    func forwardDeleteSkipsMarkers() {
        let (tv, _) = editor("a**BB**cd", caret: 5)
        tv.deleteForward(nil)
        #expect(tv.string == "a**BB**d")
        #expect(caret(tv) == 5)
    }

    @Test("Emptying a mark takes its markers with it")
    func emptyMarkGoes() {
        let (tv, _) = editor("a**B**c", caret: 6)
        tv.deleteBackward(nil)
        #expect(tv.string == "ac")
        #expect(caret(tv) == 1)
    }

    @Test("Typing after a mark's hidden markers lands visible, outside it")
    func typingAfterAMark() {
        let (tv, _) = editor("a**BB**c", caret: 7)
        tv.insertText("x", replacementRange: tv.selectedRange())
        #expect(tv.string == "a**BB**xc")
        #expect(caret(tv) == 8)
        #expect(!tv.isHiddenMarker(at: 7))
    }

    @Test("Typing inside a mark stays inside it")
    func typingInsideAMark() {
        let (tv, _) = editor("a**BB**c", caret: 5)
        tv.insertText("x", replacementRange: tv.selectedRange())
        #expect(tv.string == "a**BBx**c")
        #expect(caret(tv) == 6)
    }

    @Test("A heading's hidden prefix: the caret rests after it, ⌫ there removes it")
    func headingPrefix() {
        let (tv, _) = editor("# Title", caret: 0)
        #expect(tv.isHiddenMarker(at: 0))
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(caret(tv) == 2)
        tv.deleteBackward(nil)
        #expect(tv.string == "Title")
        #expect(caret(tv) == 0)
    }

    @Test("⌥⌫ after a mark deletes its last word, never its markers")
    func wordDeleteKeepsMarkers() {
        // a0 ␠1 *2 *3 b4 o5 l6 d7 ␠8 w9 o10 r11 d12 *13 *14 c15
        let (tv, _) = editor("a **bold word**c", caret: 15)
        tv.deleteWordBackward(nil)
        #expect(tv.string == "a **bold**c")
        #expect(caret(tv) == 8)
    }

    @Test("⌥⌫ that empties a mark takes the mark")
    func wordDeleteEmptiesMark() {
        let (tv, _) = editor("a **word**c", caret: 10)
        tv.deleteWordBackward(nil)
        #expect(tv.string == "a c")
        #expect(caret(tv) == 2)
    }

    @Test("⌥⌦ before a mark deletes its first word")
    func wordDeleteForward() {
        let (tv, _) = editor("a**word more** c", caret: 1)
        tv.deleteWordForward(nil)
        #expect(tv.string == "a**more** c")
    }

    @Test("Plain text deletes as ever")
    func plainTextUntouched() {
        let (tv, _) = editor("hello", caret: 5)
        tv.deleteBackward(nil)
        #expect(tv.string == "hell")
    }

    @Test("Revealing editors keep their markers")
    func revealingEditorUnchanged() {
        let (tv, c) = editor("a**BB**c", caret: 7)
        tv.configuration.revealsSyntax = true
        c.configuration.revealsSyntax = true
        tv.deleteBackward(nil)
        #expect(tv.string == "a**BB*c")
    }
}
