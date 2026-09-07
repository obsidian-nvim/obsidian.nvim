import Cocoa
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard
            let value = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            value.lowercased().hasPrefix("obsidian://"),
            let launcher = Bundle.main.url(forResource: "obsidian-nvim-uri", withExtension: nil)
        else {
            NSApp.terminate(nil)
            return
        }

        let process = Process()
        process.executableURL = launcher
        process.arguments = [value]
        do {
            try process.run()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Unable to launch obsidian.nvim"
            alert.runModal()
        }
        NSApp.terminate(nil)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
