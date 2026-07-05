//
//  NativeTextViewCoordinator+Tables.swift
//  MarkdownEngine
//
//  Table selection bridge for embedders that render GUI controls around the
//  active Markdown table.
//

import AppKit

extension NativeTextViewCoordinator {

    func updateTableSelection(textView: NSTextView) {
        let source = textView.string
        guard let sourceSelection = MarkdownTable.selection(
            in: source,
            selectionRange: textView.selectedRange()
        ) else {
            onTableSelectionChange?(nil)
            return
        }

        let rect = textView.viewRect(forCharacterRange: sourceSelection.range, using: layoutBridge)
        onTableSelectionChange?(MarkdownTableSelection(
            range: sourceSelection.range,
            table: sourceSelection.table,
            selectedRow: sourceSelection.selectedRow,
            selectedColumn: sourceSelection.selectedColumn,
            rect: rect
        ))
    }
}
