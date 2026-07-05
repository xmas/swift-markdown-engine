//
//  MermaidTests.swift
//  MarkdownEngineTests
//

import AppKit
import Testing
@testable import MarkdownEngine

private struct TestMermaidRenderer: MermaidRenderer {
    func render(mermaid: String, fontSize: CGFloat, theme: MarkdownEditorTheme) -> MermaidRenderResult? {
        let image = NSImage(size: NSSize(width: 80, height: 40))
        return MermaidRenderResult(image: image, size: image.size)
    }
}

@MainActor
@Suite("Mermaid fenced blocks")
struct MermaidTests {

    @Test func mermaidFenceReceivesDedicatedTokenKind() {
        let text = "```mermaid\ngraph TD\nA-->B\n```\n"
        let tokens = MarkdownTokenizer.parseTokensViaAST(in: text)
        #expect(tokens.count == 1)
        #expect(tokens.first?.kind == .mermaidBlock)
        #expect(MarkdownTokenizer.extractLanguage(from: tokens[0], in: text) == "mermaid")
    }

    @Test func mermaidBlocksRemainCodeLikeForDetection() {
        let text = "```mermaid\ngraph TD\nA-->B\n```\n"
        #expect(MarkdownDetection.isInsideCodeBlock(location: 15, in: text))
    }

    @Test func injectedRendererCollapsesInactiveMermaidBlock() {
        _ = NSApplication.shared
        let text = "```mermaid\ngraph TD\nA-->B\n```\n"
        let cfg = MarkdownEditorConfiguration(
            services: MarkdownEditorServices(mermaid: TestMermaidRenderer())
        )
        let attrs = MarkdownStyler.styleAttributes(
            text: text,
            fontName: "Helvetica",
            fontSize: 14,
            caretLocation: -1,
            activeTokenIndices: [],
            configuration: cfg
        )
        #expect(attrs.contains { _, attributes in attributes[.latexImage] is NSImage })
    }
}
