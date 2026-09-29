//
//  MarkdownEditorProxy.swift
//  MarkdownEngine
//
//  A handle on the live editor for an embedder that edits the document while
//  it is open — rewriting a line from outside (a popover's choice, a value
//  that changed elsewhere) without handing the whole text back through the
//  binding, which would rebuild the storage and drop the caret.
//

import AppKit

/// Create one, hand it to ``NativeTextViewWrapper/proxy``, and keep it: the
/// wrapper attaches its text view when the editor is made. Main thread only.
public final class MarkdownEditorProxy {
    weak var textView: NSTextView?

    /// Called after every selection change with the new selection.
    public var onSelectionChange: ((NSRange) -> Void)?

    public init() {}

    /// Whether an editor is attached.
    public var isAttached: Bool { textView != nil }

    /// The document as the editor holds it now.
    public var string: String { textView?.string ?? "" }

    /// The current selection; `nil` when no editor is attached.
    public var selectedRange: NSRange? { textView?.selectedRange() }

    /// Whether the editor holds the keyboard.
    public var hasFocus: Bool {
        guard let textView else { return false }
        return textView.window?.firstResponder === textView
    }

    /// Replace `range` as one undoable edit. The selection keeps its place:
    /// before the edit it stays, after it it shifts, inside it it moves to the
    /// end of the replacement.
    public func replace(_ range: NSRange, with replacement: String, actionName: String? = nil) {
        guard let textView, let storage = textView.textStorage,
              NSMaxRange(range) <= storage.length else { return }
        let selection = textView.selectedRange()
        let delta = (replacement as NSString).length - range.length
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        storage.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        if let actionName { textView.undoManager?.setActionName(actionName) }
        let moved: NSRange
        if NSMaxRange(selection) <= range.location {
            moved = selection
        } else if selection.location >= NSMaxRange(range) {
            moved = NSRange(location: selection.location + delta, length: selection.length)
        } else {
            moved = NSRange(location: range.location + (replacement as NSString).length, length: 0)
        }
        let length = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: min(moved.location, length),
                                          length: min(moved.length, max(0, length - moved.location))))
    }

    /// Several replacements as one undoable step, applied in the order given
    /// (give them last first so earlier ranges stay put).
    public func replace(_ edits: [(range: NSRange, text: String)], actionName: String? = nil) {
        guard let textView, !edits.isEmpty else { return }
        let undo = textView.undoManager
        undo?.beginUndoGrouping()
        for edit in edits { replace(edit.range, with: edit.text) }
        undo?.endUndoGrouping()
        if let actionName { undo?.setActionName(actionName) }
    }

    /// Type `text` at the selection, as if from the keyboard (list continuation and all).
    public func type(_ text: String) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        if text == "\n" {
            textView.insertNewline(nil)
        } else {
            textView.insertText(text, replacementRange: textView.selectedRange())
        }
    }

    /// The margin cell beside the item whose line holds `location`, as a click
    /// there would report it — for opening a margin's editor from the keyboard.
    public func marginClick(at location: Int, side: MarginSide) -> MarginClick? {
        guard let textView = textView as? NativeTextView else { return nil }
        guard let m = textView.marginLines().first(where: { NSLocationInRange(location, $0.line) || NSMaxRange($0.line) == location })
        else { return nil }
        let style = textView.configuration.margins
        let width = textView.textContainer?.size.width ?? textView.bounds.width
        let x = side == .leading
            ? textView.textContainerOrigin.x - style.gap - style.leadingWidth
            : textView.textContainerOrigin.x + width + style.gap
        let rect = CGRect(x: x, y: m.top, width: side == .leading ? style.leadingWidth : style.trailingWidth, height: m.height)
        return MarginClick(side: side, line: m.line, rect: rect, view: textView)
    }

    /// Put the caret at `location` and give the editor the keyboard.
    public func select(_ location: Int) {
        guard let textView else { return }
        let length = (textView.string as NSString).length
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: min(max(0, location), length), length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }
}
