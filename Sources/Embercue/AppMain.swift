import AppKit
import EmbercueMac

@main @MainActor
struct EmbercueMain {
    private static let controller = AppController()

    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        EmbercueApplicationMenu.install(on: application)
        application.delegate = controller
        application.run()
    }
}
