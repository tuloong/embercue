import AppKit
import EmbercueCore
import SwiftUI
import UniformTypeIdentifiers

public struct ComposerView: View {
    @ObservedObject var model: WorkbenchModel
    @FocusState private var focused: Bool

    public init(model: WorkbenchModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            if !model.pendingAttachments.isEmpty {
                HStack(spacing: AppTheme.Spacing.compact) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.compact) {
                            ForEach(model.pendingAttachments) { attachment in
                                HStack(spacing: 4) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: attachment.sourceURL.path))
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                    Text(attachment.filename).lineLimit(1).font(.caption)
                                    Button { model.removePendingAttachment(attachment) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Text("Attached \(model.pendingAttachments.count) \(model.pendingAttachments.count == 1 ? "file" : "files")").font(.caption).foregroundStyle(.secondary)
                }
                .frame(height: 22)
            }
            HStack(spacing: AppTheme.Spacing.composerGap) {
                SectionMenuAnchor(
                    sections: model.document.sections.sorted { $0.sortOrder < $1.sortOrder },
                    selectedID: model.captureSectionID,
                    select: { model.captureSectionID = $0 }
                )
                .frame(width: AppTheme.Size.composerCircle, height: AppTheme.Size.composerCircle)

                TextField("Add a note or a prompt (\(model.captureSection?.name.lowercased() ?? "inbox"))", text: $model.draft)
                    .textFieldStyle(.plain)
                    .font(AppTheme.Typography.composer)
                    .focused($focused)
                    .onSubmit {
                        model.submitDraft()
                        focused = false
                        Task { @MainActor in focused = true }
                    }
                    .accessibilityLabel("Add a note or prompt")
                    .frame(maxWidth: .infinity)
                Button { chooseFiles() } label: { Image(systemName: "paperclip") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Attach files")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.Spacing.composerHorizontalInset)
        .frame(height: AppTheme.Size.composerHeight)
        .background(AppTheme.cardSurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            providers.forEach { provider in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in model.addPendingAttachments(urls: [url]) }
                }
            }
            return !providers.isEmpty
        }
        .onAppear { focused = true }
        .onChange(of: model.focusRequest) { _, _ in focused = true }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK else { return }
            model.addPendingAttachments(urls: panel.urls)
        }
    }
}

/// SwiftUI's `Menu` can negotiate a large intrinsic width when its label is
/// transparent. This native anchor owns exactly the visible 18pt circle and
/// opens a standard AppKit menu without consuming the composer's text width.
private struct SectionMenuAnchor: NSViewRepresentable {
    let sections: [LibrarySection]
    let selectedID: UUID
    let select: (UUID) -> Void

    func makeNSView(context: Context) -> SectionMenuButton {
        let button = SectionMenuButton(frame: NSRect(x: 0, y: 0, width: AppTheme.Size.composerCircle, height: AppTheme.Size.composerCircle))
        button.configure(sections: sections, selectedID: selectedID, select: select)
        return button
    }

    func updateNSView(_ button: SectionMenuButton, context: Context) {
        button.configure(sections: sections, selectedID: selectedID, select: select)
    }
}

private final class SectionMenuButton: NSButton {
    private var sections: [LibrarySection] = []
    private var onSelect: ((UUID) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        target = self
        action = #selector(showSectionMenu)
        setAccessibilityLabel("Choose capture section")
        toolTip = "Choose capture section"
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: AppTheme.Size.composerCircle, height: AppTheme.Size.composerCircle)
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset = AppTheme.Stroke.circle / 2
        NSColor.secondaryLabelColor.withAlphaComponent(0.55).setStroke()
        let path = NSBezierPath(ovalIn: bounds.insetBy(dx: inset, dy: inset))
        path.lineWidth = AppTheme.Stroke.circle
        path.stroke()
    }

    func configure(sections: [LibrarySection], selectedID: UUID, select: @escaping (UUID) -> Void) {
        self.sections = sections
        onSelect = select
        setAccessibilityValue(sections.first(where: { $0.id == selectedID })?.name)
        needsDisplay = true
    }

    @objc private func showSectionMenu() {
        let menu = NSMenu()
        for (index, section) in sections.enumerated() {
            let item = NSMenuItem(title: section.name, action: #selector(selectSection(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height), in: self)
    }

    @objc private func selectSection(_ sender: NSMenuItem) {
        guard sections.indices.contains(sender.tag) else { return }
        onSelect?(sections[sender.tag].id)
    }
}
