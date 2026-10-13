import Carbon
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift enable-korean.swift PATH_TO_GUREUM_APP\n", stderr)
    exit(1)
}
let app = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
guard TISRegisterInputSource(app) == noErr else {
    fputs("Could not register the installed Gureum input method.\n", stderr)
    exit(1)
}

// A mode can report enabled while its parent input method remains disabled.
// Enable the parent first so the mode appears in the live switching list.
for identifier in ["org.youknowone.inputmethod.Korean", "org.youknowone.inputmethod.Gureum.han2"] {
    let filter = [kTISPropertyInputSourceID as String: identifier] as CFDictionary
    let sources = TISCreateInputSourceList(filter, true).takeRetainedValue() as NSArray
    guard let source = sources.firstObject else {
        fputs("Input source unavailable: \(identifier)\n", stderr)
        exit(1)
    }
    let status = TISEnableInputSource((source as! TISInputSource))
    guard status == noErr else {
        fputs("Could not enable \(identifier): \(status)\n", stderr)
        exit(1)
    }
}

// Remove the Apple Korean sources added by the earlier bootstrap before selecting
// Gureum. In a fresh login session TISSelectInputSource can fail with exit(2),
// but cleanup must still run so Control-Space will not keep cycling Apple Korean.
for identifier in ["com.apple.inputmethod.Korean.2SetKorean", "com.apple.inputmethod.Korean"] {
    let filter = [kTISPropertyInputSourceID as String: identifier] as CFDictionary
    let sources = TISCreateInputSourceList(filter, true).takeRetainedValue() as NSArray
    if let source = sources.firstObject {
        let status = TISDisableInputSource((source as! TISInputSource))
        guard status == noErr else {
            fputs("Could not disable the previous Apple Korean source: \(status)\n", stderr)
            exit(1)
        }
    }
}

let koreanFilter = [kTISPropertyInputSourceID as String: "org.youknowone.inputmethod.Gureum.han2"] as CFDictionary
let korean = TISCreateInputSourceList(koreanFilter, false).takeRetainedValue() as NSArray
guard let selected = korean.firstObject, TISSelectInputSource((selected as! TISInputSource)) == noErr else {
    fputs("Gureum is registered and Apple Korean sources were removed, but macOS cannot select Gureum in this session. Log out and back in, then rerun bash macos-setup.sh --input-only.\n", stderr)
    exit(2)
}
print("Gureum 1.13.2 Hangul 2-set registered, enabled, and selected.")
