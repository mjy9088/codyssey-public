import Foundation
import Vision

do {
    let guestUser = CommandLine.arguments[2]
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.customWords = ["Codyssey", "Start Setup.command", "VMware Tools.pkg", guestUser]
    try VNImageRequestHandler(url: URL(fileURLWithPath: CommandLine.arguments[1])).perform([request])
    for observation in request.results ?? [] {
        guard let text = observation.topCandidates(1).first else { continue }
        let setupLabel = text.string.hasPrefix("Codyssey") || text.string.hasPrefix("Start Setup")
            || text.string.hasPrefix("VMware Tools") || text.string == guestUser
            || text.string.contains("VMware, Inc.")
        guard text.confidence >= (setupLabel ? 0.5 : 0.8) else { continue }
        let bounds = observation.boundingBox
        print("\(bounds.midX)\t\(1 - bounds.midY)\t\(text.string)")
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
