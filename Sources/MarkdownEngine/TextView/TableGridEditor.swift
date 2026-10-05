//
//  TableGridEditor.swift
//  MarkdownEngine
//
//  A table edited as a grid, never as its markdown (with `revealsSyntax`
//  off). Laid over the drawn table — whose image is left blank meanwhile —
//  it draws the same grid and puts a field in every cell. A cell's words are
//  written back to the markdown when the cell is left; a row or column in or
//  out is written at once. Each is one undoable edit.
//
//  Keys: Tab / ⇧Tab cell to cell (Tab in the last cell adds a row), Return
//  the cell below (adding a row at the foot), ↑ ↓ cell to cell and out of the
//  table at its edges, ← → across cells at a cell's ends, Esc out below.
//  Controls: + at the right edge (a column) and the foot (a row), and a
//  cell's context menu: insert a row above / below, a column left / right,
//  delete the row, the column, the table.
//

import AppKit

final class TableGridEditor: NSView, NSTextFieldDelegate {
    weak var owner: NativeTextView?
    /// The table's source in the document; its length changes as edits are written.
    private(set) var source: NSRange
    private(set) var model: TableModel
    private(set) var focused: (row: Int, column: Int)
    private var fields: [[GridCellField]] = []
    private var geometry: TableGeometry
    private let baseFont: NSFont
    private let headerFont: NSFont
    private let theme: MarkdownEditorTheme
    private let addRow = GridAddButton(vertical: false)
    private let addColumn = GridAddButton(vertical: true)
    /// Fields are being replaced: their editing ends, but nothing is written.
    private var isRebuilding = false
    /// Room right of and under the grid for the + buttons.
    static let gutter: CGFloat = 22

    init(owner: NativeTextView, source: NSRange, model: TableModel, cell: (row: Int, column: Int), origin: CGPoint) {
        self.owner = owner
        self.source = source
        self.model = model
        self.baseFont = owner.baseFont
        let descriptor = owner.baseFont.fontDescriptor.withSymbolicTraits(.bold)
        self.headerFont = NSFont(descriptor: descriptor, size: owner.baseFont.pointSize) ?? owner.baseFont
        self.theme = owner.configuration.theme
        self.focused = (min(cell.row, model.rowCount - 1), min(cell.column, model.columnCount - 1))
        self.geometry = TableGeometry(cells: [], columnCount: model.columnCount, baseFont: owner.baseFont)
        super.init(frame: CGRect(origin: origin, size: .zero))
        addRow.target = self
        addRow.action = #selector(addRowAtFoot)
        addRow.toolTip = "Add a row"
        addColumn.target = self
        addColumn.action = #selector(addColumnAtEnd)
        addColumn.toolTip = "Add a column"
        addSubview(addRow)
        addSubview(addColumn)
        rebuildFields()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    // MARK: Layout

    private func font(row: Int) -> NSFont { row == 0 ? headerFont : baseFont }

    private func measured() -> [[NSAttributedString]] {
        model.rows.enumerated().map { r, cells in
            cells.enumerated().map { c, text in
                let live = fields.indices.contains(r) && fields[r].indices.contains(c) ? fields[r][c].stringValue : text
                return NSAttributedString(string: live.isEmpty ? " " : live, attributes: [.font: font(row: r)])
            }
        }
    }

    /// Fields for every cell, from the model.
    private func rebuildFields() {
        isRebuilding = true
        fields.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        isRebuilding = false
        fields = model.rows.enumerated().map { r, cells in
            cells.enumerated().map { c, text in
                let field = GridCellField(row: r, column: c)
                field.stringValue = text
                field.font = font(row: r)
                field.textColor = theme.bodyText
                field.alignment = model.alignments[c] == .center ? .center : (model.alignments[c] == .right ? .right : .left)
                field.delegate = self
                field.grid = self
                addSubview(field)
                return field
            }
        }
        relayout()
    }

    /// Places the fields and buttons for the cells' current words.
    func relayout() {
        geometry = TableGeometry(cells: measured(), columnCount: model.columnCount, baseFont: baseFont)
        for (r, row) in fields.enumerated() {
            for (c, field) in row.enumerated() where r < geometry.rowCount && c < geometry.columnCount {
                field.frame = geometry.textRect(row: r, column: c)
            }
        }
        let size = geometry.size
        addColumn.frame = CGRect(x: size.width + 4, y: 0, width: 16, height: size.height)
        addRow.frame = CGRect(x: 0, y: size.height + 4, width: size.width, height: 14)
        setFrameSize(CGSize(width: size.width + Self.gutter, height: size.height + Self.gutter))
        needsDisplay = true
    }

    // MARK: Drawing — the renderer's look

    override func draw(_ dirtyRect: NSRect) {
        let size = geometry.size
        let border = TableGeometry.borderWidth
        let muted = theme.mutedText.usingColorSpace(.sRGB) ?? theme.mutedText
        muted.withAlphaComponent(0.08).setFill()
        NSRect(x: border, y: border, width: size.width - 2 * border, height: geometry.rowHeight).fill()
        muted.withAlphaComponent(0.5).setStroke()
        let outer = NSBezierPath(rect: NSRect(x: border / 2, y: border / 2, width: size.width - border, height: size.height - border))
        outer.lineWidth = border
        outer.stroke()
        let lines = NSBezierPath()
        lines.lineWidth = border
        for i in 1..<max(geometry.columnCount, 1) {
            let x = geometry.columnLeft[i] - border / 2
            lines.move(to: NSPoint(x: x, y: 0)); lines.line(to: NSPoint(x: x, y: size.height))
        }
        for i in 1..<max(geometry.rowCount, 1) {
            let y = geometry.rowTop[i] - border / 2
            lines.move(to: NSPoint(x: 0, y: y)); lines.line(to: NSPoint(x: size.width, y: y))
        }
        lines.stroke()
        // The cell being edited, outlined in the accent.
        if focused.row < geometry.rowCount, focused.column < geometry.columnCount {
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(rect: geometry.cellRect(row: focused.row, column: focused.column).insetBy(dx: 0.5, dy: 0.5))
            ring.lineWidth = 2
            ring.stroke()
        }
    }

    // MARK: Focus

    func focus(row: Int, column: Int, caretAtEnd: Bool = true) {
        guard fields.indices.contains(row), fields[row].indices.contains(column) else { return }
        focused = (row, column)
        let field = fields[row][column]
        window?.makeFirstResponder(field)
        if let editor = field.currentEditor() {
            let end = (field.stringValue as NSString).length
            editor.selectedRange = NSRange(location: caretAtEnd ? end : 0, length: 0)
        }
        needsDisplay = true
    }

    /// Writes the focused cell's words back when they changed.
    func commitFocused() {
        guard !isRebuilding,
              fields.indices.contains(focused.row), fields[focused.row].indices.contains(focused.column),
              model.rows.indices.contains(focused.row), model.rows[focused.row].indices.contains(focused.column) else { return }
        let text = TableModel.clean(fields[focused.row][focused.column].stringValue)
        guard text != model.rows[focused.row][focused.column] else { return }
        model.set(text, row: focused.row, column: focused.column)
        write()
    }

    /// The model written over the table's source, as one undoable edit.
    private func write() {
        guard let owner else { return }
        let markdown = model.markdown
        if let written = owner.replaceTableSource(source, with: markdown) { source = written }
    }

    /// A structural change: the focused cell first, then the change, written, fields rebuilt.
    private func change(focusing cell: (row: Int, column: Int), _ body: (inout TableModel) -> Void) {
        commitFocused()
        body(&model)
        write()
        rebuildFields()
        focus(row: min(cell.row, model.rowCount - 1), column: min(max(cell.column, 0), model.columnCount - 1))
    }

    // MARK: Structure

    @objc func addRowAtFoot() { change(focusing: (model.rowCount, 0)) { $0.insertRow(at: $0.rowCount) } }
    @objc func addColumnAtEnd() { change(focusing: (focused.row, model.columnCount)) { $0.insertColumn(at: $0.columnCount) } }
    @objc func insertRowAbove() { change(focusing: (max(focused.row, 1), focused.column)) { [r = focused.row] in $0.insertRow(at: max(r, 1)) } }
    @objc func insertRowBelow() { change(focusing: (focused.row + 1, focused.column)) { [r = focused.row] in $0.insertRow(at: r + 1) } }
    @objc func insertColumnLeft() { change(focusing: (focused.row, focused.column)) { [c = focused.column] in $0.insertColumn(at: c) } }
    @objc func insertColumnRight() { change(focusing: (focused.row, focused.column + 1)) { [c = focused.column] in $0.insertColumn(at: c + 1) } }

    @objc func deleteRow() {
        guard focused.row > 0 else { return NSSound.beep() }
        change(focusing: (focused.row, focused.column)) { [r = focused.row] in $0.deleteRow(r) }
    }

    @objc func deleteColumn() {
        guard model.columnCount > 1 else { return deleteTable() }
        change(focusing: (focused.row, focused.column)) { [c = focused.column] in $0.deleteColumn(c) }
    }

    @objc func deleteTable() {
        guard let owner else { return }
        owner.deleteTable(source)
    }

    /// The cell's context menu.
    func cellMenu() -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector, enabled: Bool = true) {
            let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
            it.target = self
            it.isEnabled = enabled
            menu.addItem(it)
        }
        menu.autoenablesItems = false
        item("Insert Row Above", #selector(insertRowAbove))
        item("Insert Row Below", #selector(insertRowBelow))
        item("Insert Column Left", #selector(insertColumnLeft))
        item("Insert Column Right", #selector(insertColumnRight))
        menu.addItem(.separator())
        item("Delete Row", #selector(deleteRow), enabled: focused.row > 0)
        item("Delete Column", #selector(deleteColumn))
        item("Delete Table", #selector(deleteTable))
        return menu
    }

    // MARK: Fields

    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let field = obj.object as? GridCellField else { return }
        if (field.row, field.column) != focused {
            commitFocused()
            focused = (field.row, field.column)
            needsDisplay = true
        }
    }

    func controlTextDidChange(_ obj: Notification) { relayout() }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard !isRebuilding else { return }
        commitFocused()
        // Focus left the grid altogether (a click in the text, another window): close.
        DispatchQueue.main.async { [weak self] in
            guard let self, let owner = self.owner, owner.tableGridEditor === self else { return }
            let responder = self.window?.firstResponder
            let inGrid = (responder as? NSView).map { $0.isDescendant(of: self) } ?? false
            let fieldEditor = (responder as? NSTextView)?.delegate as? GridCellField
            if !inGrid && fieldEditor?.grid !== self { owner.closeTableGrid(placing: nil) }
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let (r, c) = focused
        let atStart = textView.selectedRange().location == 0 && textView.selectedRange().length == 0
        let atEnd = textView.selectedRange().location == (textView.string as NSString).length
        switch selector {
        case #selector(NSResponder.insertTab(_:)):
            if c + 1 < model.columnCount { focus(row: r, column: c + 1) }
            else if r + 1 < model.rowCount { focus(row: r + 1, column: 0) }
            else { change(focusing: (r + 1, 0)) { $0.insertRow(at: $0.rowCount) } }
        case #selector(NSResponder.insertBacktab(_:)):
            if c > 0 { focus(row: r, column: c - 1) } else if r > 0 { focus(row: r - 1, column: model.columnCount - 1) }
        case #selector(NSResponder.insertNewline(_:)):
            if r + 1 < model.rowCount { focus(row: r + 1, column: c) }
            else { change(focusing: (r + 1, c)) { $0.insertRow(at: $0.rowCount) } }
        case #selector(NSResponder.moveUp(_:)):
            if r > 0 { focus(row: r - 1, column: c) } else { owner?.closeTableGrid(placing: .before) }
        case #selector(NSResponder.moveDown(_:)):
            if r + 1 < model.rowCount { focus(row: r + 1, column: c) } else { owner?.closeTableGrid(placing: .after) }
        case #selector(NSResponder.moveLeft(_:)) where atStart:
            if c > 0 { focus(row: r, column: c - 1) } else if r > 0 { focus(row: r - 1, column: model.columnCount - 1) }
            else { owner?.closeTableGrid(placing: .before) }
        case #selector(NSResponder.moveRight(_:)) where atEnd:
            if c + 1 < model.columnCount { focus(row: r, column: c + 1, caretAtEnd: false) }
            else if r + 1 < model.rowCount { focus(row: r + 1, column: 0, caretAtEnd: false) }
            else { owner?.closeTableGrid(placing: .after) }
        case #selector(NSResponder.cancelOperation(_:)):
            owner?.closeTableGrid(placing: .after)
        default:
            return false
        }
        return true
    }
}

/// One cell's field: borderless, transparent, single line.
final class GridCellField: NSTextField {
    let row: Int
    let column: Int
    weak var grid: TableGridEditor?

    init(row: Int, column: Int) {
        self.row = row
        self.column = column
        super.init(frame: .zero)
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        usesSingleLineMode = true
        lineBreakMode = .byClipping
        cell?.wraps = false
        cell?.isScrollable = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func menu(for event: NSEvent) -> NSMenu? {
        grid?.focus(row: row, column: column)
        return grid?.cellMenu()
    }

    /// The field editor asks its delegate — this field — for its menu while editing.
    @objc func textView(_ textView: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        grid?.cellMenu() ?? menu
    }
}

/// The + beside the grid: a column at the right edge, a row at the foot.
final class GridAddButton: NSButton {
    private let vertical: Bool

    init(vertical: Bool) {
        self.vertical = vertical
        super.init(frame: .zero)
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let muted = NSColor.secondaryLabelColor
        let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
        (isHighlighted ? NSColor.controlAccentColor.withAlphaComponent(0.25) : muted.withAlphaComponent(0.10)).setFill()
        pill.fill()
        let plus = NSBezierPath()
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        plus.move(to: CGPoint(x: c.x - 4, y: c.y)); plus.line(to: CGPoint(x: c.x + 4, y: c.y))
        plus.move(to: CGPoint(x: c.x, y: c.y - 4)); plus.line(to: CGPoint(x: c.x, y: c.y + 4))
        plus.lineWidth = 1.5
        muted.setStroke()
        plus.stroke()
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}
