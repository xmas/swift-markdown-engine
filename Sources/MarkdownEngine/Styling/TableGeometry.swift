//
//  TableGeometry.swift
//  MarkdownEngine
//
//  Where a table's columns and rows fall, shared by the renderer (which
//  draws the grid into an image) and the grid editor (which lays a field
//  over each cell), so the two line up exactly.
//

import AppKit

struct TableGeometry {
    static let cellHPadding: CGFloat = 12
    static let cellVPadding: CGFloat = 6
    static let borderWidth: CGFloat = 1
    static let minColumnContentWidth: CGFloat = 16

    /// Left edge of each column's cell (after its border), plus the right end.
    let columnLeft: [CGFloat]
    /// Top of each row's cell (after its border), plus the bottom end.
    let rowTop: [CGFloat]
    let rowHeight: CGFloat
    let lineHeight: CGFloat
    let size: CGSize

    var columnCount: Int { columnLeft.count - 1 }
    var rowCount: Int { rowTop.count - 1 }

    /// `cells[0]` is the header row; every row has `columnCount` cells (or fewer).
    init(cells: [[NSAttributedString]], columnCount: Int, baseFont: NSFont) {
        let border = Self.borderWidth, hPad = Self.cellHPadding, vPad = Self.cellVPadding
        let baseLineHeight = ceil(baseFont.ascender - baseFont.descender + baseFont.leading)
        var widths = [CGFloat](repeating: Self.minColumnContentWidth, count: columnCount)
        var tallest = baseLineHeight
        for row in cells {
            for (col, cell) in row.enumerated() where col < columnCount {
                let size = cell.size()
                widths[col] = max(widths[col], ceil(size.width))
                tallest = max(tallest, ceil(size.height))
            }
        }
        lineHeight = max(baseLineHeight, tallest)
        rowHeight = lineHeight + 2 * vPad
        let rows = max(cells.count, 1)
        var left = [CGFloat](repeating: 0, count: columnCount + 1)
        left[0] = border
        for i in 0..<columnCount { left[i + 1] = left[i] + widths[i] + 2 * hPad + border }
        var top = [CGFloat](repeating: 0, count: rows + 1)
        top[0] = border
        for i in 0..<rows { top[i + 1] = top[i] + rowHeight + border }
        columnLeft = left
        rowTop = top
        let width = widths.reduce(0, +) + CGFloat(columnCount) * 2 * hPad + CGFloat(columnCount + 1) * border
        size = CGSize(width: width, height: CGFloat(rows) * rowHeight + CGFloat(rows + 1) * border)
    }

    /// A cell's box inside its borders, top-down coordinates.
    func cellRect(row: Int, column: Int) -> CGRect {
        CGRect(x: columnLeft[column], y: rowTop[row],
               width: columnLeft[column + 1] - Self.borderWidth - columnLeft[column], height: rowHeight)
    }

    /// Where a cell's text sits.
    func textRect(row: Int, column: Int) -> CGRect {
        let cell = cellRect(row: row, column: column)
        return CGRect(x: cell.minX + Self.cellHPadding, y: cell.minY + max(0, (rowHeight - lineHeight) / 2),
                      width: cell.width - 2 * Self.cellHPadding, height: lineHeight)
    }

    /// The cell under a point, if any.
    func cell(at point: CGPoint) -> (row: Int, column: Int)? {
        guard let row = (0..<rowCount).first(where: { point.y >= rowTop[$0] - Self.borderWidth && point.y < rowTop[$0 + 1] }),
              let column = (0..<columnCount).first(where: { point.x >= columnLeft[$0] - Self.borderWidth && point.x < columnLeft[$0 + 1] })
        else { return nil }
        return (row, column)
    }
}
