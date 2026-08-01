import Markdown
import SwiftUI

/// A deliberately small Markdown rendering boundary.  `swift-markdown` parses
/// caller-owned text only; this visitor never creates URLs, images, attachments
/// or HTML views.  Links and images contribute their local label/alt text.
public enum SafeMarkdownRenderer {
    public static func render(_ source: String) -> AttributedString {
        var visitor = Visitor()
        visitor.render(Document(parsing: source))
        return visitor.output.characters.isEmpty ? AttributedString(source) : visitor.output
    }

    private struct Visitor {
        var output = AttributedString()

        mutating func render(_ markup: Markup, intent: InlinePresentationIntent? = nil) {
            if let text = markup as? Markdown.Text {
                append(text.string, intent: intent)
            } else if let code = markup as? InlineCode {
                append(code.code, intent: combined(intent, .code))
            } else if let strong = markup as? Strong {
                renderChildren(of: strong, intent: combined(intent, .stronglyEmphasized))
            } else if let emphasis = markup as? Emphasis {
                renderChildren(of: emphasis, intent: combined(intent, .emphasized))
            } else if let strike = markup as? Strikethrough {
                renderChildren(of: strike, intent: combined(intent, .strikethrough))
            } else if let link = markup as? Markdown.Link {
                renderChildren(of: link, intent: intent)
            } else if let image = markup as? Markdown.Image {
                renderChildren(of: image, intent: intent)
            } else if markup is InlineHTML || markup is HTMLBlock || markup is CodeBlock {
                return
            } else if markup is Paragraph || markup is Heading || markup is ListItem || markup is BlockQuote {
                if !output.characters.isEmpty { append("\n", intent: nil) }
                renderChildren(of: markup, intent: intent)
            } else if markup is SoftBreak || markup is LineBreak {
                append("\n", intent: intent)
            } else {
                renderChildren(of: markup, intent: intent)
            }
        }

        private mutating func renderChildren(of markup: Markup, intent: InlinePresentationIntent?) {
            for child in markup.children { render(child, intent: intent) }
        }

        private mutating func append(_ string: String, intent: InlinePresentationIntent?) {
            var fragment = AttributedString(string)
            if let intent { fragment.inlinePresentationIntent = intent }
            output += fragment
        }

        private func combined(_ lhs: InlinePresentationIntent?, _ rhs: InlinePresentationIntent) -> InlinePresentationIntent {
            (lhs ?? []).union(rhs)
        }
    }
}

public struct SafeMarkdownText: View {
    private let markdown: String
    private let strikethrough: Bool
    private let selectable: Bool

    public init(_ markdown: String, strikethrough: Bool = false, selectable: Bool = true) {
        self.markdown = markdown
        self.strikethrough = strikethrough
        self.selectable = selectable
    }

    private var renderedText: SwiftUI.Text {
        SwiftUI.Text(SafeMarkdownRenderer.render(markdown))
            .font(AppTheme.Typography.body)
            .strikethrough(strikethrough)
    }

    @ViewBuilder public var body: some View {
        if selectable {
            renderedText.textSelection(.enabled)
        } else {
            renderedText
        }
    }
}
