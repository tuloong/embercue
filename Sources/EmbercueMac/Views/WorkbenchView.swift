import EmbercueCore
import SwiftUI

@_spi(Testing)
public enum WorkbenchLifecycleMenuTitles {
    public static let menuBarTitle = "Embercue"
    public static let hideToMenuBar = "Hide to Menu Bar"
    public static let quit = "Quit Embercue"
}

/// The rail deliberately stays free of product chrome.  It is a compact local
/// capture surface, not a second window manager or a lifecycle dashboard.
public struct WorkbenchView: View {
    @ObservedObject private var model: WorkbenchModel
    private let onCopyAndReturn: () -> Void
    private let onExport: () -> Void
    private let onHide: () -> Void

    public init(model: WorkbenchModel, onCopyAndReturn: @escaping () -> Void, onExport: @escaping () -> Void, onHide: @escaping () -> Void) {
        self.model = model
        self.onCopyAndReturn = onCopyAndReturn
        self.onExport = onExport
        self.onHide = onHide
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            if let notice = model.inlineNotice {
                InlineNotice(message: notice, isSuccess: model.inlineNoticeIsSuccess, dismiss: model.dismissNotice)
                    .padding(.horizontal, AppTheme.Spacing.rail)
                    .padding(.bottom, 6)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                    if model.page == .rail { railContents } else { historyContents }
                }
                .padding(.horizontal, AppTheme.Spacing.rail)
                .padding(.top, AppTheme.Spacing.scrollTop)
                .padding(.bottom, AppTheme.Spacing.card)
            }
            ComposerView(model: model)
                .padding(AppTheme.Spacing.rail)
        }
        .background(AppTheme.railMaterial)
        .background(AppTheme.railSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.rail, style: .continuous))
        .onExitCommand(perform: onHide)
        .alert("New Section", isPresented: $model.isCreatingSection) {
            TextField("Section name", text: $model.newSectionName)
            Button("Create") { model.createRequestedSection() }
            Button("Cancel", role: .cancel) { model.newSectionName = "" }
        } message: {
            Text("Use a short name to group related prompts and notes.")
        }
    }

    private var topBar: some View {
        HStack(spacing: AppTheme.Spacing.topGap) {
            HStack(spacing: AppTheme.Spacing.searchContentGap) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search", text: $model.search)
                    .textFieldStyle(.plain)
                    .font(AppTheme.Typography.search)
                    .accessibilityLabel("Search library")
            }
            .padding(.horizontal, AppTheme.Spacing.searchHorizontalInset)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.Size.topControlHeight)
            .background(AppTheme.searchSurface, in: Capsule())

            MoreMenuAnchor(
                page: model.page,
                togglePage: { model.page = model.page == .rail ? .history : .rail },
                newSection: model.requestNewSection,
                keepClipboard: model.keepClipboard,
                selectedTextCaptureStatus: model.selectedTextCaptureStatus,
                selectedTextCaptureAction: { model.onSelectedTextCaptureAction?() },
                canCopyAndReturn: !model.selectedDisplayItems().isEmpty,
                copyAndReturn: {
                    if model.copySelected() { onCopyAndReturn() }
                },
                export: onExport,
                hide: onHide
            )
            .frame(width: AppTheme.Size.topControlHeight, height: AppTheme.Size.topControlHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.Spacing.rail)
        .padding(.vertical, AppTheme.Spacing.topVertical)
    }

    @ViewBuilder private var railContents: some View {
        if model.sections.isEmpty {
            EmptyStateView(title: model.isSearching ? "No matching notes" : "A clear place to keep the next thing", description: model.isSearching ? "Try a different search." : "Add a note or prompt below.")
        } else {
            ForEach(model.sections) { snapshot in
                RailSection(title: snapshot.section.name) {
                    ForEach(snapshot.items) { item in editableCard(item) }
                }
            }
        }
    }

    @ViewBuilder private var historyContents: some View {
        RailSection(title: "HISTORY") {
            if model.historyItems.isEmpty {
                EmptyStateView(title: "Nothing in history", description: "Completed and archived notes remain here.")
            } else {
                ForEach(model.historyItems) { item in editableCard(item) }
            }
        }
    }

    private func card(_ item: EmbercueCore.LibraryItem) -> some View {
        ItemCard(
            item: item,
            selected: model.isSelected(item),
            selectionCount: model.selectedDisplayItems().count,
            canMerge: model.canMergeSelection,
            expanded: model.isExpanded(item),
            completedEcho: model.isCompletionEcho(item),
            selection: { mode in model.select(item, mode: mode) },
            toggleCircle: { model.toggleCircle(item) },
            prepareContext: { model.prepareContext(for: item) },
            command: { command in
                if !model.isSelected(item) { model.select(item) }
                model.execute(command)
            },
            move: { model.moveSelected(to: $0) },
            sections: model.document.sections.sorted { $0.sortOrder < $1.sortOrder },
            attachmentURL: model.attachmentURL(for:)
        )
    }

    @ViewBuilder private func editableCard(_ item: EmbercueCore.LibraryItem) -> some View {
        if model.isInlineEditing(item) {
            InlineItemEditor(draft: $model.inlineEditDraft, save: { _ = model.saveInlineEdit() }, cancel: model.cancelInlineEdit)
        } else {
            card(item)
        }
    }

}

private struct InlineItemEditor: View {
    @Binding var draft: String
    let save: () -> Void
    let cancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.control) {
            TextEditor(text: $draft)
                .font(AppTheme.Typography.body)
                .frame(minHeight: 88, maxHeight: 180)
                .scrollContentBackground(.hidden)
                .padding(AppTheme.Spacing.compact)
                .background(AppTheme.searchSurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                .focused($focused)
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                Button("Save", action: save).keyboardShortcut("s", modifiers: [.command])
            }
            .controlSize(.small)
        }
        .padding(AppTheme.Spacing.card)
        .background(AppTheme.cardSurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .onAppear { focused = true }
    }
}

private struct MoreMenuAnchor: NSViewRepresentable {
    let page: WorkbenchPage
    let togglePage: () -> Void
    let newSection: () -> Void
    let keepClipboard: () -> Void
    let selectedTextCaptureStatus: SelectedTextCaptureStatus
    let selectedTextCaptureAction: () -> Void
    let canCopyAndReturn: Bool
    let copyAndReturn: () -> Void
    let export: () -> Void
    let hide: () -> Void

    func makeNSView(context: Context) -> MoreMenuButton {
        let button = MoreMenuButton(frame: NSRect(x: 0, y: 0, width: AppTheme.Size.topControlHeight, height: AppTheme.Size.topControlHeight))
        button.configure(page: page, togglePage: togglePage, newSection: newSection, keepClipboard: keepClipboard, selectedTextCaptureStatus: selectedTextCaptureStatus, selectedTextCaptureAction: selectedTextCaptureAction, canCopyAndReturn: canCopyAndReturn, copyAndReturn: copyAndReturn, export: export, hide: hide)
        return button
    }

    func updateNSView(_ button: MoreMenuButton, context: Context) {
        button.configure(page: page, togglePage: togglePage, newSection: newSection, keepClipboard: keepClipboard, selectedTextCaptureStatus: selectedTextCaptureStatus, selectedTextCaptureAction: selectedTextCaptureAction, canCopyAndReturn: canCopyAndReturn, copyAndReturn: copyAndReturn, export: export, hide: hide)
    }
}

private final class MoreMenuButton: NSButton {
    private var page: WorkbenchPage = .rail
    private var togglePage: (() -> Void)?
    private var newSection: (() -> Void)?
    private var keepClipboard: (() -> Void)?
    private var selectedTextCaptureStatus: SelectedTextCaptureStatus = .disabled
    private var selectedTextCaptureAction: (() -> Void)?
    private var canCopyAndReturn = false
    private var copyAndReturn: (() -> Void)?
    private var exportLibrary: (() -> Void)?
    private var hide: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        target = self
        action = #selector(showMoreMenu)
        setAccessibilityLabel("More options")
        toolTip = "More options"
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: AppTheme.Size.topControlHeight, height: AppTheme.Size.topControlHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.withAlphaComponent(0.96).setFill()
        NSBezierPath(ovalIn: bounds).fill()
        NSColor.secondaryLabelColor.setFill()
        let diameter: CGFloat = 3
        let spacing: CGFloat = 4
        let total = diameter * 3 + spacing * 2
        let start = bounds.midX - total / 2
        for offset in 0..<3 {
            NSBezierPath(ovalIn: NSRect(x: start + CGFloat(offset) * (diameter + spacing), y: bounds.midY - diameter / 2, width: diameter, height: diameter)).fill()
        }
    }

    func configure(page: WorkbenchPage, togglePage: @escaping () -> Void, newSection: @escaping () -> Void, keepClipboard: @escaping () -> Void, selectedTextCaptureStatus: SelectedTextCaptureStatus, selectedTextCaptureAction: @escaping () -> Void, canCopyAndReturn: Bool, copyAndReturn: @escaping () -> Void, export: @escaping () -> Void, hide: @escaping () -> Void) {
        self.page = page
        self.togglePage = togglePage
        self.newSection = newSection
        self.keepClipboard = keepClipboard
        self.selectedTextCaptureStatus = selectedTextCaptureStatus
        self.selectedTextCaptureAction = selectedTextCaptureAction
        self.canCopyAndReturn = canCopyAndReturn
        self.copyAndReturn = copyAndReturn
        exportLibrary = export
        self.hide = hide
        needsDisplay = true
    }

    @objc private func showMoreMenu() {
        let menu = NSMenu()
        menu.addItem(item(page == .rail ? "History" : "Show active notes", action: #selector(togglePageAction)))
        menu.addItem(.separator())
        menu.addItem(item("New Section…", action: #selector(newSectionAction)))
        menu.addItem(item("Keep Clipboard", action: #selector(keepClipboardAction)))
        menu.addItem(item(selectedTextCaptureStatus.menuTitle, action: #selector(selectedTextCaptureActionTriggered)))
        menu.addItem(.separator())
        let copyAndReturnItem = item("Copy & Return", action: #selector(copyAndReturnAction))
        copyAndReturnItem.isEnabled = canCopyAndReturn
        menu.addItem(copyAndReturnItem)
        menu.addItem(item("Export Library Metadata…", action: #selector(exportAction)))
        let hideItem = item(WorkbenchLifecycleMenuTitles.hideToMenuBar, action: #selector(hideAction)); hideItem.keyEquivalent = "\u{1b}"; menu.addItem(hideItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: WorkbenchLifecycleMenuTitles.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = NSApp
        menu.addItem(quitItem)
        menu.addItem(.separator())
        let privacy = NSMenuItem(title: "Local only. Embercue does not sync or track your notes.", action: nil, keyEquivalent: "")
        privacy.isEnabled = false
        menu.addItem(privacy)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height), in: self)
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func togglePageAction() { togglePage?() }
    @objc private func newSectionAction() { newSection?() }
    @objc private func keepClipboardAction() { keepClipboard?() }
    @objc private func selectedTextCaptureActionTriggered() { selectedTextCaptureAction?() }
    @objc private func copyAndReturnAction() { copyAndReturn?() }
    @objc private func exportAction() { exportLibrary?() }
    @objc private func hideAction() { hide?() }
}

private struct RailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sectionContentGap) {
            HStack(spacing: AppTheme.Spacing.sectionHeaderGap) {
                Text(title.uppercased())
                    .font(AppTheme.Typography.section)
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                    .lineLimit(1)
                Rectangle().fill(.quaternary).frame(height: AppTheme.Size.sectionRuleHeight)
            }
            content()
        }
    }
}

private struct InlineNotice: View {
    let message: String
    let isSuccess: Bool
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isSuccess ? .green : .orange)
            Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
