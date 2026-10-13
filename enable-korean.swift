import Carbon
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift enable-korean.swift PATH_TO_GUREUM_APP\n", stderr)
    exit(1)
}

func inputSource(identifier: String, includeAllInstalled: Bool) -> TISInputSource? {
    let filter = [kTISPropertyInputSourceID as String: identifier] as CFDictionary
    let sources = TISCreateInputSourceList(filter, includeAllInstalled).takeRetainedValue() as NSArray
    return sources.firstObject as! TISInputSource?
}

func waitForInputSource(identifier: String, includeAllInstalled: Bool, timeout: TimeInterval = 8.0) -> TISInputSource? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let source = inputSource(identifier: identifier, includeAllInstalled: includeAllInstalled) {
            return source
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
    } while Date() < deadline
    return nil
}

@discardableResult
func enable(identifier: String) -> TISInputSource {
    guard let source = waitForInputSource(identifier: identifier, includeAllInstalled: true) else {
        fputs("Input source unavailable after registration wait: \(identifier)\n", stderr)
        exit(1)
    }
    let status = TISEnableInputSource(source)
    guard status == noErr else {
        fputs("Could not enable \(identifier): \(status)\n", stderr)
        exit(1)
    }
    return source
}

let app = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
guard TISRegisterInputSource(app) == noErr else {
    fputs("Could not register the installed Gureum input method.\n", stderr)
    exit(1)
}

// TISRegisterInputSource returns before the Input Sources server/UI has fully
// refreshed.  Polling avoids the race where Gureum exists on disk but the mode
// is not yet visible in the live keyboard switcher popup.
_ = enable(identifier: "org.youknowone.inputmethod.Korean")
_ = enable(identifier: "org.youknowone.inputmethod.Gureum.han2")

// Remove the Apple Korean sources added by the earlier bootstrap before selecting
// Gureum. In a fresh login session TISSelectInputSource can fail with exit(2),
// but cleanup must still run so Control-Space will not keep cycling Apple Korean.
for identifier in ["com.apple.inputmethod.Korean.2SetKorean", "com.apple.inputmethod.Korean"] {
    if let source = inputSource(identifier: identifier, includeAllInstalled: true) {
        let status = TISDisableInputSource(source)
        guard status == noErr else {
            fputs("Could not disable the previous Apple Korean source: \(status)\n", stderr)
            exit(1)
        }
    }
}

// Wait for the enabled mode to appear in the currently selectable source list.
guard let selected = waitForInputSource(identifier: "org.youknowone.inputmethod.Gureum.han2", includeAllInstalled: false),
      TISSelectInputSource(selected) == noErr else {
    fputs("Gureum is registered and Apple Korean sources were removed, but macOS cannot select Gureum in this session. Log out and back in, then rerun bash macos-setup.sh --input-only.\n", stderr)
    exit(2)
}

// Give the live input-source popup/switcher one more turn to observe the final
// selection before the parent shell reloads hotkeys.
RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.5))
print("Gureum 1.13.2 Hangul 2-set registered, enabled, and selected.")
