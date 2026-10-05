//
//  NativeTextView+TableGrid.swift
//  MarkdownEngine
//
//  With syntax hidden a table never opens as its markdown: the caret
//  arriving in its source (an arrow, ↑ ↓, a jump) or a click on the drawn
//  grid opens a `TableGridEditor` over it, on the cell that was reached;
//  leaving it puts the caret on the line above or below. Edits come back
//  through `replaceTableSource`; any other change to the text (an undo)
//  closes the grid, since its cells would be stale.
//

import AppKit

enum TableExit { case before, after }

extension NativeTextView {
    /// The whole table whose source holds `location`, if any.
    func tableSource(at location: Int) -> NSRange? {
        guard let storage = textStorage, location >= 0, location < storage.length else { return nil }
        return (storage.attribute(.tableSource, at: location, effectiveRange: nil) as? NSValue)?.rangeValue
    }

    /// Where a table is drawn, in view coordinates.
    func drawnTableRect(_ source: NSRange) -> CGRect? {
        if let wide = wideTableOverlays.values.first(where: { NSLocationInRange($0.anchorTextLocation, source) }) {
            return wide.frame
        }
        guard let tlm = textLayoutManager else { return nil }
        var found: CGRect?
        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) { fragment in
            guard let markdown = fragment as? MarkdownTextLayoutFragment else { return true }
            let frame = fragment.layoutFragmentFrame
            for table in markdown.drawnTables() where NSEqualRanges(table.source, source) {
                found = table.rect.offsetBy(dx: frame.minX + textContainerOrigin.x, dy: frame.minY + textContainerOrigin.y)
                return false
            }
            return true
        }
        return found
    }

    /// The drawn table under a point, if any.
    func drawnTable(at point: CGPoint) -> (source: NSRange, rect: CGRect)? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        var sources: [NSRange] = []
        storage.enumerateAttribute(.tableSource, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let range = (value as? NSValue)?.rangeValue, !sources.contains(where: { NSEqualRanges($0, range) }) {
                sources.append(range)
            }
        }
        for source in sources {
            if let rect = drawnTableRect(source), rect.contains(point) { return (source, rect) }
        }
        return nil
    }

    /// The grid under a click: the drawn table's own geometry says which cell.
    func openTableGrid(at point: CGPoint) -> Bool {
        guard hidesSyntax, tableGridEditor == nil, let hit = drawnTable(at: point) else { return false }
        let text = (string as NSString).substring(with: hit.source)
        guard let model = TableModel(source: text) else { return false }
        let geometry = MarkdownStyler.renderedTableGeometry(model, baseFont: baseFont, configuration: configuration)
        let local = CGPoint(x: point.x - hit.rect.minX, y: point.y - hit.rect.minY)
        let cell = geometry.cell(at: local) ?? (0, 0)
        openTableGrid(hit.source, cell: cell)
        return true
    }

    func openTableGrid(_ source: NSRange, cell: (row: Int, column: Int)) {
        guard hidesSyntax, tableGridEditor == nil, NSMaxRange(source) <= (string as NSString).length,
              let model = TableModel(source: (string as NSString).substring(with: source)) else { return }
        removeImageResizeHandle()
        editingTableLocation = source.location
        restyleTable(source)
        guard let rect = drawnTableRect(source) else {
            editingTableLocation = nil
            restyleTable(source)
            return
        }
        let editor = TableGridEditor(owner: self, source: source, model: model, cell: cell, origin: rect.origin)
        addSubview(editor)
        tableGridEditor = editor
        editor.focus(row: editor.focused.row, column: editor.focused.column)
    }

    /// Closes the grid, its last cell written. `placing` puts the caret on the
    /// line above or below; nil leaves focus wherever it went.
    func closeTableGrid(placing exit: TableExit?) {
        guard let editor = tableGridEditor else { return }
        editor.commitFocused()
        let source = editor.source
        tableGridEditor = nil
        editor.removeFromSuperview()
        editingTableLocation = nil
        restyleTable(source)
        guard let exit else { return }
        window?.makeFirstResponder(self)
        let ns = string as NSString
        let location: Int
        switch exit {
        case .before: location = max(0, source.location - 1)
        case .after: location = min(NSMaxRange(source) + 1, ns.length)
        }
        suppressTableGridOpen = true
        setSelectedRange(NSRange(location: location, length: 0))
        suppressTableGridOpen = false
        scrollRangeToVisible(selectedRange())
    }

    /// The grid's table written over its source, as one undoable edit; the
    /// range it now covers.
    func replaceTableSource(_ source: NSRange, with markdown: String) -> NSRange? {
        guard NSMaxRange(source) <= (string as NSString).length,
              shouldChangeText(in: source, replacementString: markdown) else { return nil }
        let written = NSRange(location: source.location, length: (markdown as NSString).length)
        isWritingTableSource = true
        editingTableLocation = written.location
        replaceCharacters(in: source, with: markdown)
        didChangeText()
        isWritingTableSource = false
        // The caret stays parked at the table while its cells are edited.
        suppressTableGridOpen = true
        setSelectedRange(NSRange(location: written.location, length: 0))
        suppressTableGridOpen = false
        return written
    }

    /// The table and the line it stood on, gone; the caret where it was.
    func deleteTable(_ source: NSRange) {
        if let editor = tableGridEditor {
            tableGridEditor = nil
            editor.removeFromSuperview()
        }
        editingTableLocation = nil
        let ns = string as NSString
        var range = source
        if NSMaxRange(range) < ns.length, ns.character(at: NSMaxRange(range)) == 0x0A { range.length += 1 }
        guard shouldChangeText(in: range, replacementString: "") else { return }
        replaceCharacters(in: range, with: "")
        didChangeText()
        window?.makeFirstResponder(self)
        suppressTableGridOpen = true
        setSelectedRange(NSRange(location: min(range.location, (string as NSString).length), length: 0))
        suppressTableGridOpen = false
    }

    private func restyleTable(_ source: NSRange) {
        guard let coordinator = delegate as? NativeTextViewCoordinator else { return }
        let ns = string as NSString
        guard NSMaxRange(source) <= ns.length else { return }
        coordinator.restyleParagraphs([ns.paragraphRange(for: source)], in: self)
        if let tlm = textLayoutManager { tlm.ensureLayout(for: tlm.documentRange) }
        needsDisplay = true
    }

    /// The caret landing in a table's source opens its grid (from
    /// `setSelectedRanges`); true when it did, the caret parked at the table.
    func openTableGridIfCaretEnters(_ location: Int) -> Bool {
        guard hidesSyntax, !suppressTableGridOpen, tableGridEditor == nil,
              let source = tableSource(at: location) else { return false }
        let text = (string as NSString).substring(with: source)
        let cell = TableModel.cell(at: location - source.location, in: text)
        DispatchQueue.main.async { [weak self] in self?.openTableGrid(source, cell: cell) }
        return true
    }

    override func didChangeText() {
        super.didChangeText()
        // A change the grid didn't make (an undo, a paste elsewhere): its cells are stale.
        if tableGridEditor != nil, !isWritingTableSource { closeTableGrid(placing: nil) }
    }
}

extension MarkdownStyler {
    /// The geometry the renderer drew a table with: its cells formatted the same way.
    static func renderedTableGeometry(_ model: TableModel, baseFont: NSFont, configuration: MarkdownEditorConfiguration) -> TableGeometry {
        let cells = model.rows.enumerated().map { r, row in
            row.map {
                formattedCellString($0, baseFont: baseFont, header: r == 0, theme: configuration.theme,
                                    codeBackgroundColor: configuration.services.syntaxHighlighter.backgroundColor(),
                                    latex: configuration.services.latex)
            }
        }
        return TableGeometry(cells: cells, columnCount: model.columnCount, baseFont: baseFont)
    }
}
