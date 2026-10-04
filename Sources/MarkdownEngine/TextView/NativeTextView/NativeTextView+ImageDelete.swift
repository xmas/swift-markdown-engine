//
//  NativeTextView+ImageDelete.swift
//  MarkdownEngine
//
//  A drawn image is one thing to delete. ⌫ at the start of the line under
//  it (or with the caret on its own line) and ⌦ at the end of the line over
//  it remove the whole image line in one undoable edit, so the caret never
//  steps into the line and its markdown is never shown on the way out. An
//  image that isn't drawn (not found) deletes like text.
//

import AppKit

extension NativeTextView {
    private static let imageLineRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*!(\[\[[^\]\n]+\]\]|\[[^\]\n]*\]\([^)\n]+\))[ \t]*$"#
    )

    override func deleteBackward(_ sender: Any?) {
        if deleteImageLine(backward: true) || deleteBesideHiddenSyntax(backward: true) { return }
        super.deleteBackward(sender)
    }

    override func deleteWordBackward(_ sender: Any?) {
        if deleteImageLine(backward: true) || deleteBesideHiddenSyntax(backward: true) { return }
        super.deleteWordBackward(sender)
    }

    override func deleteForward(_ sender: Any?) {
        if deleteImageLine(backward: false) || deleteBesideHiddenSyntax(backward: false) { return }
        super.deleteForward(sender)
    }

    override func deleteWordForward(_ sender: Any?) {
        if deleteImageLine(backward: false) || deleteBesideHiddenSyntax(backward: false) { return }
        super.deleteWordForward(sender)
    }

    /// Removes the drawn image line the key would reach into; false when the
    /// key doesn't reach one and should do its usual thing.
    private func deleteImageLine(backward: Bool) -> Bool {
        guard isEditable, hasMarkedText() == false else { return false }
        let selection = selectedRange()
        guard selection.length == 0 else { return false }
        let ns = string as NSString
        let caret = selection.location

        // The caret on the image line itself: either key takes the line.
        if let line = drawnImageLine(containing: caret, in: ns), caret == line.contentEnd || caret == line.range.location {
            if backward || caret == line.range.location {
                removeImageLine(line, in: ns)
                return true
            }
        }
        if backward {
            // At the start of a line, the line above.
            guard caret > 0, ns.character(at: caret - 1) == 0x0A,
                  let line = drawnImageLine(containing: caret - 1, in: ns) else { return false }
            removeImageLine(line, in: ns)
        } else {
            // At the end of a line, the line below.
            guard caret < ns.length, ns.character(at: caret) == 0x0A, caret + 1 < ns.length,
                  let line = drawnImageLine(containing: caret + 1, in: ns) else { return false }
            removeImageLine(line, in: ns)
        }
        return true
    }

    private struct ImageLine {
        /// The paragraph with its newline, if it has one.
        var range: NSRange
        /// Where its text ends, before the newline.
        var contentEnd: Int
    }

    private func drawnImageLine(containing index: Int, in ns: NSString) -> ImageLine? {
        guard index >= 0, index <= ns.length, ns.length > 0 else { return nil }
        let range = ns.paragraphRange(for: NSRange(location: min(index, ns.length - 1), length: 0))
        var contentEnd = NSMaxRange(range)
        if contentEnd > range.location, ns.character(at: contentEnd - 1) == 0x0A { contentEnd -= 1 }
        let content = NSRange(location: range.location, length: contentEnd - range.location)
        guard content.length > 0,
              Self.imageLineRegex.firstMatch(in: ns as String, range: content) != nil,
              let storage = textStorage, NSMaxRange(content) <= storage.length else { return nil }
        // Only a drawn image is one thing; a missing one is still its text.
        var drawn = false
        storage.enumerateAttribute(.latexImage, in: content) { value, _, stop in
            if value is NSImage { drawn = true; stop.pointee = true }
        }
        return drawn ? ImageLine(range: range, contentEnd: contentEnd) : nil
    }

    /// One edit, one undo. A last line takes the newline before it instead,
    /// so no empty line is left at the end.
    private func removeImageLine(_ line: ImageLine, in ns: NSString) {
        var range = line.range
        if NSMaxRange(range) == ns.length, line.contentEnd == ns.length, range.location > 0 {
            range = NSRange(location: range.location - 1, length: range.length + 1)
        }
        insertText("", replacementRange: range)
        setSelectedRange(NSRange(location: min(range.location, (string as NSString).length), length: 0))
    }
}
