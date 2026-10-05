//
//  TableModel.swift
//  MarkdownEngine
//
//  A pipe table as cells: what the grid editor edits and writes back. Row 0
//  is the header. Every structural change (a row or column in or out) is a
//  value change here; `markdown` is the table written out again.
//

import Foundation

struct TableModel: Equatable {
    var rows: [[String]]
    var alignments: [MarkdownStyler.TableAlignment]

    var columnCount: Int { alignments.count }
    var rowCount: Int { rows.count }

    init(rows: [[String]], alignments: [MarkdownStyler.TableAlignment]) {
        self.rows = rows
        self.alignments = alignments
    }

    init?(source: String) {
        guard let parsed = MarkdownStyler.parseTableSource(source) else { return nil }
        self.init(rows: [parsed.header] + parsed.rows, alignments: parsed.alignments)
    }

    /// A cell's words as they can live in a pipe table: one line, no `|`.
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "∣")
            .trimmingCharacters(in: .whitespaces)
    }

    var markdown: String {
        func line(_ cells: [String]) -> String {
            "| " + cells.map { $0.isEmpty ? " " : $0 }.joined(separator: " | ") + " |"
        }
        let rule = "| " + alignments.map { alignment -> String in
            switch alignment {
            case .left: "---"
            case .center: ":---:"
            case .right: "---:"
            }
        }.joined(separator: " | ") + " |"
        var lines = [line(rows.first ?? Array(repeating: "", count: columnCount)), rule]
        lines += rows.dropFirst().map(line)
        return lines.joined(separator: "\n")
    }

    mutating func set(_ text: String, row: Int, column: Int) {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return }
        rows[row][column] = Self.clean(text)
    }

    /// A blank row at `index` (never above the header).
    mutating func insertRow(at index: Int) {
        rows.insert(Array(repeating: "", count: columnCount), at: min(max(index, 1), rows.count))
    }

    /// Takes a body row out; the header stays.
    mutating func deleteRow(_ index: Int) {
        guard index > 0, rows.indices.contains(index) else { return }
        rows.remove(at: index)
    }

    mutating func insertColumn(at index: Int) {
        let at = min(max(index, 0), columnCount)
        for r in rows.indices { rows[r].insert("", at: min(at, rows[r].count)) }
        alignments.insert(.left, at: at)
    }

    /// Takes a column out; false when it was the last one (the table would be empty).
    @discardableResult
    mutating func deleteColumn(_ index: Int) -> Bool {
        guard columnCount > 1, alignments.indices.contains(index) else { return false }
        for r in rows.indices where rows[r].indices.contains(index) { rows[r].remove(at: index) }
        alignments.remove(at: index)
        return true
    }

    /// The cell a source location falls in: its line's row (the rule line
    /// reads as the first body row, or the header in a header-only table) and
    /// the pipes before it on that line.
    static func cell(at offset: Int, in source: String) -> (row: Int, column: Int) {
        let ns = source as NSString
        let offset = min(max(0, offset), ns.length)
        let before = ns.substring(to: offset)
        let lineIndex = before.components(separatedBy: "\n").count - 1
        let lineStart = (before as NSString).range(of: "\n", options: .backwards).location
        let onLine = lineStart == NSNotFound ? before : (before as NSString).substring(from: lineStart + 1)
        let pipes = onLine.filter { $0 == "|" }.count
        let lineCount = source.components(separatedBy: "\n").count
        let row = lineIndex == 0 ? 0 : (lineIndex == 1 ? (lineCount > 2 ? 1 : 0) : lineIndex - 1)
        return (row, max(0, pipes - 1))
    }
}
