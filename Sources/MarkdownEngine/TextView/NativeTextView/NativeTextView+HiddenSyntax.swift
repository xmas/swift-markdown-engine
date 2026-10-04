//
//  NativeTextView+HiddenSyntax.swift
//  MarkdownEngine
//
//  With `revealsSyntax` off the markers stay hidden while they are edited,
//  but they are still characters. This keeps the caret from ever resting
//  among them: ← → move one visible character, a click or a vertical move
//  never lands between two hidden characters or before a hidden line prefix
//  (`# `, `- `, `> `), and ⌫ ⌦ delete the visible character beside a hidden
//  run — a mark left with nothing in it takes its markers along, and ⌫ at
//  the start of a heading or list line takes its prefix.
//
//  "Hidden" is what the styler drew invisible: a clear foreground, or the
//  hidden-marker font size.
//

import AppKit

extension NativeTextView {
    var hidesSyntax: Bool { isEditable && !configuration.revealsSyntax && !configuration.rawSourceMode }

    /// Whether the character at `index` is a marker drawn invisible.
    func isHiddenMarker(at index: Int) -> Bool {
        guard let storage = textStorage, index >= 0, index < storage.length else { return false }
        let ns = storage.string as NSString
        if ns.character(at: index) == 0x0A { return false }
        let attrs = storage.attributes(at: index, effectiveRange: nil)
        if attrs[.revealableSource] != nil { return false }
        if let color = attrs[.foregroundColor] as? NSColor, color.alphaComponent < 0.01 { return true }
        if let font = attrs[.font] as? NSFont, font.pointSize < 1 { return true }
        return false
    }

    private func isLineStart(_ index: Int, _ ns: NSString) -> Bool {
        index == 0 || (index <= ns.length && ns.character(at: index - 1) == 0x0A)
    }

    /// The end of the hidden run starting at `index` (== index when none).
    private func hiddenRunEnd(from index: Int) -> Int {
        var end = index
        while isHiddenMarker(at: end) { end += 1 }
        return end
    }

    /// The start of the hidden run ending at `index` (== index when none).
    private func hiddenRunStart(before index: Int) -> Int {
        var start = index
        while start > 0, isHiddenMarker(at: start - 1) { start -= 1 }
        return start
    }

    /// Where the caret may rest nearest `index`: never between two hidden
    /// characters, never before a hidden line prefix.
    func restingCaret(near index: Int) -> Int {
        let ns = string as NSString
        let index = min(max(0, index), ns.length)
        if isLineStart(index, ns), isHiddenMarker(at: index) { return hiddenRunEnd(from: index) }
        guard index > 0, isHiddenMarker(at: index - 1), isHiddenMarker(at: index) else { return index }
        let start = hiddenRunStart(before: index), end = hiddenRunEnd(from: index)
        if isLineStart(start, ns) { return end }
        return index - start < end - index ? start : end
    }

    // MARK: Moving

    override func moveRight(_ sender: Any?) {
        guard hidesSyntax, selectedRange().length == 0 else { return super.moveRight(sender) }
        let ns = string as NSString
        var to = hiddenRunEnd(from: selectedRange().location)
        if to < ns.length { to = NSMaxRange(ns.rangeOfComposedCharacterSequence(at: to)) }
        if isLineStart(to, ns), isHiddenMarker(at: to) { to = hiddenRunEnd(from: to) }
        setSelectedRange(NSRange(location: to, length: 0))
        scrollRangeToVisible(selectedRange())
    }

    override func moveLeft(_ sender: Any?) {
        guard hidesSyntax, selectedRange().length == 0 else { return super.moveLeft(sender) }
        let ns = string as NSString
        var to = hiddenRunStart(before: selectedRange().location)
        if to > 0 { to = ns.rangeOfComposedCharacterSequence(at: to - 1).location }
        if isLineStart(to, ns), isHiddenMarker(at: to) { to = hiddenRunEnd(from: to) }
        setSelectedRange(NSRange(location: to, length: 0))
        scrollRangeToVisible(selectedRange())
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        guard hidesSyntax, !stillSelecting, ranges.count == 1, ranges[0].rangeValue.length == 0 else {
            return super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        }
        let resting = restingCaret(near: ranges[0].rangeValue.location)
        super.setSelectedRanges([NSValue(range: NSRange(location: resting, length: 0))],
                                affinity: affinity, stillSelecting: stillSelecting)
    }

    // MARK: Deleting

    /// ⌫ beside hidden markers; false when the key should do its usual thing.
    func deleteBesideHiddenSyntax(backward: Bool) -> Bool {
        guard hidesSyntax, !hasMarkedText(), selectedRange().length == 0 else { return false }
        let ns = string as NSString
        let caret = selectedRange().location
        if backward {
            guard caret > 0, isHiddenMarker(at: caret - 1) else { return false }
            let start = hiddenRunStart(before: caret)
            // A heading's or a list item's prefix: ⌫ at its text takes it.
            if isLineStart(start, ns) {
                replaceHidden(NSRange(location: start, length: caret - start), caretAt: start)
                return true
            }
            let victim = ns.rangeOfComposedCharacterSequence(at: start - 1)
            if ns.character(at: victim.location) == 0x0A { return false }
            removeVisible(victim, ns, caretAt: nil)
        } else {
            guard caret < ns.length, isHiddenMarker(at: caret) else { return false }
            let end = hiddenRunEnd(from: caret)
            guard end < ns.length else { return false }
            let victim = ns.rangeOfComposedCharacterSequence(at: end)
            if ns.character(at: victim.location) == 0x0A { return false }
            removeVisible(victim, ns, caretAt: caret)
        }
        return true
    }

    /// Deletes one visible character; when hidden markers then meet with
    /// nothing between them, the mark is empty and they go too.
    /// `caretAt` nil puts the caret where the character was (⌫); ⌦ keeps it.
    private func removeVisible(_ victim: NSRange, _ ns: NSString, caretAt: Int?) {
        let before = hiddenRunStart(before: victim.location)
        let after = hiddenRunEnd(from: NSMaxRange(victim))
        if before < victim.location, after > NSMaxRange(victim), !isLineStart(before, ns) {
            let whole = NSRange(location: before, length: after - before)
            replaceHidden(whole, caretAt: min(caretAt ?? before, before))
        } else {
            replaceHidden(victim, caretAt: caretAt ?? victim.location)
        }
    }

    private func replaceHidden(_ range: NSRange, caretAt location: Int) {
        insertText("", replacementRange: range)
        setSelectedRange(NSRange(location: min(location, (string as NSString).length), length: 0))
    }
}
