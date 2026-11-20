// Compiled with enable-korean.swift on macOS. No TIS preferences are changed.
func testDelayedHangulActivation() {
    // The parent approval was requested externally. Its enabled flag never
    // changes, but the Hangul mode becomes available and eventually selectable.
    var tick = 0
    var requests: [Int] = []
    let selected = waitForHangul(
        requestMode: {
            requests.append(tick)
            return tick >= 2
        },
        selectMode: { tick == 4 },
        waitForNextAttempt: {
            tick += 1
            return tick < 8
        }
    )
    precondition(selected)
    precondition(requests == [0, 1, 2])
}

func testAcceptedRequestWithoutSelectionTimesOut() {
    var ticks = 0
    var requests = 0
    let selected = waitForHangul(
        requestMode: { requests += 1; return true },
        selectMode: { false },
        waitForNextAttempt: { ticks += 1; return ticks < 3 }
    )
    precondition(!selected && requests == 1 && ticks == 3)
}

testDelayedHangulActivation()
testAcceptedRequestWithoutSelectionTimesOut()
print("PASS: Gureum Hangul activation retry and timeout with simulated input-source state.")
