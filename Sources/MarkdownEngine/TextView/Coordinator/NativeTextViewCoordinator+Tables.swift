//
//  NativeTextViewCoordinator+Tables.swift
//  MarkdownEngine
//
//  Table selection bridge for embedders that render GUI controls around the
//  active Markdown table.
//

import AppKit

extension NativeTextViewCoordinator {

    func handleSelectTableCellNotification(_ notification: Notification) {
        guard let textView,
              let rangeValue = notification.userInfo?["range"] as? NSValue,
              let row = notification.userInfo?["row"] as? Int,
              let column = notification.userInfo?["column"] as? Int,
              let location = MarkdownTable.cellContentLocation(
                in: textView.string,
                tableRange: rangeValue.rangeValue,
                row: row,
                column: column
              ) else { return }

        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: location, length: 0))
        updateTableSelection(textView: textView)
    }

    func updateTableSelection(textView: NSTextView) {
        let source = textView.string
        guard let sourceSelection = MarkdownTable.selection(
            in: source,
            selectionRange: textView.selectedRange()
        ) else {
            onTableSelectionChange?(nil)
            return
        }

        let rect = textView.renderedTableImageRect(
            forCharacterRange: sourceSelection.range,
            using: layoutBridge
        ) ?? textView.viewRect(forCharacterRange: sourceSelection.range, using: layoutBridge)
        onTableSelectionChange?(MarkdownTableSelection(
            range: sourceSelection.range,
            table: sourceSelection.table,
            selectedRow: sourceSelection.selectedRow,
            selectedColumn: sourceSelection.selectedColumn,
            rect: rect
        ))
    }
}

private extension NSTextView {
    func renderedTableImageRect(forCharacterRange range: NSRange, using bridge: LayoutBridge?) -> CGRect? {
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
              let anchorRect = viewRect(forCharacterRange: anchorRange, using: bridge) else {
            return nil
        }

        return CGRect(
            x: anchorRect.minX,
            y: anchorRect.minY + max(0, (anchorRect.height - imageBounds.height) / 2),
            width: imageBounds.width,
            height: imageBounds.height
        )
    }
}
