//
//  NativeTextView+ImageResize.swift
//  MarkdownEngine
//
//  A drawn `![alt](url)` picture resizes from a handle on its right edge.
//  Hovering the picture shows the handle; dragging it draws a ghost of the
//  new size with its width in points (the picture itself isn't redrawn per
//  frame), snapping to the picture's own size, the column, ½ and ⅓ of it
//  (⌥ frees it). Letting go writes the width into the alt — `![|480](url)`,
//  Obsidian's way — as one undoable edit; a double-click on the handle takes
//  it out, back to the picture's own size.
//

import AppKit

/// A picture the pointer can resize: where its source is, where it is drawn
/// (text-view coordinates), and its own width.
struct ResizableImage {
    var location: Int
    var rect: CGRect
    var naturalWidth: CGFloat
}

extension NativeTextView {
    // MARK: Finding

    /// The drawn picture at (or just beside) a point, in view coordinates.
    func resizableImage(near point: CGPoint) -> ResizableImage? {
        guard let tlm = textLayoutManager, let storage = textStorage, storage.length > 0 else { return nil }
        // Cheap no: a note without pictures never walks its fragments.
        var any = false
        storage.enumerateAttribute(.resizableImageWidth, in: NSRange(location: 0, length: storage.length)) { value, _, stop in
            if value != nil { any = true; stop.pointee = true }
        }
        guard any else { return nil }
        var hit: ResizableImage?
        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: []) { fragment in
            let frame = fragment.layoutFragmentFrame
            let origin = CGPoint(x: frame.minX + textContainerOrigin.x, y: frame.minY + textContainerOrigin.y)
            // Past the point by more than a tall picture could reach: stop.
            if origin.y > point.y + 4 { return false }
            guard let markdown = fragment as? MarkdownTextLayoutFragment else { return true }
            for image in markdown.resizableImages() {
                let rect = image.rect.offsetBy(dx: origin.x, dy: origin.y)
                if rect.insetBy(dx: -12, dy: -2).contains(point) {
                    hit = ResizableImage(location: image.location, rect: rect, naturalWidth: image.naturalWidth)
                    return false
                }
            }
            return true
        }
        return hit
    }

    /// The widest a picture may be drawn: the text container's measure.
    var imageColumnWidth: CGFloat {
        guard let container = textContainer else { return bounds.width }
        return max(50, container.size.width - container.lineFragmentPadding * 2)
    }

    // MARK: The handle

    func updateImageResizeHandle(for event: NSEvent) {
        guard isEditable, window != nil else { return removeImageResizeHandle() }
        let point = convert(event.locationInWindow, from: nil)
        if let handle = imageResizeHandle, handle.frame.insetBy(dx: -4, dy: -4).contains(point) { return }
        guard let image = resizableImage(near: point) else { return removeImageResizeHandle() }
        let handle = imageResizeHandle ?? {
            let made = ImageResizeHandle(frame: .zero)
            made.owner = self
            addSubview(made)
            imageResizeHandle = made
            return made
        }()
        handle.image = image
        handle.frame = ImageResizeHandle.frame(for: image.rect)
        handle.needsDisplay = true
    }

    func removeImageResizeHandle() {
        imageResizeHandle?.removeFromSuperview()
        imageResizeHandle = nil
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        let point = convert(event.locationInWindow, from: nil)
        if let handle = imageResizeHandle, !handle.frame.insetBy(dx: -4, dy: -4).contains(point) {
            removeImageResizeHandle()
        }
    }

    // MARK: Dragging

    /// The snaps a width is drawn to: the picture's own size, the column, ½, ⅓.
    func imageSnapWidths(natural: CGFloat) -> [CGFloat] {
        let column = imageColumnWidth
        return [min(natural, column), column, column / 2, column / 3]
    }

    func trackImageResize(_ image: ResizableImage, from event: NSEvent) {
        if event.clickCount == 2 {
            writeImageWidth(nil, for: image)
            return
        }
        let start = convert(event.locationInWindow, from: nil).x
        let column = imageColumnWidth
        let aspect = image.rect.width > 0 ? image.rect.height / image.rect.width : 1
        let ghost = ImageResizeGhost(frame: image.rect)
        addSubview(ghost)
        imageResizeHandle?.isHidden = true
        var width = image.rect.width
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let x = convert(next.locationInWindow, from: nil).x
            var proposed = min(max(image.rect.width + (x - start), configuration.imageEmbed.minimumWidth), column)
            if !next.modifierFlags.contains(.option),
               let snap = imageSnapWidths(natural: image.naturalWidth).min(by: { abs($0 - proposed) < abs($1 - proposed) }),
               abs(snap - proposed) <= 8 {
                proposed = snap
            }
            width = proposed.rounded()
            ghost.frame = CGRect(x: image.rect.minX, y: image.rect.minY, width: width, height: width * aspect)
            ghost.label = "\(Int(width)) pt"
            if next.type == .leftMouseUp { break }
        }
        ghost.removeFromSuperview()
        removeImageResizeHandle()
        guard abs(width - image.rect.width) >= 1 else { return }
        // The picture's own size (clamped to the column) is no width at all.
        let natural = min(image.naturalWidth, column)
        writeImageWidth(abs(width - natural) < 0.5 ? nil : Int(width), for: image)
    }

    private static let imageLinkHead = try! NSRegularExpression(pattern: #"!\[([^\]\n]*)\]\("#)

    /// Writes (or, nil, takes out) the width in the picture line's alt, as
    /// one undoable edit; the caret stays where it was.
    func writeImageWidth(_ width: Int?, for image: ResizableImage) {
        let ns = string as NSString
        guard image.location < ns.length else { return }
        let line = ns.paragraphRange(for: NSRange(location: image.location, length: 0))
        guard let match = Self.imageLinkHead.firstMatch(in: ns as String, range: line) else { return }
        let altRange = match.range(at: 1)
        let alt = ns.substring(with: altRange)
        let newAlt = ImageLinkWidth.alt(alt, width: width)
        guard newAlt != alt else { return }
        let selection = selectedRange()
        guard shouldChangeText(in: altRange, replacementString: newAlt) else { return }
        replaceCharacters(in: altRange, with: newAlt)
        didChangeText()
        let shift = (newAlt as NSString).length - altRange.length
        let location = selection.location >= NSMaxRange(altRange) ? selection.location + shift : selection.location
        setSelectedRange(NSRange(location: min(location, (string as NSString).length), length: selection.length))
    }
}

/// The bar on a picture's right edge.
final class ImageResizeHandle: NSView {
    weak var owner: NativeTextView?
    var image: ResizableImage?

    static func frame(for picture: CGRect) -> CGRect {
        let height = min(44, max(24, picture.height / 4))
        // Inside the picture's edge: a picture as wide as the column reaches the
        // text view's own edge, and anything past it is clipped.
        return CGRect(x: picture.maxX - 18, y: picture.midY - height / 2, width: 14, height: height)
    }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let bar = NSRect(x: bounds.midX - 3, y: 0, width: 6, height: bounds.height)
        let path = NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3)
        NSColor.white.withAlphaComponent(0.92).setFill()
        path.fill()
        NSColor.black.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        guard let owner, let image else { return }
        owner.trackImageResize(image, from: event)
    }
}

/// The new size while the handle is dragged, with its width.
final class ImageResizeGhost: NSView {
    var label = "" { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        accent.withAlphaComponent(0.10).setFill()
        bounds.fill()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        border.lineWidth = 2
        accent.setStroke()
        border.stroke()
        guard !label.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let text = label as NSString
        let size = text.size(withAttributes: attrs)
        let pill = NSRect(x: bounds.maxX - size.width - 18, y: bounds.minY + 8, width: size.width + 12, height: size.height + 6)
        accent.setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        text.draw(at: NSPoint(x: pill.minX + 6, y: pill.minY + 3), withAttributes: attrs)
    }
}

extension NativeTextViewCoordinator {
    /// Gives the picture on the line at `location` a width in points (nil: its
    /// own size), as the handle does — for an embedder's command or test.
    public func setImageWidth(_ width: Int?, atLine location: Int) {
        guard let tv = textView as? NativeTextView else { return }
        tv.writeImageWidth(width, for: ResizableImage(location: location, rect: .zero, naturalWidth: 0))
    }

    /// Where the drawn pictures are, in the text view's coordinates, with the
    /// line each sits on — for an embedder's command or test.
    public func drawnImages() -> [(location: Int, rect: CGRect)] {
        guard let tv = textView as? NativeTextView, let tlm = tv.textLayoutManager else { return [] }
        var found: [(Int, CGRect)] = []
        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) { fragment in
            guard let markdown = fragment as? MarkdownTextLayoutFragment else { return true }
            let frame = fragment.layoutFragmentFrame
            for image in markdown.resizableImages() {
                found.append((image.location, image.rect.offsetBy(dx: frame.minX + tv.textContainerOrigin.x,
                                                                 dy: frame.minY + tv.textContainerOrigin.y)))
            }
            return true
        }
        return found
    }
}
