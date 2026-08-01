import EmbercueCore
import SwiftUI

@_spi(Testing) public enum ItemCardPresentation {
    public static func accessibilitySummary(markdown: String) -> String {
        let text = String(SafeMarkdownRenderer.render(markdown).characters)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String(text.prefix(80)).isEmpty ? "Untitled note" : String(text.prefix(80))
    }

    public static func accessibilityValue(selected: Bool, state: LibraryItemState) -> String {
        let status = switch state {
        case .active: "Active"
        case .completed: "Completed"
        case .archived: "Archived"
        }
        return "\(status), \(selected ? "selected" : "not selected")"
    }
}

public struct ItemCard: View {
    let item: EmbercueCore.LibraryItem
    let selected: Bool
    let selectionCount: Int
    let canMerge: Bool
    let expanded: Bool
    let completedEcho: Bool
    let selection: (WorkbenchSelectionMode) -> Void
    let toggleCircle: () -> Void
    let prepareContext: () -> Void
    let command: (WorkbenchCommand) -> Void
    let move: (UUID) -> Void
    let sections: [LibrarySection]
    let attachmentURL: (LibraryAttachment) -> URL?
    @State private var bodyPressed = false
    @State private var circlePressed = false

    public var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.composerGap) {
            selectionCircle
                .overlay {
                    CardSelectionButton(
                        accessibilityIdentifier: circleIdentifier,
                        accessibilityLabel: selected ? "Remove selection from note: \(accessibilitySummary)" : "Add note to selection: \(accessibilitySummary)",
                        selected: selected,
                        fixedPointerMode: .toggle,
                        selection: { _ in toggleCircle() },
                        prepareContext: prepareContext,
                        pressed: $circlePressed
                    )
                    .frame(width: AppTheme.Size.selectionHitTarget, height: AppTheme.Size.selectionHitTarget)
                }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                if !item.text.isEmpty {
                    if expanded {
                        SafeMarkdownText(item.text, strikethrough: completedEcho).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                    } else {
                        SafeMarkdownText(item.text, strikethrough: completedEcho, selectable: false).lineLimit(3).fixedSize(horizontal: false, vertical: true).allowsHitTesting(false)
                    }
                }
                ForEach(item.attachments) { attachment in
                    HStack(spacing: 6) {
                        if let url = attachmentURL(attachment) { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 22, height: 22) }
                        else { Image(systemName: "doc") }
                        Text(attachment.filename).lineLimit(1).font(.caption)
                        Spacer(minLength: 0)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(6).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(AppTheme.Spacing.card)
        .background {
            if expanded { expandedBodySelectionSurface }
        }
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .background(cardSurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: selected ? AppTheme.Stroke.selection : 0)
        }
        .overlay {
            if !expanded { collapsedBodySelectionSurface }
        }
        .overlay {
            CardContextCaptureSurface(identifier: contextIdentifier, prepareContext: prepareContext)
                .contextMenu { menu }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("item-card-\(item.id.uuidString)")
        .accessibilityLabel("Note: \(accessibilitySummary)")
        .accessibilityValue(ItemCardPresentation.accessibilityValue(selected: selected, state: item.state))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var selectionCircle: some View {
        let checked = selected || completedEcho
        return Image(systemName: checked ? "checkmark" : "")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: AppTheme.Size.selectionCircle, height: AppTheme.Size.selectionCircle)
            .background(checked ? Color.accentColor : Color.clear, in: Circle())
            .overlay(Circle().stroke(checked ? Color.accentColor : Color.secondary.opacity(0.55), lineWidth: AppTheme.Stroke.circle))
            .opacity(circlePressed ? 0.65 : 1)
    }

    private var collapsedBodySelectionSurface: some View {
        GeometryReader { proxy in
            CardSelectionButton(
                accessibilityIdentifier: bodyIdentifier,
                accessibilityLabel: "Select note: \(accessibilitySummary)",
                selected: selected,
                fixedPointerMode: nil,
                selection: selection,
                prepareContext: prepareContext,
                pressed: $bodyPressed
            )
            .frame(
                width: max(0, proxy.size.width - AppTheme.Spacing.card - AppTheme.Size.selectionCircle - AppTheme.Spacing.composerGap),
                height: proxy.size.height
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var expandedBodySelectionSurface: some View {
        GeometryReader { proxy in
            CardSelectionButton(
                accessibilityIdentifier: bodyIdentifier,
                accessibilityLabel: "Select note chrome: \(accessibilitySummary)",
                selected: selected,
                fixedPointerMode: nil,
                selection: selection,
                prepareContext: prepareContext,
                pressed: $bodyPressed
            )
            .frame(
                width: max(0, proxy.size.width - AppTheme.Spacing.card - AppTheme.Size.selectionCircle - AppTheme.Spacing.composerGap),
                height: proxy.size.height
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var cardSurface: Color {
        if bodyPressed || circlePressed { return Color.accentColor.opacity(0.08) }
        if selected { return AppTheme.selectedCardSurface }
        return AppTheme.cardSurface
    }

    private var accessibilitySummary: String { item.text.isEmpty ? item.attachments.map(\.filename).joined(separator: ", ") : ItemCardPresentation.accessibilitySummary(markdown: item.text) }
    private var bodyIdentifier: String { "item-card-body-\(item.id.uuidString)" }
    private var circleIdentifier: String { "item-card-circle-\(item.id.uuidString)" }
    private var contextIdentifier: String { "item-card-context-\(item.id.uuidString)" }

    @ViewBuilder private var menu: some View {
        Button("Copy") { prepareContext(); command(.copy) }.keyboardShortcut("c", modifiers: [.command])
        Button("Copy as List") { prepareContext(); command(.copyAsList) }.keyboardShortcut("c", modifiers: [.command, .shift])
        Divider()
        Button("Mark as Done") { prepareContext(); command(.markDone) }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(item.state != .active)
        Button(expanded ? "Collapse" : "Expand") { prepareContext(); command(.expand) }
            .disabled(selectionCountIsMany)
        Divider()
        Button("Edit") { prepareContext(); command(.edit) }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(selectionCountIsMany)
        Button("Edit in New Window") { prepareContext(); command(.editInNewWindow) }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(selectionCountIsMany)
        Button("Merge Notes") { prepareContext(); command(.mergeNotes) }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(!contextCanMerge)
        Menu("Move to") {
            ForEach(sections) { section in Button(section.name) { prepareContext(); move(section.id) } }
        }
        if item.state != .active {
            Divider()
            Button("Restore") { prepareContext(); command(.restore) }
                .disabled(selectionCountIsMany)
        }
    }

    private var selectionCountIsMany: Bool { (selected ? selectionCount : 1) != 1 }
    private var contextCanMerge: Bool { selected && canMerge }
}
