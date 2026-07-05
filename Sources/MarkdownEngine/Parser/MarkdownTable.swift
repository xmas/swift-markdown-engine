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
        var s = line.trimmingCharacters(in: .whitespaces)
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

private extension MarkdownTableAlignment {
    var separatorCell: String {
        switch self {
        case .left: return "---"
        case .center: return ":---:"
        case .right: return "---:"
        }
    }
}
