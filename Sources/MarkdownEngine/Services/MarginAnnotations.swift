//
//  MarginAnnotations.swift
//  MarkdownEngine
//
//  Margin annotations: an embedder can pull tokens out of a list item's line
//  and set them in the page's side margins instead — a due date in the
//  leading margin, a person in the trailing one — the way an outliner keeps
//  dates and owners in columns beside the text.
//
//  The text never changes. A folded token stays in storage and shrinks to the
//  hidden-marker font (see `MarkerStyle`), exactly like inactive syntax: it
//  comes back while the caret is on its line so it can be edited, and a range
//  folded `always` (an embedder's own identifier, say) never shows at all and
//  is stepped over by the caret as one unit.
//
//  The margins live inside the text view's horizontal `textInsets`: give the
//  editor insets at least `MarginStyle.gap + width` on each side.
//

import AppKit
import Foundation

/// One side of the text column.
public enum MarginSide: Sendable, Equatable {
    case leading, trailing
}

/// What the embedder says about one list item's line.
public struct MarginAnnotation: @unchecked Sendable {
    /// Drawn right-aligned in the leading margin, on the line's first baseline.
    public var leading: NSAttributedString?
    /// Drawn left-aligned in the trailing margin, on the line's first baseline.
    public var trailing: NSAttributedString?
    /// Shown faintly in an empty margin while the pointer is over it — the
    /// invitation to click and fill it ("Date", "Assign").
    public var leadingPrompt: NSAttributedString?
    public var trailingPrompt: NSAttributedString?
    /// Absolute ranges hidden while the caret is off the line. Include the
    /// space before a token so the sentence closes up around it.
    public var folded: [NSRange]
    /// Absolute ranges hidden always; the caret steps over each as one unit.
    public var alwaysFolded: [NSRange]
    /// A font for the item's text (a parent item set heavier, say); inline
    /// emphasis composes on top of it. nil keeps the body font.
    public var font: NSFont?
    /// A foreground colour for the item's text; nil keeps the theme's.
    public var textColor: NSColor?

    public init(
        leading: NSAttributedString? = nil,
        trailing: NSAttributedString? = nil,
        leadingPrompt: NSAttributedString? = nil,
        trailingPrompt: NSAttributedString? = nil,
        folded: [NSRange] = [],
        alwaysFolded: [NSRange] = [],
        font: NSFont? = nil,
        textColor: NSColor? = nil
    ) {
        self.leading = leading
        self.trailing = trailing
        self.leadingPrompt = leadingPrompt
        self.trailingPrompt = trailingPrompt
        self.folded = folded
        self.alwaysFolded = alwaysFolded
        self.font = font
        self.textColor = textColor
    }
}

/// Supplies margin annotations for list items, and an icon for links.
///
/// Called synchronously while styling — keep it cheap, like the other services.
public protocol MarginAnnotator: Sendable {
    /// The annotation for one list item. `line` is the item's line without
    /// its line break, in absolute document coordinates; `text` is the whole
    /// document, so the embedder can look at neighbouring lines.
    func annotation(forLine line: NSRange, in text: NSString) -> MarginAnnotation?

    /// A small template image drawn before a link's text (tinted with the
    /// link colour), or nil for a plain link. `url` is the link's destination
    /// as written.
    func linkIcon(for url: String) -> NSImage?

    /// Coarse fingerprint of whatever the annotations depend on besides the
    /// text (today's date, the people the embedder knows). A different value
    /// restyles the document.
    func fingerprint() -> AnyHashable
}

public extension MarginAnnotator {
    func linkIcon(for url: String) -> NSImage? { nil }
    func fingerprint() -> AnyHashable { 0 }
}

/// A click in a margin, handed to ``NativeTextViewWrapper/onMarginClick``.
public struct MarginClick {
    public let side: MarginSide
    /// The item's line without its line break.
    public let line: NSRange
    /// The margin cell that was clicked, in `view`'s coordinates — anchor a
    /// popover on it.
    public let rect: CGRect
    /// The text view.
    public let view: NSView
}

/// Where the margins sit around the text column.
public struct MarginStyle: Sendable {
    /// Space between the text column and each margin.
    public var gap: CGFloat
    /// Width of the leading margin (its labels are right-aligned against the gap).
    public var leadingWidth: CGFloat
    /// Width of the trailing margin.
    public var trailingWidth: CGFloat
    /// Room a link icon takes before the link's text, icon and gap together.
    public var linkIconAdvance: CGFloat

    public init(gap: CGFloat = 20, leadingWidth: CGFloat = 112, trailingWidth: CGFloat = 112, linkIconAdvance: CGFloat = 19) {
        self.gap = gap
        self.leadingWidth = leadingWidth
        self.trailingWidth = trailingWidth
        self.linkIconAdvance = linkIconAdvance
    }

    public static let `default` = MarginStyle()
}

extension NSAttributedString.Key {
    /// A `MarginAnnotationBox` over a list item's whole line.
    static let marginAnnotation = NSAttributedString.Key("MarkdownMarginAnnotation")
    /// On the `[` of an inactive link whose URL has an icon: the `NSImage`.
    static let linkIcon = NSAttributedString.Key("MarkdownLinkIcon")
}

/// Reference wrapper so one annotation spans its whole line as one attribute run.
final class MarginAnnotationBox: NSObject {
    let annotation: MarginAnnotation
    init(_ annotation: MarginAnnotation) { self.annotation = annotation }
}
