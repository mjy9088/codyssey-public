import Carbon
import Foundation
import Darwin

func fail(_ message: String) -> Never {
    fputs("\(message)\n", stderr)
    exit(1)
}

func configureShortcuts(verifyOnly: Bool) {
    // Read the active WindowServer bindings, not just the saved preferences. These
    // private symbols are available on the reference macOS environment; fail clearly
    // if a future OS removes them. No event capture or accessibility access is used.
    typealias GetHotKey = @convention(c) (Int32, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt32>) -> Int32
    typealias IsEnabled = @convention(c) (Int32) -> Bool
    guard let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
          let getAddress = dlsym(library, "CGSGetSymbolicHotKeyValue"),
          let enabledAddress = dlsym(library, "CGSIsSymbolicHotKeyEnabled") else {
        fail("live verification is unavailable on this macOS version; no settings were changed.")
    }
    let get = unsafeBitCast(getAddress, to: GetHotKey.self)
    let enabled = unsafeBitCast(enabledAddress, to: IsEnabled.self)
    let bindings: [(String, UInt32)] = [("60", 262144), ("61", 393216), ("64", 1048576), ("65", 1572864)]

    if !verifyOnly {
        // Keyboard Settings can write its stale cached bindings back over ours.
        // Leave the user's application alone and require it to be closed first.
        let settings = Process()
        settings.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        settings.arguments = ["-x", "System Settings"]
        settings.standardOutput = FileHandle.nullDevice
        do { try settings.run() } catch { fail("could not check whether System Settings is open: \(error)") }
        settings.waitUntilExit()
        guard settings.terminationStatus == 1 else {
            fail("close System Settings and rerun setup so it cannot overwrite the shortcut bindings; no shortcuts were changed.")
        }
        let domain = "com.apple.symbolichotkeys" as CFString
        var keys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any] ?? [:]
        for (identifier, modifiers) in bindings {
            keys[identifier] = ["enabled": true, "value": ["type": "standard", "parameters": [65535, 49, modifiers]]]
        }
        CFPreferencesSetAppValue("AppleSymbolicHotKeys" as CFString, keys as CFDictionary, domain)
        guard CFPreferencesAppSynchronize(domain) else { fail("could not save symbolic hotkeys.") }
        CFPreferencesSetAppValue("TISRomanSwitchState" as CFString, 0 as CFNumber, kCFPreferencesAnyApplication)
        guard CFPreferencesAppSynchronize(kCFPreferencesAnyApplication) else { fail("could not disable Caps Lock switching.") }
        let reload = Process()
        reload.executableURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
        reload.arguments = ["-u"]
        do { try reload.run() } catch { fail("could not reload shortcuts: \(error)") }
        reload.waitUntilExit()
        guard reload.terminationStatus == 0 else { fail("live shortcut reload failed.") }
    }

    for (identifier, expectedModifiers) in bindings {
        let id = Int32(identifier)!
        var character: UInt16 = 0, key: UInt16 = 0
        var modifiers: UInt32 = 0
        guard get(id, &character, &key, &modifiers) == 0,
              key == 49, modifiers == expectedModifiers, enabled(id) else {
            fail("binding \(identifier) was not applied in the active session. Close Keyboard settings and rerun setup; no logout is needed.")
        }
    }
    print("Live shortcuts verified: Control-Space input switching; Command-Space Spotlight.")
}

if CommandLine.arguments.count == 2 && ["--shortcuts", "--verify-shortcuts"].contains(CommandLine.arguments[1]) {
    configureShortcuts(verifyOnly: CommandLine.arguments[1] == "--verify-shortcuts")
    exit(0)
}

func source(_ identifier: String) -> TISInputSource? {
    let filter = [kTISPropertyInputSourceID as String: identifier] as CFDictionary
    let sources = TISCreateInputSourceList(filter, true).takeRetainedValue() as NSArray
    return sources.firstObject.map { $0 as! TISInputSource }
}

func enabled(_ source: TISInputSource) -> Bool {
    guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else {
        return false
    }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
}

func enableAndWait(_ identifier: String) {
    guard let input = source(identifier) else {
        fail("Input source unavailable: \(identifier)")
    }
    if enabled(input) { return }
    fputs("Approve the macOS input-source activation dialog if shown. Waiting up to 120 seconds…\n", stderr)
    let status = TISEnableInputSource(input)
    guard status == noErr else {
        fail("Could not request activation of \(identifier): \(status)")
    }
    // noErr acknowledges the request, not the user's approval. Keep this process
    // alive and service its run loop until fresh TIS state confirms activation.
    let deadline = Date(timeIntervalSinceNow: 120)
    repeat {
        if let current = source(identifier), enabled(current) { return }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
    } while Date() < deadline
    fail("Input-source activation was not approved within 120 seconds (\(identifier)). Rerun setup and choose Allow; no logout is required.")
}

guard CommandLine.arguments.count == 2 else {
    fail("Usage: swift enable-korean.swift PATH_TO_GUREUM_APP | --shortcuts | --verify-shortcuts")
}
let app = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
guard TISRegisterInputSource(app) == noErr else {
    fail("Could not register the installed Gureum input method.")
}

// Approval of the parent must finish before requesting its Hangul mode.
let parent = "org.youknowone.inputmethod.Korean"
let identifier = "org.youknowone.inputmethod.Gureum.han2"
enableAndWait(parent)
enableAndWait(identifier)

let deadline = Date(timeIntervalSinceNow: 10)
var selectionStatus: OSStatus = -50
var selected = false
repeat {
    if let korean = source(identifier) {
        selectionStatus = TISSelectInputSource(korean)
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        if let value = TISGetInputSourceProperty(current, kTISPropertyInputSourceID) {
            let currentID = Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
            selected = selectionStatus == noErr && currentID == identifier
        }
        if selected { break }
    }
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
} while Date() < deadline
guard selected else {
    fail("Korean input was enabled but selection was not confirmed (status \(selectionStatus)). Rerun setup in the active desktop session.")
}

// Keep the existing Latin layout; remove the old Apple Korean sources only after
// the requested replacement has been confirmed as selected.
let previousSources = ["com.apple.inputmethod.Korean.2SetKorean", "com.apple.inputmethod.Korean"]
for identifier in previousSources {
    if let previous = source(identifier), enabled(previous) {
        let status = TISDisableInputSource(previous)
        guard status == noErr else {
            fail("Could not disable the previous input source \(identifier): \(status)")
        }
    }
}
print("Gureum 1.13.2 Hangul 2-set registered, enabled, and selected.")
