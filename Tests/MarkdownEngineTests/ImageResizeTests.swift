//
//  ImageResizeTests.swift
//  MarkdownEngineTests
//
//  `![alt|480](url)`: the width in the alt, the styler drawing it, the
//  handle's write-back and snaps. The drag itself is pointer work. Headless.
//

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

private struct FixedImages: EmbeddedImageProvider {
    func image(for reference: EmbeddedImageRequest) -> NSImage? {
        reference.name == "a.png" ? NSImage(size: NSSize(width: 400, height: 200)) : nil
    }
    func fingerprint() -> AnyHashable { 1 }
}

@MainActor
@Suite("Image resize")
struct ImageResizeTests {

    @Test func parsesTheWidth() {
        #expect(ImageLinkWidth.parse(alt: "").width == nil)
        #expect(ImageLinkWidth.parse(alt: "|480").width == 480)
        #expect(ImageLinkWidth.parse(alt: "board|320").text == "board")
        #expect(ImageLinkWidth.parse(alt: "a|b").width == nil)
        #expect(ImageLinkWidth.alt("", width: 480) == "|480")
        #expect(ImageLinkWidth.alt("board|320", width: 200) == "board|200")
        #expect(ImageLinkWidth.alt("board|320", width: nil) == "board")
    }

    /// The engine's layout fragments and bridge, installed as the wrapper does.
    private static var bridges: [LayoutBridge] = []
    private static let layoutDelegate = MarkdownLayoutManagerDelegate()

    private func editor(_ text: String, hidden: Bool = false) -> NativeTextView {
        _ = NSApplication.shared
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let tv = NativeTextView(frame: scroll.contentView.bounds)
        tv.isEditable = true
        tv.allowsUndo = true
        var config = MarkdownEditorConfiguration.default
        config.services.images = FixedImages()
        config.revealsSyntax = !hidden
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
        Self.bridges.append(bridge)
        c.layoutBridge = bridge
        tv.layoutBridge = bridge
        c.rebuildTextStorageAndStyle(tv, from: text)
        return tv
    }

    @Test func aDrawnPictureIsResizableAtItsWidth() {
        let tv = editor("text\n![|120](a.png)\nmore")
        tv.textLayoutManager?.ensureLayout(for: tv.textLayoutManager!.documentRange)
        var found: [(location: Int, rect: CGRect, naturalWidth: CGFloat)] = []
        tv.textLayoutManager?.enumerateTextLayoutFragments(from: tv.textLayoutManager!.documentRange.location, options: [.ensuresLayout]) {
            found += ($0 as? MarkdownTextLayoutFragment)?.resizableImages() ?? []
            return true
        }
        #expect(found.count == 1)
        #expect(found.first?.naturalWidth == 400)
        #expect(found.first?.rect.width == 120)
    }

    @Test func writesTheWidthAsOneEdit() {
        let tv = editor("text\n![](a.png)\nmore")
        tv.setSelectedRange(NSRange(location: 2, length: 0))
        tv.writeImageWidth(240, for: ResizableImage(location: 6, rect: .zero, naturalWidth: 400))
        #expect(tv.string == "text\n![|240](a.png)\nmore")
        #expect(tv.selectedRange() == NSRange(location: 2, length: 0))
        tv.undoManager?.undo()
        #expect(tv.string == "text\n![](a.png)\nmore")
    }

    @Test func resetTakesTheWidthOut() {
        let tv = editor("![board|240](a.png)")
        tv.writeImageWidth(nil, for: ResizableImage(location: 0, rect: .zero, naturalWidth: 400))
        #expect(tv.string == "![board](a.png)")
    }

    @Test("The caret never stands on a picture's line: it goes on past it, the way it was moving")
    func caretSkipsAPictureLine() {
        // a0 \n1 ![](a.png)2…11 \n12 b13
        let tv = editor("a\n![](a.png)\nb", hidden: true)
        tv.setSelectedRange(NSRange(location: 1, length: 0))
        tv.setSelectedRange(NSRange(location: 12, length: 0))      // forward onto it
        #expect(tv.selectedRange().location == 13)
        tv.setSelectedRange(NSRange(location: 5, length: 0))       // back onto it
        #expect(tv.selectedRange().location == 1)
        tv.moveRight(nil)                                           // from the end of "a"
        #expect(tv.selectedRange().location == 13)
        tv.moveLeft(nil)
        #expect(tv.selectedRange().location == 1)
    }

    @Test("The caret beside hidden markers is the body's height, not a dot")
    func typingAttributesAreTheBodys() {
        let tv = editor("a\n![](a.png)\n", hidden: true)
        tv.setSelectedRange(NSRange(location: 1, length: 0))
        tv.setSelectedRange(NSRange(location: 13, length: 0))
        #expect(((tv.typingAttributes[.font] as? NSFont)?.pointSize ?? 0) >= 1)
    }

    @Test func snapsToItsOwnSizeTheColumnAndFractions() {
        let tv = editor("x")
        let column = tv.imageColumnWidth
        #expect(tv.imageSnapWidths(natural: 300) == [min(300, column), column, column / 2, column / 3])
    }
}
