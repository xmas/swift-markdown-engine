//
//  NativeTextViewCoordinator+LinkEditing.swift
//  MarkdownEngine
//
//  With syntax hidden a link's address never shows in the text, so it is
//  edited beside it: the context menu offers Edit Link… and Remove Link on
//  a link, Add Link… on a selection, and `didMarkdownLinkPrompt:` (for a
//  toolbar) does whichever fits the caret. The address is asked for in a
//  small sheet; the text stays markdown, `[words](address)`.
//

import AppKit

extension NativeTextViewCoordinator {
    /// The markdown link at a character, if any.
    func markdownLink(at index: Int, in text: String) -> MarkdownToken? {
        parsedDocument(for: text).tokens.first { token in
            token.kind == .link && token.markerRanges.count >= 4
                && index >= token.range.location && index < NSMaxRange(token.range)
        }
    }

    private func urlRange(of link: MarkdownToken) -> NSRange {
        let open = NSMaxRange(link.markerRanges[2])
        return NSRange(location: open, length: link.markerRanges[3].location - open)
    }

    /// The link's address, as written.
    public func linkAddress(at index: Int) -> String? {
        guard let tv = textView, let link = markdownLink(at: index, in: tv.string) else { return nil }
        return (tv.string as NSString).substring(with: urlRange(of: link))
    }

    /// Gives the link at `index` a new address; an empty one removes the link.
    public func setLinkAddress(_ address: String, at index: Int) {
        guard let tv = textView, let link = markdownLink(at: index, in: tv.string) else { return }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return removeLink(at: index) }
        replace(urlRange(of: link), with: trimmed, in: tv)
    }

    /// The link at `index` becomes its words.
    public func removeLink(at index: Int) {
        guard let tv = textView, let link = markdownLink(at: index, in: tv.string) else { return }
        let words = (tv.string as NSString).substring(with: link.contentRange)
        replace(link.range, with: words, in: tv)
        tv.setSelectedRange(NSRange(location: link.range.location + (words as NSString).length, length: 0))
    }

    /// The selection (or `fallback` words) becomes a link to `address`.
    public func addLink(_ address: String, fallbackText: String = "link") {
        guard let tv = textView else { return }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let selection = tv.selectedRange()
        let ns = tv.string as NSString
        let words = selection.length > 0 ? ns.substring(with: selection) : fallbackText
        let markdown = "[\(words)](\(trimmed))"
        replace(selection, with: markdown, in: tv)
        tv.setSelectedRange(NSRange(location: selection.location + (markdown as NSString).length, length: 0))
    }

    private func replace(_ range: NSRange, with text: String, in tv: NSTextView) {
        guard tv.shouldChangeText(in: range, replacementString: text) else { return }
        tv.replaceCharacters(in: range, with: text)
        tv.didChangeText()
    }

    // MARK: The menu and the sheet

    /// Edit Link… / Remove Link on a link, Add Link… on a selection — at the
    /// top of the menu, while syntax is hidden.
    func addLinkItems(to menu: NSMenu, at charIndex: Int, in tv: NSTextView) {
        guard !configuration.revealsSyntax, tv.isEditable else { return }
        var items: [NSMenuItem] = []
        if markdownLink(at: charIndex, in: tv.string) != nil {
            let edit = NSMenuItem(title: "Edit Link…", action: #selector(editLinkFromMenu(_:)), keyEquivalent: "")
            let remove = NSMenuItem(title: "Remove Link", action: #selector(removeLinkFromMenu(_:)), keyEquivalent: "")
            for item in [edit, remove] { item.target = self; item.representedObject = charIndex }
            items = [edit, remove]
        } else if tv.selectedRange().length > 0 {
            let add = NSMenuItem(title: "Add Link…", action: #selector(didMarkdownLinkPrompt(_:)), keyEquivalent: "")
            add.target = self
            items = [add]
        }
        guard !items.isEmpty else { return }
        items.append(.separator())
        for (i, item) in items.enumerated() { menu.insertItem(item, at: i) }
    }

    @objc func editLinkFromMenu(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        promptForLink(at: index)
    }

    @objc func removeLinkFromMenu(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        removeLink(at: index)
    }

    /// For a toolbar: edit the link at the caret, else link the selection.
    @objc func didMarkdownLinkPrompt(_ sender: Any?) {
        guard let tv = textView else { return }
        let caret = tv.selectedRange().location
        if markdownLink(at: caret, in: tv.string) != nil || (caret > 0 && markdownLink(at: caret - 1, in: tv.string) != nil) {
            promptForLink(at: markdownLink(at: caret, in: tv.string) != nil ? caret : caret - 1)
        } else {
            promptForLink(at: nil)
        }
    }

    /// The address sheet: prefilled when editing, the pasteboard's link when adding.
    private func promptForLink(at index: Int?) {
        guard let tv = textView else { return }
        let current = index.flatMap(linkAddress(at:))
        let alert = NSAlert()
        alert.messageText = current == nil ? "Add Link" : "Edit Link"
        alert.informativeText = "The address the words link to."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "https://"
        if let current {
            field.stringValue = current
        } else if let copied = NSPasteboard.general.string(forType: .string),
                  let url = URL(string: copied.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme != nil {
            field.stringValue = url.absoluteString
        }
        alert.accessoryView = field
        alert.addButton(withTitle: current == nil ? "Add" : "Save")
        alert.addButton(withTitle: "Cancel")
        if current != nil { alert.addButton(withTitle: "Remove Link") }
        alert.window.initialFirstResponder = field
        let selection = tv.selectedRange()
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            tv.window?.makeFirstResponder(tv)
            switch response {
            case .alertFirstButtonReturn:
                if let index { self.setLinkAddress(field.stringValue, at: index) }
                else { tv.setSelectedRange(selection); self.addLink(field.stringValue) }
            case .alertThirdButtonReturn:
                if let index { self.removeLink(at: index) }
            default: break
            }
        }
        if let window = tv.window {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }
}
