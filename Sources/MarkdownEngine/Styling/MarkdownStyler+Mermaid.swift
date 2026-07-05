//
//  MarkdownStyler+Mermaid.swift
//  MarkdownEngine
//
//  Mermaid fenced-code blocks. The core engine recognizes ```mermaid fences
//  and asks the embedder-provided renderer for an image. Without a renderer,
//  these blocks remain ordinary syntax-highlighted code blocks.
//

import AppKit
import Foundation

extension MarkdownStyler {

    static func styleMermaidBlocks(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        for (idx, token) in ctx.tokens.enumerated() where token.kind == .mermaidBlock {
            attrs.append((token.range, [.spellingState: 0]))

            guard !ctx.activeTokenIndices.contains(idx),
                  token.standaloneParagraphRange(in: ctx.nsText) != nil else { continue }

            let rawDiagram = ctx.nsText.substring(with: token.contentRange)
            let diagram = rawDiagram.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !diagram.isEmpty,
                  let entry = ctx.services.mermaid.render(
                    mermaid: diagram,
                    fontSize: ctx.baseFont.pointSize,
                    theme: ctx.configuration.theme
                  ) else { continue }

            _ = appendRenderedStandaloneBlock(
                for: token,
                rawContent: rawDiagram,
                image: entry.image,
                imageBounds: CGRect(
                    x: 0,
                    y: entry.baselineOffset,
                    width: entry.size.width,
                    height: entry.size.height
                ),
                paragraphSpacingBefore: ctx.baseDefaultLineHeight * 0.5,
                paragraphSpacing: ctx.baseDefaultLineHeight * 0.5,
                alignment: .center,
                mode: .collapsedSource(markerTexts: []),
                ctx: ctx,
                attrs: &attrs
            )
        }
        return attrs
    }
}
