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

    func selectRenderedTableCellIfHit(event: NSEvent) -> Bool {
        guard event.clickCount == 1,
              !event.modifierFlags.contains(.shift),
              let layoutBridge else { return false }

        let point = enclosingScrollView?.convert(event.locationInWindow, from: nil)
            ?? convert(event.locationInWindow, from: nil)
        let ns = string as NSString
        let tokens = MarkdownTokenizer.parseTokensViaAST(in: string)
        for token in tokens where token.kind == .table {
            guard NSMaxRange(token.range) <= ns.length,
                  let table = MarkdownTable.parse(ns.substring(with: token.range)),
                  let tableRect = renderedTableImageRectForHitTesting(
                    forCharacterRange: token.range,
                    bridge: layoutBridge
                  ),
                  tableRect.insetBy(dx: -2, dy: -2).contains(point) else { continue }

            let target = MarkdownTableLayout.target(
                at: point,
                tableRect: tableRect,
                table: table,
                font: baseFont
            )
            guard let cellRange = MarkdownTable.cellContentRange(
                in: string,
                tableRange: token.range,
                row: target.row,
                column: target.column
            ) else { return false }

            let location = cellRange.location + min(max(target.offset, 0), cellRange.length)
            window?.makeFirstResponder(self)
            setSelectedRange(NSRange(location: location, length: 0))
            (delegate as? NativeTextViewCoordinator)?.updateTableSelection(textView: self)
            return true
        }

        return false
    }

    private func renderedTableImageRectForHitTesting(
        forCharacterRange range: NSRange,
        bridge: LayoutBridge
    ) -> CGRect? {
        guard let storage = textStorage else { return nil }

        var anchorRange: NSRange?
        var imageBounds: CGRect?
        storage.enumerateAttribute(.latexImage, in: range, options: []) { value, attrRange, stop in
            guard let image = value as? NSImage else { return }
            anchorRange = NSRange(location: attrRange.location, length: 1)
            imageBounds = (storage.attribute(.latexBounds, at: attrRange.location, effectiveRange: nil) as? NSValue)?.rectValue
                ?? CGRect(origin: .zero, size: image.size)
            stop.pointee = true
        }

        guard let anchorRange,
              let imageBounds,
              let anchorRect = viewRect(forCharacterRange: anchorRange, using: bridge) else { return nil }

        return CGRect(
            x: anchorRect.minX,
            y: anchorRect.minY + max(0, (anchorRect.height - imageBounds.height) / 2),
            width: imageBounds.width,
            height: imageBounds.height
        )
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
