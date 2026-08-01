import AppKit
import EmbercueCore
import SwiftUI

@MainActor
public final class AppController: NSObject, NSApplicationDelegate {
    private var model: WorkbenchModel?
    private var panelController: PanelController?
    private var statusItemController: StatusItemController?
    private var hotKeyCoordinator: HotKeyAvailabilityCoordinator?
    private var editorController: ItemEditorController?
    private var selectedTextCaptureCoordinator: SelectedTextCaptureCoordinator?
    private var applicationActivationRelay: (any ApplicationActivationRelaying)?

    /// Isolated visual QA may force a native appearance.  A normal launch never
    /// reads this knob, so it cannot become a hidden user preference.
    public static func qaAppearance(environment: [String: String] = ProcessInfo.processInfo.environment) -> NSAppearance? {
        guard environment[JSONLibraryRepository.dataDirectoryEnvironmentVariable] != nil else { return nil }
        switch environment["EMBERCUE_QA_APPEARANCE"]?.lowercased() {
        case "light": return NSAppearance(named: .aqua)
        case "dark": return NSAppearance(named: .darkAqua)
        default: return nil
        }
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let repository = try JSONLibraryRepository()
            let engine = try LibraryEngine(repository: repository)
            let clipboard = NSPasteboardClipboard()
            let workbench = WorkbenchModel(engine: engine, clipboard: clipboard, attachmentStore: try AttachmentStore(rootURL: repository.rootURL))
            model = workbench
            let editor = ItemEditorController(model: workbench)
            editorController = editor
            workbench.onOpenEditor = { [weak editor] item in editor?.show(item) }
            let selectedTextCoordinator = SelectedTextCaptureCoordinator(
                reader: AccessibilitySelectedTextReader(),
                monitor: GlobalDoubleShiftMonitor(),
                preferences: UserDefaultsDoubleShiftCapturePreferences(),
                automaticSelectionCopier: FrontmostSelectionCopier(clipboard: clipboard),
                capture: { [weak workbench] text in workbench?.captureSelectedText(text) },
                reportError: { [weak workbench] error in workbench?.show(error: error) },
                statusChanged: { [weak workbench] status in workbench?.setSelectedTextCaptureStatus(status) },
                captureConfirmation: { DoubleShiftCaptureConsentAlert.requestEnable() }
            )
            selectedTextCaptureCoordinator = selectedTextCoordinator
            workbench.onSelectedTextCaptureAction = { [weak selectedTextCoordinator] in selectedTextCoordinator?.performMenuAction() }
            selectedTextCoordinator.restore()
            let activationRelay = ApplicationDidBecomeActiveRelay()
            activationRelay.start { [weak selectedTextCoordinator] in selectedTextCoordinator?.refreshAuthorization() }
            applicationActivationRelay = activationRelay
            workbench.onDocumentChange = { [weak self] in self?.updateQueueCount() }
            let tracker = ForegroundApplicationTracker()
            let panel = PanelController(rootView: WorkbenchView(model: workbench, onCopyAndReturn: { [weak self] in self?.panelController?.hideAndReturn() }, onExport: { [weak self] in self?.exportLibrary() }, onHide: { [weak self] in self?.panelController?.hide() }, onCheckForUpdates: { [weak self] in self?.checkForUpdates() }), tracker: tracker, appearance: Self.qaAppearance(), onShortcut: { workbench.handleShortcut($0) }, onShow: { workbench.requestComposerFocus() }, onHide: { workbench.clearCompletionEcho() })
            panelController = panel
            let coordinator = HotKeyAvailabilityCoordinator(hotKey: CarbonGlobalHotKey())
            coordinator.composeMenuFallback { [weak self] in
                self?.statusItemController = StatusItemController(onShow: { [weak self] in self?.showWorkbench() }, onExport: { [weak self] in self?.exportLibrary() })
            }
            hotKeyCoordinator = coordinator
            updateQueueCount()
            if let error = coordinator.start(action: { [weak self] in
                DispatchQueue.main.async { self?.showWorkbench() }
            }) {
                workbench.show(error: error)
            }
            DispatchQueue.main.async { [weak self] in self?.showWorkbench() }
        } catch {
            presentStartupError(error)
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        hotKeyCoordinator?.stop()
        selectedTextCaptureCoordinator?.stop()
        applicationActivationRelay?.stop()
        applicationActivationRelay = nil
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWorkbench()
        return true
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        BackgroundResidencyPolicy.shouldTerminateAfterLastWindowClosed
    }

    private func showWorkbench() {
        panelController?.show()
        updateQueueCount()
    }

    private func exportLibrary() {
        guard let model else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Embercue-library-export.json"
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in model.export(to: url) }
        }
    }

    private func updateQueueCount() {
        let count = model?.document.items(kind: .prompt, states: [.active]).count ?? 0
        statusItemController?.updateQueueCount(count)
    }

    private func checkForUpdates() {
        GitHubReleaseUpdateChecker().check { [weak self] result in
            let alert = NSAlert()
            switch result {
            case let .updateAvailable(version, releaseURL):
                alert.messageText = "Embercue \(version) is available"
                alert.informativeText = "Open the GitHub release page to download it."
                alert.addButton(withTitle: "Open Download")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(releaseURL) }
            case .upToDate:
                alert.messageText = "Embercue is up to date"
                alert.informativeText = "You already have the latest release."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            case .unavailable:
                alert.messageText = "Unable to check for updates"
                alert.informativeText = "GitHub Releases could not be reached. Try again later."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            _ = self
        }
    }

    private func presentStartupError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
        NSApp.terminate(nil)
    }
}
