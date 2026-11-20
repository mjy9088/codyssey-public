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

    func matches(_ identifier: String, _ expectedModifiers: UInt32) -> Bool {
        let id = Int32(identifier)!
        var character: UInt16 = 0, key: UInt16 = 0
        var modifiers: UInt32 = 0
        return get(id, &character, &key, &modifiers) == 0 &&
            key == 49 && modifiers == expectedModifiers && enabled(id)
    }

    if !verifyOnly {
        let domain = "com.apple.symbolichotkeys" as CFString
        var keys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any] ?? [:]
        for (identifier, modifiers) in bindings {
            keys[identifier] = ["enabled": true, "value": ["type": "standard", "parameters": [65535, 49, modifiers]]]
        }
        CFPreferencesSetAppValue("AppleSymbolicHotKeys" as CFString, keys as CFDictionary, domain)
        guard CFPreferencesAppSynchronize(domain) else { fail("could not save symbolic hotkeys.") }
        CFPreferencesSetAppValue("TISRomanSwitchState" as CFString, 0 as CFNumber, kCFPreferencesAnyApplication)
        guard CFPreferencesAppSynchronize(kCFPreferencesAnyApplication) else { fail("could not disable Caps Lock switching.") }
        // Register live values directly; activateSettings can restore stale
        // bindings while preferences are being synchronized.
        typealias SetHotKey = @convention(c) (Int32, UInt16, UInt16, UInt32) -> Int32
        typealias SetEnabled = @convention(c) (Int32, Bool) -> Int32
        guard let setAddress = dlsym(library, "CGSSetSymbolicHotKeyValue"),
              let enableAddress = dlsym(library, "CGSSetSymbolicHotKeyEnabled") else {
            fail("live shortcut registration is unavailable on this macOS version.")
        }
        let set = unsafeBitCast(setAddress, to: SetHotKey.self)
        let setEnabled = unsafeBitCast(enableAddress, to: SetEnabled.self)
        // The input-source approval flow can refresh live shortcuts while
        // WindowServer is applying registrations. Retry only mismatched bindings.
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        repeat {
            for (identifier, modifiers) in bindings where !matches(identifier, modifiers) {
                let id = Int32(identifier)!
                guard set(id, 65535, 49, modifiers) == 0 else {
                    fail("could not register shortcut \(identifier).")
                }
                guard setEnabled(id, true) == 0 else { fail("could not enable shortcut \(identifier).") }
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
            if bindings.allSatisfy({ matches($0.0, $0.1) }) { break }
        } while ProcessInfo.processInfo.systemUptime < deadline
    }

    for (identifier, expectedModifiers) in bindings {
        let id = Int32(identifier)!
        var character: UInt16 = 0, key: UInt16 = 0
        var modifiers: UInt32 = 0
        guard get(id, &character, &key, &modifiers) == 0,
              key == 49, modifiers == expectedModifiers, enabled(id) else {
            fail("binding \(identifier) was not applied in the active session (key \(key), modifiers \(modifiers), enabled \(enabled(id))).")
        }
    }
    if verifyOnly {
        print("Live shortcuts verified: Control-Space input switching; Command-Space Spotlight.")
    }
}

func source(_ identifier: String, includeDisabled: Bool = true) -> TISInputSource? {
    let filter = [kTISPropertyInputSourceID as String: identifier] as CFDictionary
    let sources = TISCreateInputSourceList(filter, includeDisabled).takeRetainedValue() as NSArray
    return sources.firstObject.map { $0 as! TISInputSource }
}

func enabled(_ source: TISInputSource) -> Bool {
    guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else {
        return false
    }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
}

// A parent activation request can return before the approval dialog closes.
// The usable Hangul mode and the current source determine completion.
// Carbon can return paramErr for an enabled, selectable mode while Allow is
// pending or after it was accepted. Keep retrying at a slower cadence and let
// desktop selection complete the same flow. Prompt once and treat only the
// current source as confirmation, including after a successful selection call.
func waitForHangul(
    requestMode: () -> Bool,
    currentIsHangul: () -> Bool,
    selectMode: () -> OSStatus?,
    selectionRejected: () -> Void,
    waitForNextAttempt: (_ selectionRejected: Bool) -> Bool
) -> Bool {
    var requested = false
    var reportedRejection = false
    var rejected = false
    repeat {
        if currentIsHangul() { return true }
        if !requested { requested = requestMode() }
        rejected = selectMode() == OSStatus(paramErr)
        if currentIsHangul() { return true }
        if rejected && !reportedRejection {
            selectionRejected()
            reportedRejection = true
        }
    } while waitForNextAttempt(rejected)
    return false
}

func flag(_ input: TISInputSource, _ property: CFString) -> Bool {
    guard let value = TISGetInputSourceProperty(input, property) else { return false }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
}

func currentSourceID() -> String {
    guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
          let value = TISGetInputSourceProperty(current, kTISPropertyInputSourceID) else { return "" }
    return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
}

#if !CODYSSEY_INPUT_TEST
if CommandLine.arguments.count == 2 && ["--shortcuts", "--verify-shortcuts"].contains(CommandLine.arguments[1]) {
    configureShortcuts(verifyOnly: CommandLine.arguments[1] == "--verify-shortcuts")
    exit(0)
}

if CommandLine.arguments.count == 2 && CommandLine.arguments[1] == "--current-source" {
    let identifier = currentSourceID()
    guard !identifier.isEmpty else { fail("Current keyboard input source is unavailable.") }
    print(identifier)
    exit(0)
}

if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--wait-for-source" {
    let relation = CommandLine.arguments[2]
    let expected = CommandLine.arguments[3]
    guard relation == "is" || relation == "is-not" else { fail("Expected is or is-not.") }
    let deadline = ProcessInfo.processInfo.systemUptime + 30
    repeat {
        let current = currentSourceID()
        if !current.isEmpty && ((current == expected) == (relation == "is")) { exit(0) }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    } while ProcessInfo.processInfo.systemUptime < deadline
    fail("The active input source did not change as expected (current: \(currentSourceID())).")
}

guard CommandLine.arguments.count == 2 else {
    fail("Usage: swift enable-korean.swift PATH_TO_GUREUM_APP | --shortcuts | --verify-shortcuts | --current-source | --wait-for-source {is|is-not} ID")
}
let parent = "org.youknowone.inputmethod.Korean"
let identifier = "org.youknowone.inputmethod.Gureum.han2"
var parentStatus: OSStatus?
if currentSourceID() != identifier {
    let app = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
    let registrationStatus = TISRegisterInputSource(app)
    guard registrationStatus == noErr else {
        fail("Could not register the installed Gureum input method (status \(registrationStatus)).")
    }
    if let input = source(parent), !enabled(input) {
        parentStatus = TISEnableInputSource(input)
    }
    fputs("If macOS shows an input-source activation dialog, choose Allow. Waiting for Gureum Hangul to become selectable…\n", stderr)
}

let deadline = ProcessInfo.processInfo.systemUptime + 120
var modeStatus: OSStatus?
var selectionStatus: OSStatus?
let selected = waitForHangul(
    requestMode: {
        guard let mode = source(identifier) else { return false }
        if enabled(mode) { return true }
        guard flag(mode, kTISPropertyInputSourceIsEnableCapable) else { return false }
        modeStatus = TISEnableInputSource(mode)
        return modeStatus == noErr
    },
    currentIsHangul: { currentSourceID() == identifier },
    selectMode: {
        guard let mode = source(identifier, includeDisabled: false),
              flag(mode, kTISPropertyInputSourceIsSelectCapable) else { return nil }
        selectionStatus = TISSelectInputSource(mode)
        return selectionStatus
    },
    selectionRejected: {
        fputs("macOS rejected automatic Gureum selection. Choose Allow if the approval dialog is still open. If Gureum does not switch automatically, select Gureum Hangul 2-set from the desktop Input menu. Add it in System Settings > Keyboard > Text Input > Edit if needed.\n", stderr)
    },
    waitForNextAttempt: { rejected in
        RunLoop.current.run(until: Date(timeIntervalSinceNow: rejected ? 3 : 0.5))
        return ProcessInfo.processInfo.systemUptime < deadline
    }
)
guard selected else {
    func state(_ id: String) -> String {
        guard let input = source(id) else { return "missing" }
        return "enabled=\(enabled(input)), enable-capable=\(flag(input, kTISPropertyInputSourceIsEnableCapable)), select-capable=\(flag(input, kTISPropertyInputSourceIsSelectCapable))"
    }
    func status(_ result: OSStatus?) -> String { result.map { String($0) } ?? "not requested" }
    fail("Gureum Hangul selection was not confirmed within 120 seconds. Parent: \(state(parent)) (request \(status(parentStatus))). Hangul: \(state(identifier)) (request \(status(modeStatus)), selection \(status(selectionStatus))). Select Gureum in the desktop Input menu, then retry with bash macos-setup.sh --input-only.")
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
print("Gureum Hangul 2-set is selected.")
#endif
