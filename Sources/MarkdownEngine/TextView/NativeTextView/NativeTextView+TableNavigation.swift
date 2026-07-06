//
//  NativeTextView+TableNavigation.swift
//  MarkdownEngine
//

import AppKit

extension NativeTextView {
    func moveSelectionForTableArrowKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers.isEmpty,
              selectedRange().length == 0,
              let direction = MarkdownTable.CellNavigationDirection(eventKeyCode: event.keyCode),
              let location = MarkdownTable.cellNavigationLocation(
                in: string,
                selectionRange: selectedRange(),
                direction: direction,
                onlyNavigateHorizontallyAtCellBoundary: true
              ) else { return false }

        window?.makeFirstResponder(self)
        setSelectedRange(NSRange(location: min(max(location, 0), (string as NSString).length), length: 0))
        (delegate as? NativeTextViewCoordinator)?.updateTableSelection(textView: self)
        return true
    }
}

private extension MarkdownTable.CellNavigationDirection {
    init?(eventKeyCode: UInt16) {
        switch eventKeyCode {
        case 123: self = .left
        case 124: self = .right
        case 125: self = .down
        case 126: self = .up
        default: return nil
        }
    }
}
