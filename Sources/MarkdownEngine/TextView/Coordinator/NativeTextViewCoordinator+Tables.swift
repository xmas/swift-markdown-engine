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
              let cellRange = MarkdownTable.cellContentRange(
                in: textView.string,
                tableRange: rangeValue.rangeValue,
                row: row,
                column: column
              ) else { return }
        let offset = notification.userInfo?["offset"] as? Int ?? 0
        let location = cellRange.location + min(max(offset, 0), cellRange.length)

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

    func remapTableSyntaxSelectionIfNeeded(textView: NSTextView) -> Bool {
        let selectionRange = textView.selectedRange()
        let source = textView.string
        guard let tableRange = MarkdownTable.tableRangeContainingEdit(selectionRange, in: source),
              selectionRange.location < NSMaxRange(tableRange) else { return false }

        if let target = MarkdownTable.editTarget(in: source, selectionRange: selectionRange),
           target.tableRange == tableRange,
           target.cellRange.containsOrTouches(selectionRange) {
            return false
        }
        guard let target = MarkdownTable.syntaxRedirectTarget(in: source, selectionRange: selectionRange) else {
            return false
        }

        textView.setSelectedRange(NSRange(location: target.cellRange.location, length: 0))
        updateTableSelection(textView: textView)
        return true
    }

    func handleProtectedTableEdit(
        textView: NSTextView,
        affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool? {
        let source = textView.string
        guard let tableRange = MarkdownTable.tableRangeContainingEdit(affectedCharRange, in: source) else {
            return nil
        }

        if let target = MarkdownTable.editTarget(in: source, selectionRange: textView.selectedRange()),
           target.tableRange == tableRange,
           target.cellRange.containsOrTouches(affectedCharRange) {
            if let sanitized = sanitizedTableCellReplacement(replacementString), sanitized != replacementString {
                isProgrammaticEdit = true
                defer { isProgrammaticEdit = false }
                textView.insertText(sanitized, replacementRange: affectedCharRange)
                updateTableSelection(textView: textView)
                return false
            }
            return true
        }

        guard let replacementString, !replacementString.isEmpty else {
            return false
        }
        guard let target = MarkdownTable.syntaxRedirectTarget(in: source, selectionRange: textView.selectedRange()) else {
            return false
        }

        isProgrammaticEdit = true
        defer { isProgrammaticEdit = false }
        textView.insertText(
            replacementString,
            replacementRange: NSRange(location: target.cellRange.location, length: 0)
        )
        updateTableSelection(textView: textView)
        return false
    }

    func handleTableCommand(textView: NSTextView, commandSelector: Selector) -> Bool {
        let direction: MarkdownTable.CellNavigationDirection?
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            direction = .down
        case #selector(NSResponder.insertTab(_:)):
            direction = .right
        case #selector(NSResponder.insertBacktab(_:)):
            direction = .left
        default:
            direction = nil
        }
        guard let direction else { return false }
        guard MarkdownTable.selection(in: textView.string, selectionRange: textView.selectedRange()) != nil else {
            return false
        }

        if textView.selectedRange().length == 0,
           let location = MarkdownTable.cellNavigationLocation(
            in: textView.string,
            selectionRange: textView.selectedRange(),
            direction: direction
           ) {
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: min(max(location, 0), (textView.string as NSString).length), length: 0))
            updateTableSelection(textView: textView)
        }
        return true
    }

    private func sanitizedTableCellReplacement(_ replacementString: String?) -> String? {
        guard var replacementString else { return nil }
        replacementString = replacementString
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "|", with: "\\|")
        return replacementString
    }
}

private extension NSRange {
    func containsOrTouches(_ other: NSRange) -> Bool {
        other.location >= location
            && NSMaxRange(other) <= NSMaxRange(self)
            && (length > 0 || other.length == 0)
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
