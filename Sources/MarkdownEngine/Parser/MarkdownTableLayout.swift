//
//  MarkdownTableLayout.swift
//  MarkdownEngine
//

import AppKit

public struct MarkdownTableHitTarget: Sendable, Equatable {
    public let row: Int
    public let column: Int
    public let offset: Int

    public init(row: Int, column: Int, offset: Int) {
        self.row = row
        self.column = column
        self.offset = offset
    }
}

public enum MarkdownTableLayout {
    public struct Metrics: Sendable, Equatable {
        public let columnLefts: [CGFloat]
        public let rowHeight: CGFloat
        public let totalWidth: CGFloat
        public let totalHeight: CGFloat
        public let borderWidth: CGFloat
        public let cellHPadding: CGFloat

        public init(
            columnLefts: [CGFloat],
            rowHeight: CGFloat,
            totalWidth: CGFloat,
            totalHeight: CGFloat,
            borderWidth: CGFloat,
            cellHPadding: CGFloat
        ) {
            self.columnLefts = columnLefts
            self.rowHeight = rowHeight
            self.totalWidth = totalWidth
            self.totalHeight = totalHeight
            self.borderWidth = borderWidth
            self.cellHPadding = cellHPadding
        }
    }

    public static func metrics(for table: MarkdownTable, font: NSFont) -> Metrics {
        let columnCount = max(1, table.columnCount)
        let cellHPadding: CGFloat = 12
        let cellVPadding: CGFloat = 6
        let borderWidth: CGFloat = 1
        let minColumnContentWidth: CGFloat = 16
        let headerFont = headerFont(for: font)
        var columnWidths = [CGFloat](repeating: minColumnContentWidth, count: columnCount)

        func measure(_ value: String, column: Int, header: Bool = false) {
            guard columnWidths.indices.contains(column) else { return }
            let measured = ceil((value as NSString).size(withAttributes: [.font: header ? headerFont : font]).width)
            columnWidths[column] = max(columnWidths[column], measured)
        }

        for (index, value) in table.header.enumerated() {
            measure(value, column: index, header: true)
        }
        for row in table.rows {
            for (index, value) in row.enumerated() {
                measure(value, column: index)
            }
        }

        let baseLineHeight = ceil(font.ascender - font.descender + font.leading)
        let rowHeight = baseLineHeight + 2 * cellVPadding
        let rowCount = max(1, table.rows.count + 1)
        let totalWidth = columnWidths.reduce(0, +)
            + CGFloat(columnCount) * 2 * cellHPadding
            + CGFloat(columnCount + 1) * borderWidth
        let totalHeight = CGFloat(rowCount) * rowHeight + CGFloat(rowCount + 1) * borderWidth
        var columnLefts = [CGFloat](repeating: 0, count: columnCount + 1)
        columnLefts[0] = borderWidth
        for index in 0..<columnCount {
            columnLefts[index + 1] = columnLefts[index] + columnWidths[index] + 2 * cellHPadding + borderWidth
        }
        return Metrics(
            columnLefts: columnLefts,
            rowHeight: rowHeight,
            totalWidth: totalWidth,
            totalHeight: totalHeight,
            borderWidth: borderWidth,
            cellHPadding: cellHPadding
        )
    }

    public static func target(
        at location: CGPoint,
        tableRect: CGRect,
        table: MarkdownTable,
        font: NSFont
    ) -> MarkdownTableHitTarget {
        let metrics = metrics(for: table, font: font)
        let scaleX = tableRect.width / max(1, metrics.totalWidth)
        let scaleY = tableRect.height / max(1, metrics.totalHeight)
        let localX = (location.x - tableRect.minX) / max(0.001, scaleX)
        let localY = (location.y - tableRect.minY) / max(0.001, scaleY)
        let renderedRow = Int(localY / max(1, metrics.rowHeight + metrics.borderWidth))
        let rawRow = renderedRow <= 0 ? -1 : renderedRow - 1
        let row = min(max(rawRow, -1), max(0, table.rows.count - 1))
        let column = min(max(columnIndex(at: localX, metrics: metrics), 0), max(0, table.columnCount - 1))
        let cellText = row < 0
            ? table.header[safe: column] ?? ""
            : table.rows[safe: row]?[safe: column] ?? ""
        return MarkdownTableHitTarget(
            row: row,
            column: column,
            offset: characterOffset(
                at: localX,
                text: cellText,
                column: column,
                metrics: metrics,
                font: row < 0 ? headerFont(for: font) : font
            )
        )
    }

    public static func cellRect(
        tableRect: CGRect,
        row: Int,
        column: Int,
        table: MarkdownTable,
        font: NSFont
    ) -> CGRect {
        let metrics = metrics(for: table, font: font)
        let scaleX = tableRect.width / max(1, metrics.totalWidth)
        let scaleY = tableRect.height / max(1, metrics.totalHeight)
        let clampedColumn = min(max(column, 0), max(0, table.columnCount - 1))
        let clampedRow = min(max(row, -1), max(0, table.rows.count - 1))
        let renderedRow = clampedRow < 0 ? 0 : clampedRow + 1
        let x = metrics.columnLefts[clampedColumn]
        let nextX = metrics.columnLefts[min(clampedColumn + 1, metrics.columnLefts.count - 1)]
        return CGRect(
            x: tableRect.minX + x * scaleX,
            y: tableRect.minY + (metrics.borderWidth + CGFloat(renderedRow) * (metrics.rowHeight + metrics.borderWidth)) * scaleY,
            width: max(1, (nextX - x - metrics.borderWidth) * scaleX),
            height: max(1, metrics.rowHeight * scaleY)
        )
    }

    public static func caretX(
        tableRect: CGRect,
        table: MarkdownTable,
        font: NSFont,
        row: Int,
        column: Int,
        offset: Int
    ) -> CGFloat {
        let metrics = metrics(for: table, font: font)
        let scaleX = tableRect.width / max(1, metrics.totalWidth)
        let clampedColumn = min(max(column, 0), max(0, table.columnCount - 1))
        let text = row < 0
            ? table.header[safe: clampedColumn] ?? ""
            : table.rows[safe: row]?[safe: clampedColumn] ?? ""
        let ns = text as NSString
        let safeOffset = min(max(offset, 0), ns.length)
        let caretFont = row < 0 ? headerFont(for: font) : font
        let prefix = ns.substring(with: NSRange(location: 0, length: safeOffset)) as NSString
        let contentWidth = prefix.size(withAttributes: [.font: caretFont]).width
        let localX = metrics.columnLefts[clampedColumn] + metrics.cellHPadding + contentWidth
        let cell = cellRect(tableRect: tableRect, row: row, column: clampedColumn, table: table, font: font)
        return min(max(tableRect.minX + localX * scaleX, cell.minX + 4), cell.maxX - 4)
    }

    private static func headerFont(for font: NSFont) -> NSFont {
        NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.bold), size: font.pointSize) ?? font
    }

    private static func columnIndex(at localX: CGFloat, metrics: Metrics) -> Int {
        guard metrics.columnLefts.count > 1 else { return 0 }
        for index in 0..<(metrics.columnLefts.count - 1) {
            let left = metrics.columnLefts[index]
            let right = metrics.columnLefts[index + 1]
            if localX >= left, localX < right { return index }
        }
        return localX < metrics.columnLefts[0] ? 0 : metrics.columnLefts.count - 2
    }

    private static func characterOffset(
        at localX: CGFloat,
        text: String,
        column: Int,
        metrics: Metrics,
        font: NSFont
    ) -> Int {
        guard !text.isEmpty, metrics.columnLefts.indices.contains(column) else { return 0 }
        let contentX = localX - metrics.columnLefts[column] - metrics.cellHPadding
        if contentX <= 0 { return 0 }
        let ns = text as NSString
        var best = ns.length
        for offset in 0...ns.length {
            let prefix = ns.substring(with: NSRange(location: 0, length: offset)) as NSString
            if prefix.size(withAttributes: [.font: font]).width >= contentX {
                best = offset
                break
            }
        }
        return best
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
