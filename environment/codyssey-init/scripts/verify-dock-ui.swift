import AppKit
import ApplicationServices

// Read-only VM verification. Production setup never requires Accessibility.
guard AXIsProcessTrusted() else {
    fputs("Dock UI verification requires an already-authorized VM Guest Agent; no permission is requested.\n", stderr)
    exit(1)
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

let home = FileManager.default.homeDirectoryForCurrentUser
let chrome = FileManager.default.fileExists(atPath: "/Applications/Google Chrome.app")
    ? URL(fileURLWithPath: "/Applications/Google Chrome.app")
    : home.appendingPathComponent("Applications/Google Chrome.app")
let targets = [URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), chrome,
               home.appendingPathComponent("Library/Application Support/codyssey-init/Codyssey j.command")]
let expected = Set(targets.map { $0.standardizedFileURL.path })
let pinnedPrefix = ["/System/Library/CoreServices/Finder.app"] + targets.prefix(2).map { $0.standardizedFileURL.path }
let deadline = Date().addingTimeInterval(20)
var found = Set<String>()
var visible = [String]()
repeat {
    found.removeAll()
    visible.removeAll()
    for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == "com.apple.dock" {
        var queue = [AXUIElementCreateApplication(app.processIdentifier)]
        var visited = 0
        while !queue.isEmpty && visited < 500 {
            let element = queue.removeFirst()
            visited += 1
            if attribute(element, kAXRoleAttribute) as? String == "AXDockItem" {
                if let url = attribute(element, kAXURLAttribute) as? URL,
                   let title = attribute(element, kAXTitleAttribute) as? String,
                   !title.isEmpty && title != "?" {
                    found.insert(url.standardizedFileURL.path)
                    visible.append(url.standardizedFileURL.path)
                } else {
                    visible.append("<unresolved>")
                }
            }
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: children)
            }
        }
    }
    // Running apps must not mask broken pins with a second, valid Dock icon.
    if Array(visible.prefix(3)) == pinnedPrefix && expected.isSubset(of: found) {
        print("PASS: the live Dock resolves Terminal, Chrome and the j launcher to named UI items.")
        exit(0)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
} while Date() < deadline
fputs("Dock UI verification failed: pinned prefix \(Array(visible.prefix(3))); missing items \(expected.subtracting(found).sorted())\n", stderr)
exit(1)
