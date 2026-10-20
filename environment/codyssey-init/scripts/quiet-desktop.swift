import AppKit

// Hide only the GUI; leave OrbStack's engine and containers running.
for app in NSWorkspace.shared.runningApplications where ["dev.kdrag0n.MacVirt", "dev.kdrag0n.OrbStack"].contains(app.bundleIdentifier ?? "") {
    if !app.hide() { fputs("Could not hide the OrbStack window.\n", stderr) }
}
