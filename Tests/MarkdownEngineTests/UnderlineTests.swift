//
//  UnderlineTests.swift
//  MarkdownEngineTests
//
//  `~text~` is Bear's underline: one tilde each side. `~~text~~` stays
//  strikethrough, and an approximate "~5" stays plain. Headless.
//

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Underline")
struct UnderlineTests {

    private func r(_ location: Int, _ length: Int) -> NSRange {
        NSRange(location: location, length: length)
    }

    @Test("single tildes → underline")
    func parsesUnderline() {
        #expect(InlineParser.parse("a ~b~ c") == [
            .text(r(0, 2)),
            .underline(range: r(2, 3), markers: [r(2, 1), r(4, 1)], children: [.text(r(3, 1))]),
            .text(r(5, 2)),
        ])
    }

    @Test("double tildes stay strikethrough")
    func doubleTildeIsStrikethrough() {
        #expect(InlineParser.parse("~~x~~") == [
            .strikethrough(range: r(0, 5), markers: [r(0, 2), r(3, 2)], children: [.text(r(2, 1))]),
        ])
    }

    @Test("an approximate tilde stays plain")
    func approximationIsPlain() {
        #expect(InlineParser.parse("~5 to ~10") == [.text(r(0, 9))])
        #expect(InlineParser.parse("about ~5 minutes") == [.text(r(0, 16))])
        #expect(InlineParser.parse("a ~ b ~ c") == [.text(r(0, 9))])
    }

    @Test("underline nests inside bold")
    func nestsInBold() {
        let nodes = InlineParser.parse("**a ~b~**")
        guard case .emphasis(.bold, _, _, let children)? = nodes.first else {
            Issue.record("expected bold, got \(nodes)"); return
        }
        #expect(children.contains { if case .underline = $0 { true } else { false } })
    }

    @Test("the styler underlines the content and hides the tildes")
    func styled() {
        let attrs = MarkdownStyler.styleAttributes(
            text: "a ~b~ c", fontName: "SF Pro", fontSize: 16, layoutBridge: nil,
            caretLocation: -1, activeTokenIndices: []
        )
        let underlined = attrs.contains { range, a in
            range == r(3, 1) && (a[.underlineStyle] as? Int) == NSUnderlineStyle.single.rawValue
        }
        #expect(underlined)
    }

    // MARK: - The toggle

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

    @Test func wrapsSelection() {
        let tv = apply("hello world", r(6, 5)) { $0.didMarkdownUnderline(nil) }
        #expect(tv.string == "hello ~world~")
        #expect(tv.selectedRange() == r(7, 5))
    }

    @Test func wrapsWordAtCaret() {
        let tv = apply("hello world", r(8, 0)) { $0.didMarkdownUnderline(nil) }
        #expect(tv.string == "hello ~world~")
    }

    @Test func togglesOff() {
        let tv = apply("~text~", r(1, 4)) { $0.didMarkdownUnderline(nil) }
        #expect(tv.string == "text")
    }
}
