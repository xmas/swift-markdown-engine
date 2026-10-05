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

    /// The drawn picture line holding `index`: where it starts and where its
    /// text ends (before its newline).
    func pictureLine(containing index: Int) -> (start: Int, contentEnd: Int)? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let ns = storage.string as NSString
        let paragraph = ns.paragraphRange(for: NSRange(location: min(max(0, index), ns.length - 1), length: 0))
        guard paragraph.length > 0,
              storage.attribute(.resizableImageWidth, at: paragraph.location, effectiveRange: nil) != nil else { return nil }
        var end = NSMaxRange(paragraph)
        if end > paragraph.location, ns.character(at: end - 1) == 0x0A { end -= 1 }
        // A caret at the start of the next line belongs there, not here.
        guard index <= end else { return nil }
        return (paragraph.location, end)
    }

    /// Typing beside hidden markers would take their 0.1 pt font and clear colour
    /// (and the caret their height): the body's are used instead.
    func repairTypingAttributes() {
        guard let font = typingAttributes[.font] as? NSFont, font.pointSize < 1
                || (typingAttributes[.foregroundColor] as? NSColor)?.alphaComponent ?? 1 < 0.01 else { return }
        var attributes = typingAttributes
        attributes[.font] = baseFont
        attributes[.foregroundColor] = configuration.theme.bodyText
        attributes.removeValue(forKey: .kern)
        typingAttributes = attributes
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
        // Into a table's source: its grid opens; the caret waits at the table.
        let location = ranges[0].rangeValue.location
        if openTableGridIfCaretEnters(location), let table = tableSource(at: location) {
            return super.setSelectedRanges([NSValue(range: NSRange(location: table.location, length: 0))],
                                           affinity: affinity, stillSelecting: stillSelecting)
        }
        // On a drawn picture's line the caret would stand in its hidden source, drawn
        // at the 0.1 pt marker font's height — a dot. It goes on past the picture,
        // the way it was moving: the line below, or the end of the line above.
        if let picture = pictureLine(containing: location), !(location == 0 && picture.start == 0) {
            let backward = location < selectedRange().location
            let ns = string as NSString
            let past = backward
                ? max(0, picture.start - 1)
                : (picture.contentEnd < ns.length ? picture.contentEnd + 1 : picture.contentEnd)
            super.setSelectedRanges([NSValue(range: NSRange(location: past, length: 0))],
                                    affinity: affinity, stillSelecting: stillSelecting)
            repairTypingAttributes()
            return
        }
        let resting = restingCaret(near: location)
        super.setSelectedRanges([NSValue(range: NSRange(location: resting, length: 0))],
                                affinity: affinity, stillSelecting: stillSelecting)
        repairTypingAttributes()
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

    /// ⌥⌫ ⌥⌦ beside hidden markers: the word is deleted inside the mark,
    /// never the markers; a mark left empty goes whole. False when the
    /// caret isn't beside a hidden run.
    func deleteWordBesideHiddenSyntax(backward: Bool) -> Bool {
        guard hidesSyntax, !hasMarkedText(), selectedRange().length == 0 else { return false }
        let ns = string as NSString
        let caret = selectedRange().location
        // The markers the word sits against, and where the word's edge is.
        let edge: Int
        if backward {
            guard caret > 0, isHiddenMarker(at: caret - 1) else { return false }
            edge = hiddenRunStart(before: caret)
            guard edge > 0, !isLineStart(edge, ns) else { return false }
        } else {
            guard caret < ns.length, isHiddenMarker(at: caret) else { return false }
            edge = hiddenRunEnd(from: caret)
            guard edge < ns.length else { return false }
        }
        // What was hidden before the edit, to tell an emptied mark after it.
        let paragraph = ns.paragraphRange(for: NSRange(location: edge, length: 0))
        let hiddenBefore = Set((paragraph.location..<NSMaxRange(paragraph)).filter(isHiddenMarker))
        // `string` is live: the length before the edit, kept by value.
        let lengthBefore = ns.length

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }
        super.setSelectedRanges([NSValue(range: NSRange(location: edge, length: 0))], affinity: .downstream, stillSelecting: false)
        if backward { super.deleteWordBackward(nil) } else { super.deleteWordForward(nil) }

        // The deleted span, in the old text: [from, to).
        let removed = lengthBefore - (string as NSString).length
        let from = backward ? edge - removed : edge
        let to = from + removed
        guard removed > 0 else { return true }
        // Markers on both sides of what went, nothing else between: an empty mark.
        guard hiddenBefore.contains(from - 1), hiddenBefore.contains(to) else {
            // A space left against a marker would unmake the mark (`**bold **`
            // isn't bold, and its asterisks would show): it goes too.
            let now = string as NSString
            let space = backward ? from - 1 : from
            let againstMarker = backward ? hiddenBefore.contains(to) : hiddenBefore.contains(from - 1)
            if againstMarker, space >= 0, space < now.length, now.character(at: space) == 0x20 {
                insertText("", replacementRange: NSRange(location: space, length: 1))
                setSelectedRange(NSRange(location: backward ? space : from, length: 0))
            } else {
                setSelectedRange(NSRange(location: from, length: 0))
            }
            return true
        }
        var open = from - 1
        while hiddenBefore.contains(open - 1) { open -= 1 }
        var close = to
        while hiddenBefore.contains(close + 1) { close += 1 }
        let now = NSRange(location: open, length: (from - open) + (close + 1 - to))
        if !isLineStart(open, ns) {
            insertText("", replacementRange: now)
            setSelectedRange(NSRange(location: open, length: 0))
        } else {
            setSelectedRange(NSRange(location: from, length: 0))
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
