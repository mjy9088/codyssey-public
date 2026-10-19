import AppKit
import ApplicationServices

// Hide only the GUI; leave OrbStack's engine and containers running.
for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == "dev.kdrag0n.OrbStack" {
    if !app.hide() { fputs("Could not hide the OrbStack window.\n", stderr) }
}

// Never request permissions or touch the notification database. Only operate on
// Notification Center's close controls when this terminal is already trusted.
guard AXIsProcessTrusted() else {
    print("For fewer banners, enable Do Not Disturb in Control Center. Closing existing banners automatically requires Accessibility access for this terminal.")
    exit(0)
}
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}
var closed = 0
for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == "com.apple.notificationcenterui" {
    var queue = [AXUIElementCreateApplication(app.processIdentifier)]
    var visited = 0
    while !queue.isEmpty && visited < 500 {
        let element = queue.removeFirst()
        visited += 1
        if attribute(element, kAXSubroleAttribute) as? String == kAXCloseButtonSubrole {
            if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success { closed += 1 }
        } else if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            queue.append(contentsOf: children)
        }
    }
}
if closed > 0 { print("Closed \(closed) notification controls.") }
