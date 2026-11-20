// Compiled with enable-korean.swift on macOS. No TIS preferences are changed.
func testDelayedHangulActivation() {
    // The parent approval was requested externally. Its enabled flag never
    // changes, but the Hangul mode becomes available and eventually selectable.
    var tick = 0
    var requests: [Int] = []
    var current = false
    var notices = 0
    var delayedAttempts: [Int] = []
    let selected = waitForHangul(
        requestMode: {
            requests.append(tick)
            return tick >= 2
        },
        currentIsHangul: { current },
        selectMode: {
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
    precondition(requests == [0, 1, 2])
    precondition(notices == 1 && delayedAttempts == [2, 3])
}

func testAcceptedRequestWithoutSelectionTimesOut() {
    var ticks = 0
    var requests = 0
    let selected = waitForHangul(
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

testDelayedHangulActivation()
testAcceptedRequestWithoutSelectionTimesOut()
testRejectedSelectionWaitsForDesktop()
print("PASS: Gureum Hangul activation, desktop fallback, and timeout with simulated input-source state.")
