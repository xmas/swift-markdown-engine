//
//  NativeTextView+Margins.swift
//  MarkdownEngine
//
//  The margins beside list items (`MarginAnnotator`): drawn by a click-through
//  overlay above the text, hovered for their prompts, clicked through to the
//  embedder. The labels hang off each item's first baseline, so they line up
//  with the text whatever the fonts.
//

import AppKit

/// Transparent, click-through layer that draws the margins.
final class MarginOverlayView: NSView {
    weak var textView: NativeTextView?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        textView?.drawMargins(in: dirtyRect)
    }
}

extension NativeTextView {
    /// One annotated item as laid out, in view coordinates.
    struct MarginLine {
        let line: NSRange
        let annotation: MarginAnnotation
        /// The first line's baseline.
        let baseline: CGFloat
        /// The first line's box.
        let top: CGFloat
        let height: CGFloat
    }

    var hasMargins: Bool { configuration.services.margins != nil }

    /// Where the leading margin's labels end and the trailing margin's begin.
    private var marginEdges: (leading: CGFloat, trailing: CGFloat) {
        let gap = configuration.margins.gap
        let width = textContainer?.size.width ?? bounds.width
        return (textContainerOrigin.x - gap, textContainerOrigin.x + width + gap)
    }

    /// The annotated items whose first line meets `rect` (every one when nil).
    func marginLines(in rect: CGRect? = nil) -> [MarginLine] {
        guard hasMargins, let storage = textStorage, storage.length > 0,
              let tlm = textLayoutManager, let tcm = tlm.textContentManager else { return [] }
        let origin = textContainerOrigin
        var out: [MarginLine] = []
        storage.enumerateAttribute(.marginAnnotation, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let box = value as? MarginAnnotationBox,
                  let location = tcm.location(tlm.documentRange.location, offsetBy: range.location),
                  let fragment = tlm.textLayoutFragment(for: location),
                  let first = fragment.textLineFragments.first else { return }
            let frame = fragment.layoutFragmentFrame
            let bounds = first.typographicBounds
            let top = frame.minY + bounds.minY + origin.y
            if let rect, top > rect.maxY || top + bounds.height < rect.minY { return }
            let baseline = top + first.locationForCharacter(at: 0).y
            out.append(MarginLine(line: range, annotation: box.annotation, baseline: baseline, top: top, height: bounds.height))
        }
        return out
    }

    // MARK: Drawing

    /// Keeps the overlay over the text (TextKit adds its own content views as it
    /// goes) and asks it to redraw.
    func refreshMargins() {
        guard hasMargins else {
            marginOverlay?.removeFromSuperview()
            marginOverlay = nil
            return
        }
        let overlay = marginOverlay ?? {
            let view = MarginOverlayView(frame: bounds)
            view.autoresizingMask = [.width, .height]
            view.textView = self
            marginOverlay = view
            return view
        }()
        if subviews.last !== overlay { addSubview(overlay) }
        if overlay.frame != bounds { overlay.frame = bounds }
        overlay.needsDisplay = true
    }

    func drawMargins(in dirtyRect: NSRect) {
        let style = configuration.margins
        let edges = marginEdges
        for m in marginLines(in: dirtyRect) {
            let hover = marginHover?.line == m.line.location ? marginHover?.side : nil
            if let text = m.annotation.leading ?? (hover == .leading ? m.annotation.leadingPrompt : nil) {
                draw(text, width: style.leadingWidth, x: edges.leading - style.leadingWidth, baseline: m.baseline, alignment: .right)
            }
            if let text = m.annotation.trailing ?? (hover == .trailing ? m.annotation.trailingPrompt : nil) {
                draw(text, width: style.trailingWidth, x: edges.trailing, baseline: m.baseline, alignment: .left)
            }
        }
    }

    /// One label, on `baseline`, cut short with an ellipsis if it runs past `width`.
    private func draw(_ text: NSAttributedString, width: CGFloat, x: CGFloat, baseline: CGFloat, alignment: NSTextAlignment) {
        guard text.length > 0 else { return }
        let font = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let para = NSMutableParagraphStyle()
        para.alignment = alignment
        para.lineBreakMode = .byTruncatingTail
        let label = NSMutableAttributedString(attributedString: text)
        label.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: label.length))
        let height = ceil(font.ascender - font.descender + font.leading)
        let rect = CGRect(x: x, y: baseline - font.ascender, width: width, height: height)
        label.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    // MARK: Hover and clicks

    /// The annotated item and margin under `point` (view coordinates), with the cell's rect.
    func marginHit(at point: CGPoint) -> (MarginLine, MarginSide, CGRect)? {
        guard hasMargins else { return nil }
        let style = configuration.margins
        let edges = marginEdges
        let side: MarginSide
        if point.x <= edges.leading + 6, point.x >= edges.leading - style.leadingWidth - 8 {
            side = .leading
        } else if point.x >= edges.trailing - 6, point.x <= edges.trailing + style.trailingWidth + 8 {
            side = .trailing
        } else {
            return nil
        }
        let probe = CGRect(x: 0, y: point.y - 1, width: bounds.width, height: 2)
        guard let m = marginLines(in: probe).first(where: { point.y >= $0.top && point.y <= $0.top + $0.height }) else { return nil }
        let rect = side == .leading
            ? CGRect(x: edges.leading - style.leadingWidth, y: m.top, width: style.leadingWidth, height: m.height)
            : CGRect(x: edges.trailing, y: m.top, width: style.trailingWidth, height: m.height)
        return (m, side, rect)
    }

    func updateMarginHover(for event: NSEvent) {
        guard hasMargins else { return }
        let hit = marginHit(at: convert(event.locationInWindow, from: nil))
        let next = hit.map { (line: $0.0.line.location, side: $0.1) }
        guard next?.line != marginHover?.line || next?.side != marginHover?.side else { return }
        marginHover = next
        refreshMargins()
    }

    /// A click in a margin goes to the embedder; true when it was one.
    func handleMarginClick(_ event: NSEvent) -> Bool {
        guard let onMarginClick, event.clickCount == 1,
              let (m, side, rect) = marginHit(at: convert(event.locationInWindow, from: nil)) else { return false }
        window?.makeFirstResponder(self)
        onMarginClick(MarginClick(side: side, line: m.line, rect: rect, view: self))
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let marginTrackingArea { removeTrackingArea(marginTrackingArea) }
        marginTrackingArea = nil
        guard hasMargins else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        marginTrackingArea = area
    }
}

// MARK: - Folded ranges

extension MarginAnnotator {
    /// The line's always-folded ranges, read fresh from the text.
    func alwaysFolded(at location: Int, in ns: NSString) -> (line: NSRange, ranges: [NSRange])? {
        guard ns.length > 0 else { return nil }
        let para = ns.paragraphRange(for: NSRange(location: min(location, ns.length), length: 0))
        var line = para
        while line.length > 0, [0x0A, 0x0D].contains(ns.character(at: NSMaxRange(line) - 1)) { line.length -= 1 }
        guard line.length > 0, let note = annotation(forLine: line, in: ns), !note.alwaysFolded.isEmpty else { return nil }
        return (line, note.alwaysFolded)
    }
}
