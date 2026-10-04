//
//  LinkEditingTests.swift
//  MarkdownEngineTests
//
//  A link's address edited beside the text (syntax hidden): read, change,
//  remove, add; and the menu items. The sheet itself is UI. Headless.
//

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Link editing")
struct LinkEditingTests {

    private func editor(_ text: String, _ selection: NSRange, hidden: Bool = true) -> (NativeTextView, NativeTextViewCoordinator) {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let tv = NativeTextView(frame: scroll.contentView.bounds)
        tv.isEditable = true
        var config = MarkdownEditorConfiguration.default
        config.revealsSyntax = !hidden
        tv.configuration = config
        let c = NativeTextViewCoordinator(
            text: .constant(""), fontName: "SF Pro Text", fontSize: 14,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil
        )
        c.configuration = config
        c.textView = tv
        tv.string = text
        tv.setSelectedRange(selection)
        return (tv, c)
    }

    @Test func readsAndChangesTheAddress() {
        let (tv, c) = editor("see [the doc](https://a.example) now", NSRange(location: 6, length: 0))
        #expect(c.linkAddress(at: 6) == "https://a.example")
        c.setLinkAddress(" https://b.example ", at: 6)
        #expect(tv.string == "see [the doc](https://b.example) now")
    }

    @Test func anEmptyAddressRemovesTheLink() {
        let (tv, c) = editor("see [the doc](https://a.example) now", NSRange(location: 6, length: 0))
        c.setLinkAddress("", at: 6)
        #expect(tv.string == "see the doc now")
    }

    @Test func removeKeepsTheWords() {
        let (tv, c) = editor("[x](y) z", NSRange(location: 1, length: 0))
        c.removeLink(at: 1)
        #expect(tv.string == "x z")
        #expect(tv.selectedRange() == NSRange(location: 1, length: 0))
    }

    @Test func addLinksTheSelection() {
        let (tv, c) = editor("read this please", NSRange(location: 5, length: 4))
        c.addLink("https://c.example")
        #expect(tv.string == "read [this](https://c.example) please")
    }

    @Test func menuOffersEditAndRemoveOnALink() {
        let (tv, c) = editor("see [the doc](https://a.example)", NSRange(location: 0, length: 0))
        let menu = NSMenu()
        c.addLinkItems(to: menu, at: 6, in: tv)
        #expect(menu.items.prefix(2).map(\.title) == ["Edit Link…", "Remove Link"])
    }

    @Test func menuOffersAddOnASelection() {
        let (tv, c) = editor("plain words", NSRange(location: 0, length: 5))
        let menu = NSMenu()
        c.addLinkItems(to: menu, at: 2, in: tv)
        #expect(menu.items.first?.title == "Add Link…")
    }

    @Test func revealingEditorsAddNothing() {
        let (tv, c) = editor("see [the doc](https://a.example)", NSRange(location: 0, length: 0), hidden: false)
        let menu = NSMenu()
        c.addLinkItems(to: menu, at: 6, in: tv)
        #expect(menu.items.isEmpty)
    }
}
