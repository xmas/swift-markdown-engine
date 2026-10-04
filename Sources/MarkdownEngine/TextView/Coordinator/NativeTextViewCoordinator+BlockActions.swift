//
//  NativeTextViewCoordinator+BlockActions.swift
//  MarkdownEngine
//
//  Lists and tables from a toolbar or menu, as one undoable edit each.
//
//  A list toggle works on every line the selection touches: when they are
//  all already that kind of list it takes the prefix off, otherwise it makes
//  each non-blank line that kind (replacing another list kind, keeping the
//  indent, numbering an ordered list 1, 2, 3…). Tables: insert a small one,
//  or add a row under / a column after the caret's cell.
//

import AppKit

public enum MarkdownListKind: Sendable {
    case bullet, ordered, task
}

extension NativeTextViewCoordinator {
    private static let listPrefix = try! NSRegularExpression(
        pattern: #"^([ \t]*)(- \[[ xX]\] |[-*+] |\d+[.)] )?"#
    )

    private static func kind(ofPrefix prefix: String) -> MarkdownListKind? {
        if prefix.isEmpty { return nil }
        if prefix.hasPrefix("- [") { return .task }
        if let first = prefix.first, first.isNumber { return .ordered }
        return .bullet
    }

    /// Makes the selected lines `kind` list items, or plain lines when they all are.
    public func toggleList(_ kind: MarkdownListKind) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let selection = tv.selectedRange()
        let block = ns.lineRange(for: selection)
        let original = ns.substring(with: block)
        var lines = original.components(separatedBy: "\n")
        let endsWithNewline = original.hasSuffix("\n")
        if endsWithNewline { lines.removeLast() }

        struct Line { var indent: String; var prefix: String; var body: String }
        let parsed: [Line] = lines.map { line in
            let l = line as NSString
            let m = Self.listPrefix.firstMatch(in: line, range: NSRange(location: 0, length: l.length))!
            let indent = l.substring(with: m.range(at: 1))
            let prefix = m.range(at: 2).location == NSNotFound ? "" : l.substring(with: m.range(at: 2))
            return Line(indent: indent, prefix: prefix, body: l.substring(from: m.range.length))
        }
        let content = parsed.filter { !($0.prefix.isEmpty && $0.body.trimmingCharacters(in: .whitespaces).isEmpty) }
        let allAlready = !content.isEmpty && content.allSatisfy { Self.kind(ofPrefix: $0.prefix) == kind }

        var number = 0
        let rebuilt: [String] = parsed.map { line in
            let blank = line.prefix.isEmpty && line.body.trimmingCharacters(in: .whitespaces).isEmpty
            if blank && parsed.count > 1 { return line.indent + line.body }
            if allAlready { return line.indent + line.body }
            number += 1
            let prefix: String
            switch kind {
            case .bullet: prefix = "- "
            case .ordered: prefix = "\(number). "
            case .task: prefix = line.prefix.hasPrefix("- [x") || line.prefix.hasPrefix("- [X") ? line.prefix : "- [ ] "
            }
            return line.indent + prefix + line.body
        }
        let replacement = rebuilt.joined(separator: "\n") + (endsWithNewline ? "\n" : "")
        guard replacement != original, tv.shouldChangeText(in: block, replacementString: replacement) else { return }
        tv.replaceCharacters(in: block, with: replacement)
        tv.didChangeText()

        if parsed.count == 1 {
            // One line: the caret keeps its place in the words.
            let shift = (rebuilt[0] as NSString).length - (lines[0] as NSString).length
            let oldPrefixEnd = block.location + (parsed[0].indent + parsed[0].prefix as NSString).length
            let location = selection.location >= oldPrefixEnd ? selection.location + shift : block.location + (rebuilt[0] as NSString).length - (parsed[0].body as NSString).length
            tv.setSelectedRange(NSRange(location: max(block.location, location), length: selection.length))
        } else {
            tv.setSelectedRange(NSRange(location: block.location, length: (replacement as NSString).length - (endsWithNewline ? 1 : 0)))
        }
    }

    @objc func didMarkdownTaskList(_ sender: Any?) { toggleList(.task) }

    // MARK: Tables

    /// A table of `columns` × (header + `rows`) on lines of its own, the
    /// caret in its first header cell.
    @objc func didMarkdownTable(_ sender: Any?) { insertTable(columns: 3, rows: 2) }

    public func insertTable(columns: Int, rows: Int) {
        guard let tv = textView, columns > 0 else { return }
        let ns = tv.string as NSString
        let selection = tv.selectedRange()
        let row = "|" + String(repeating: "   |", count: columns)
        let rule = "|" + String(repeating: "---|", count: columns)
        var table = ([row, rule] + Array(repeating: row, count: max(rows, 1))).joined(separator: "\n")
        var at = NSMaxRange(selection)
        // Its own block: after the caret's line, with a blank line around it.
        if at < ns.length || (at > 0 && ns.character(at: at - 1) != 0x0A) {
            let line = ns.lineRange(for: NSRange(location: at, length: 0))
            at = NSMaxRange(line)
        }
        var prefix = ""
        if at > 0 {
            if ns.character(at: at - 1) != 0x0A { prefix = "\n\n" }
            else if at > 1, ns.character(at: at - 2) != 0x0A,
                    !ns.substring(with: ns.lineRange(for: NSRange(location: at - 1, length: 0))).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                prefix = "\n"
            }
        }
        table = prefix + table + "\n"
        if at < ns.length, ns.character(at: at) != 0x0A { table += "\n" }
        let range = NSRange(location: at, length: 0)
        guard tv.shouldChangeText(in: range, replacementString: table) else { return }
        tv.replaceCharacters(in: range, with: table)
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: at + (prefix as NSString).length + 2, length: 0))
    }

    /// The table lines around the caret, with the caret's row and column.
    private func tableAtCaret() -> (lines: [NSRange], row: Int, column: Int)? {
        guard let tv = textView else { return nil }
        let ns = tv.string as NSString
        let caret = tv.selectedRange().location
        func isTableLine(_ r: NSRange) -> Bool {
            ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("|")
        }
        let here = ns.lineRange(for: NSRange(location: min(caret, max(ns.length - 1, 0)), length: 0))
        guard ns.length > 0, isTableLine(here) else { return nil }
        var lines = [here]
        var up = here.location
        while up > 0 {
            let prev = ns.lineRange(for: NSRange(location: up - 1, length: 0))
            guard isTableLine(prev) else { break }
            lines.insert(prev, at: 0); up = prev.location
        }
        var down = NSMaxRange(here)
        while down < ns.length {
            let next = ns.lineRange(for: NSRange(location: down, length: 0))
            guard isTableLine(next) else { break }
            lines.append(next); down = NSMaxRange(next)
        }
        guard lines.count >= 2 else { return nil }
        let row = lines.firstIndex(where: { NSEqualRanges($0, here) })!
        let before = ns.substring(with: NSRange(location: here.location, length: caret - here.location))
        let column = max(0, before.filter { $0 == "|" }.count - 1)
        return (lines, row, column)
    }

    private static func cells(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|")
    }

    private static func line(_ cells: [String]) -> String { "|" + cells.joined(separator: "|") + "|" }

    /// A blank row under the caret's row (under the rule when on the header).
    @objc func didMarkdownTableAddRow(_ sender: Any?) {
        guard let tv = textView, let table = tableAtCaret() else { return NSSound.beep() }
        let ns = tv.string as NSString
        let after = table.lines[max(table.row, 1)]
        let columns = Self.cells(ns.substring(with: table.lines[0])).count
        let row = Self.line(Array(repeating: "   ", count: columns))
        let atEnd = NSMaxRange(after) == ns.length && ns.substring(with: after).hasSuffix("\n") == false
        let insertion = atEnd ? "\n" + row : row + "\n"
        let range = NSRange(location: NSMaxRange(after), length: 0)
        guard tv.shouldChangeText(in: range, replacementString: insertion) else { return }
        tv.replaceCharacters(in: range, with: insertion)
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: NSMaxRange(after) + (atEnd ? 1 : 0) + 2, length: 0))
    }

    /// A blank column after the caret's column, in every row.
    @objc func didMarkdownTableAddColumn(_ sender: Any?) {
        guard let tv = textView, let table = tableAtCaret() else { return NSSound.beep() }
        let ns = tv.string as NSString
        let whole = NSRange(location: table.lines[0].location,
                            length: NSMaxRange(table.lines[table.lines.count - 1]) - table.lines[0].location)
        let original = ns.substring(with: whole)
        let endsWithNewline = original.hasSuffix("\n")
        var rows = original.components(separatedBy: "\n")
        if endsWithNewline { rows.removeLast() }
        rows = rows.enumerated().map { i, line in
            var cells = Self.cells(line)
            let at = min(table.column + 1, cells.count)
            cells.insert(i == 1 ? "---" : "   ", at: at)
            return Self.line(cells)
        }
        let replacement = rows.joined(separator: "\n") + (endsWithNewline ? "\n" : "")
        guard tv.shouldChangeText(in: whole, replacementString: replacement) else { return }
        tv.replaceCharacters(in: whole, with: replacement)
        tv.didChangeText()
        // The caret into the new cell on its own row.
        let rowLine = rows[table.row] as NSString
        var pipes = 0, offset = 0
        for i in 0..<rowLine.length where rowLine.character(at: i) == 0x7C {
            pipes += 1
            if pipes == table.column + 2 { offset = i + 2; break }
        }
        let rowStart = whole.location + rows[..<table.row].reduce(0) { $0 + ($1 as NSString).length + 1 }
        tv.setSelectedRange(NSRange(location: min(rowStart + offset, (tv.string as NSString).length), length: 0))
    }
}
