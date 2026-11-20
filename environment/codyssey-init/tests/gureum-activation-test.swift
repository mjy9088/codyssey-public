// Compiled with enable-korean.swift on macOS. No TIS preferences are changed.
func testDelayedHangulActivation() {
    // The child can already look ready while the parent is missing or disabled.
    var tick = 0
    var requests: [Int] = []
    var current = false
    var notices = 0
    var delayedAttempts: [Int] = []
    let selected = waitForHangul(
        parentIsEnabled: { tick >= 2 },
        requestMode: {
            requests.append(tick)
            return tick >= 2
        },
        currentIsHangul: { current },
        selectMode: {
            precondition(tick >= 2)
            if tick == 2 || tick == 3 { return OSStatus(paramErr) }
            if tick == 4 { current = true; return noErr }
            return nil
        },
        selectionRejected: { notices += 1 },
        waitForNextAttempt: { rejected in
            if rejected { delayedAttempts.append(tick) }
            tick += 1
            return tick < 8
        }
    )
    precondition(selected)
    precondition(requests == [2])
    precondition(notices == 1 && delayedAttempts == [2, 3])
}

func testAcceptedRequestWithoutSelectionTimesOut() {
    var ticks = 0
    var requests = 0
    let selected = waitForHangul(
        parentIsEnabled: { true },
        requestMode: { requests += 1; return true },
        currentIsHangul: { false },
        selectMode: { noErr },
        selectionRejected: { preconditionFailure("unexpected rejection") },
        waitForNextAttempt: { _ in ticks += 1; return ticks < 3 }
    )
    precondition(!selected && requests == 1 && ticks == 3)
}

func testRejectedSelectionWaitsForDesktop() {
    for desktopSwitch in [true, false] {
        var tick = 0
        var selectionAttempts = 0
        var notices = 0
        let selected = waitForHangul(
            parentIsEnabled: { true },
            requestMode: { true },
            currentIsHangul: { desktopSwitch && tick == 2 },
            selectMode: { selectionAttempts += 1; return OSStatus(paramErr) },
            selectionRejected: { notices += 1 },
            waitForNextAttempt: { rejected in
                precondition(rejected)
                tick += 1
                return tick < 4
            }
        )
        precondition(selectionAttempts == (desktopSwitch ? 2 : 4) && notices == 1)
        precondition(selected == desktopSwitch)
    }
}

func testMissingOrUnapprovedParentTimesOut() {
    var checks = 0
    let selected = waitForHangul(
        parentIsEnabled: { checks += 1; return false },
        requestMode: { preconditionFailure("parent is unavailable") },
        currentIsHangul: { false },
        selectMode: { preconditionFailure("parent is unavailable") },
        selectionRejected: { preconditionFailure("selection was not attempted") },
        waitForNextAttempt: { rejected in
            precondition(!rejected)
            return checks < 3
        }
    )
    precondition(!selected && checks == 3)
}

precondition(source("org.example.codyssey.missing-input-source", includeDisabled: false) == nil)
testDelayedHangulActivation()
testMissingOrUnapprovedParentTimesOut()
testAcceptedRequestWithoutSelectionTimesOut()
testRejectedSelectionWaitsForDesktop()
print("PASS: Gureum Hangul activation, desktop fallback, and timeout with simulated input-source state.")
