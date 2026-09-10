import CoreServices
import Foundation

if let handler = LSCopyDefaultHandlerForURLScheme("obsidian" as CFString) {
    print(handler.takeRetainedValue() as String)
}
