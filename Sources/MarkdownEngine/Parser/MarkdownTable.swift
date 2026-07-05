//
//  MarkdownTable.swift
//  MarkdownEngine
//
//  Source-level GFM table model and edit operations. UI layers can parse the
//  selected table, mutate rows/columns, and write the serialized Markdown back
//  to the original source range.
//

import Foundation

public enum MarkdownTableAlignment: Sendable, Equatable {
    case left
    case center
    case right
}

public struct MarkdownTable: Sendable, Equatable {
    public var header: [String]
    public var alignments: [MarkdownTableAlignment]
    public var rows: [[String]]

    public var columnCount: Int { header.count }

    public init(
        header: [String],
        alignments: [MarkdownTableAlignment],
        rows: [[String]]
    ) {
        let count = max(header.count, alignments.count, rows.map(\.count).max() ?? 0)
        self.header = Self.padded(header, to: count, with: "")
        self.alignments = Self.padded(alignments, to: count, with: .left)
        self.rows = rows.map { Self.padded($0, to: count, with: "") }
    }

    public static func parse(_ source: String) -> MarkdownTable? {
        let rawLines = source.components(separatedBy: CharacterSet.newlines)
        let lines = rawLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { return nil }

        let header = parseRow(lines[0])
        guard !header.isEmpty else { return nil }

        let alignmentCells = parseRow(lines[1])
        let alignments = alignmentCells.compactMap(parseAlignment)
        guard alignments.count == alignmentCells.count, !alignments.isEmpty else { return nil }

        let rows = lines.dropFirst(2).map(parseRow)
        return MarkdownTable(header: header, alignments: alignments, rows: rows)
    }

    public static func selection(in source: String, selectionRange: NSRange) -> MarkdownTableSourceSelection? {
        let ns = source as NSString
        let length = ns.length
        guard length > 0 else { return nil }
        let caret = min(max(selectionRange.location, 0), length)
        var lineRanges: [NSRange] = []
        var cursor = 0
        while cursor < length {
            let line = ns.lineRange(for: NSRange(location: cursor, length: 0))
            lineRanges.append(line)
            cursor = NSMaxRange(line)
        }

        func lineText(_ index: Int) -> String {
            ns.substring(with: lineRanges[index])
        }

        var index = lineRanges.firstIndex { range in
            caret >= range.location && caret <= NSMaxRange(range)
        }
        if index == nil, caret == length {
            index = lineRanges.indices.last
        }
        guard let selectedLine = index else { return nil }

        for headerIndex in lineRanges.indices {
            guard headerIndex + 1 < lineRanges.count,
                  isTableRow(lineText(headerIndex)),
                  isTableSeparator(lineText(headerIndex + 1)) else { continue }

            var endIndex = headerIndex + 1
            while endIndex + 1 < lineRanges.count, isTableRow(lineText(endIndex + 1)) {
                endIndex += 1
            }
            guard selectedLine >= headerIndex, selectedLine <= endIndex else { continue }

            let range = union(lineRanges[headerIndex...endIndex])
            guard let table = parse(ns.substring(with: range)) else { return nil }
            let selectedRow = selectedLine >= headerIndex + 2 ? selectedLine - headerIndex - 2 : nil
            let selectedColumn = columnIndex(at: caret, in: lineText(selectedLine), lineStart: lineRanges[selectedLine].location)
            return MarkdownTableSourceSelection(
                range: range,
                table: table,
                selectedRow: selectedRow,
                selectedColumn: selectedColumn
            )
        }
        return nil
    }

    enum CellNavigationDirection {
        case left
        case right
        case up
        case down
    }

    static func cellNavigationLocation(
        in source: String,
        selectionRange: NSRange,
        direction: CellNavigationDirection
    ) -> Int? {
        guard let selection = selection(in: source, selectionRange: selectionRange) else { return nil }
        let columnCount = max(1, selection.table.columnCount)
        let currentRow = selection.selectedRow ?? -1
        let currentColumn = min(max(selection.selectedColumn ?? 0, 0), columnCount - 1)

        let target: (row: Int, column: Int)?
        switch direction {
        case .left:
            if currentColumn > 0 {
                target = (currentRow, currentColumn - 1)
            } else if currentRow > -1 {
                target = (currentRow - 1, columnCount - 1)
            } else {
                return selection.range.location
            }
        case .right:
            if currentColumn + 1 < columnCount {
                target = (currentRow, currentColumn + 1)
            } else if currentRow < selection.table.rows.count - 1 {
                target = (currentRow + 1, 0)
            } else {
                return NSMaxRange(selection.range)
            }
        case .up:
            if currentRow > -1 {
                target = (currentRow - 1, currentColumn)
            } else {
                return selection.range.location
            }
        case .down:
            if currentRow < selection.table.rows.count - 1 {
                target = (currentRow + 1, currentColumn)
            } else {
                return NSMaxRange(selection.range)
            }
        }

        guard let target else { return nil }
        return cellContentLocation(
            in: source,
            tableRange: selection.range,
            row: target.row,
            column: target.column
        )
    }

    public static func cellContentLocation(in source: String, tableRange: NSRange, row: Int, column: Int) -> Int? {
        let ns = source as NSString
        guard tableRange.location >= 0,
              tableRange.length > 0,
              NSMaxRange(tableRange) <= ns.length else { return nil }

        var lineRanges: [NSRange] = []
        var cursor = tableRange.location
        let end = NSMaxRange(tableRange)
        while cursor < end {
            let line = ns.lineRange(for: NSRange(location: cursor, length: 0))
            lineRanges.append(NSIntersectionRange(line, tableRange))
            cursor = NSMaxRange(line)
        }

        let lineIndex = row < 0 ? 0 : row + 2
        guard lineRanges.indices.contains(lineIndex) else { return nil }
        let lineRange = lineRanges[lineIndex]
        let line = ns.substring(with: lineRange)
        return cellContentLocation(inLine: line, lineStart: lineRange.location, column: column)
    }

    public func serialized() -> String {
        var lines: [String] = []
        lines.append(Self.serializedRow(header))
        lines.append(Self.serializedRow(alignments.map(\.separatorCell)))
        lines.append(contentsOf: rows.map(Self.serializedRow))
        return lines.joined(separator: "\n")
    }

    @discardableResult
    public mutating func moveRow(from sourceIndex: Int, to destinationIndex: Int) -> Bool {
        guard rows.indices.contains(sourceIndex), rows.indices.contains(destinationIndex) else { return false }
        if sourceIndex == destinationIndex { return true }
        let row = rows.remove(at: sourceIndex)
        rows.insert(row, at: destinationIndex)
        return true
    }

    @discardableResult
    public mutating func insertRow(at index: Int, cells: [String]? = nil) -> Bool {
        let insertionIndex = min(max(index, 0), rows.count)
        rows.insert(Self.padded(cells ?? [], to: columnCount, with: ""), at: insertionIndex)
        return true
    }

    @discardableResult
    public mutating func removeRow(at index: Int) -> Bool {
        guard rows.indices.contains(index) else { return false }
        rows.remove(at: index)
        return true
    }

    @discardableResult
    public mutating func moveColumn(from sourceIndex: Int, to destinationIndex: Int) -> Bool {
        guard header.indices.contains(sourceIndex), header.indices.contains(destinationIndex) else { return false }
        if sourceIndex == destinationIndex { return true }
        moveElement(in: &header, from: sourceIndex, to: destinationIndex)
        moveElement(in: &alignments, from: sourceIndex, to: destinationIndex)
        for rowIndex in rows.indices {
            moveElement(in: &rows[rowIndex], from: sourceIndex, to: destinationIndex)
        }
        return true
    }

    @discardableResult
    public mutating func insertColumn(
        at index: Int,
        header headerCell: String = "",
        alignment: MarkdownTableAlignment = .left,
        cells: [String] = []
    ) -> Bool {
        let insertionIndex = min(max(index, 0), columnCount)
        header.insert(headerCell, at: insertionIndex)
        alignments.insert(alignment, at: insertionIndex)
        for rowIndex in rows.indices {
            let cell = cells.indices.contains(rowIndex) ? cells[rowIndex] : ""
            rows[rowIndex].insert(cell, at: insertionIndex)
        }
        return true
    }

    @discardableResult
    public mutating func removeColumn(at index: Int) -> Bool {
        guard columnCount > 1, header.indices.contains(index) else { return false }
        header.remove(at: index)
        alignments.remove(at: index)
        for rowIndex in rows.indices where rows[rowIndex].indices.contains(index) {
            rows[rowIndex].remove(at: index)
        }
        return true
    }

    @discardableResult
    public mutating func setCell(row: Int, column: Int, value: String) -> Bool {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return false }
        rows[row][column] = value
        return true
    }

    @discardableResult
    public mutating func setHeader(column: Int, value: String) -> Bool {
        guard header.indices.contains(column) else { return false }
        header[column] = value
        return true
    }

    @discardableResult
    public mutating func setAlignment(column: Int, value: MarkdownTableAlignment) -> Bool {
        guard alignments.indices.contains(column) else { return false }
        alignments[column] = value
        return true
    }

    private static func parseRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }

        var cells: [String] = []
        var current = ""
        var escaping = false
        for ch in s {
            if escaping {
                current.append(ch)
                escaping = false
            } else if ch == "\\" {
                escaping = true
            } else if ch == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(ch)
            }
        }
        if escaping { current.append("\\") }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count >= 3
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = parseRow(line)
        return !cells.isEmpty && cells.allSatisfy { parseAlignment($0) != nil }
    }

    private static func columnIndex(at caret: Int, in line: String, lineStart: Int) -> Int? {
        let lineRelative = max(0, caret - lineStart)
        let ns = line as NSString
        var end = ns.length
        while end > 0 {
            let ch = ns.character(at: end - 1)
            guard ch == 0x0A || ch == 0x0D || ch == 0x20 || ch == 0x09 else { break }
            end -= 1
        }
        var i = 0
        while i < end {
            let ch = ns.character(at: i)
            guard ch == 0x20 || ch == 0x09 else { break }
            i += 1
        }
        if i < end, ns.character(at: i) == 0x7C { i += 1 }
        var column = 0
        var escaping = false
        while i < end {
            let ch = ns.character(at: i)
            if !escaping, ch == 0x7C {
                if lineRelative <= i { return column }
                column += 1
            } else if !escaping, ch == 0x5C {
                escaping = true
            } else {
                escaping = false
            }
            i += 1
        }
        return max(0, column)
    }

    private static func cellContentLocation(inLine line: String, lineStart: Int, column: Int) -> Int? {
        let targetColumn = max(0, column)
        let ns = line as NSString
        var end = ns.length
        while end > 0 {
            let ch = ns.character(at: end - 1)
            guard ch == 0x0A || ch == 0x0D || ch == 0x20 || ch == 0x09 else { break }
            end -= 1
        }

        var i = 0
        while i < end {
            let ch = ns.character(at: i)
            guard ch == 0x20 || ch == 0x09 else { break }
            i += 1
        }
        if i < end, ns.character(at: i) == 0x7C { i += 1 }

        var currentColumn = 0
        var cellStart = i
        var escaping = false
        while i < end {
            let ch = ns.character(at: i)
            if !escaping, ch == 0x7C {
                if currentColumn == targetColumn {
                    return lineStart + trimmedCellStart(in: ns, start: cellStart, end: i)
                }
                currentColumn += 1
                cellStart = i + 1
            } else if !escaping, ch == 0x5C {
                escaping = true
            } else {
                escaping = false
            }
            i += 1
        }

        guard currentColumn == targetColumn else { return nil }
        return lineStart + trimmedCellStart(in: ns, start: cellStart, end: end)
    }

    private static func trimmedCellStart(in ns: NSString, start: Int, end: Int) -> Int {
        var location = start
        while location < end {
            let ch = ns.character(at: location)
            guard ch == 0x20 || ch == 0x09 else { break }
            location += 1
        }
        return location
    }

    private static func parseAlignment(_ cell: String) -> MarkdownTableAlignment? {
        let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("-"),
              trimmed.allSatisfy({ $0 == "-" || $0 == ":" }) else { return nil }
        let leading = trimmed.hasPrefix(":")
        let trailing = trimmed.hasSuffix(":")
        switch (leading, trailing) {
        case (true, true): return .center
        case (false, true): return .right
        default: return .left
        }
    }

    private static func serializedRow(_ cells: [String]) -> String {
        "| " + cells.map(escapedCell).joined(separator: " | ") + " |"
    }

    private static func escapedCell(_ cell: String) -> String {
        cell
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "|", with: "\\|")
    }

    private static func padded<T>(_ values: [T], to count: Int, with fill: T) -> [T] {
        if values.count == count { return values }
        if values.count > count { return Array(values.prefix(count)) }
        return values + Array(repeating: fill, count: count - values.count)
    }

    private func moveElement<T>(in values: inout [T], from sourceIndex: Int, to destinationIndex: Int) {
        let value = values.remove(at: sourceIndex)
        values.insert(value, at: destinationIndex)
    }
}

public struct MarkdownTableSourceSelection: Sendable, Equatable {
    public let range: NSRange
    public let table: MarkdownTable
    /// Zero-based body row index. `nil` means the caret is in the header or separator row.
    public let selectedRow: Int?
    public let selectedColumn: Int?

    public init(range: NSRange, table: MarkdownTable, selectedRow: Int?, selectedColumn: Int?) {
        self.range = range
        self.table = table
        self.selectedRow = selectedRow
        self.selectedColumn = selectedColumn
    }
}

private extension MarkdownTableAlignment {
    var separatorCell: String {
        switch self {
        case .left: return "---"
        case .center: return ":---:"
        case .right: return "---:"
        }
    }
}

private func union(_ ranges: ArraySlice<NSRange>) -> NSRange {
    guard let first = ranges.first, let last = ranges.last else { return NSRange(location: 0, length: 0) }
    return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
}
