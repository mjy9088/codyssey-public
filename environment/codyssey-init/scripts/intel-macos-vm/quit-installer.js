// Ask Launch Services to quit only the selected InstallAssistant bundle.
ObjC.import("AppKit");
ObjC.import("Foundation");

function run(argv) {
    const path = $(argv[0]).stringByResolvingSymlinksInPath;
    const app = $.NSBundle.bundleWithPath(path);
    const identifier = ObjC.unwrap(app.bundleIdentifier);
    if (!identifier || !identifier.startsWith("com.apple.InstallAssistant.")) return;

    function matches() {
        const result = [];
        const instances = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(identifier);
        for (let i = 0; i < instances.count; i++) {
            const instance = instances.objectAtIndex(i);
            const runningPath = ObjC.unwrap(instance.bundleURL.path.stringByResolvingSymlinksInPath);
            if (runningPath === ObjC.unwrap(path) && !instance.isTerminated) result.push(instance);
        }
        return result;
    }

    const selected = matches();
    if (!selected.length) return;
    for (const instance of selected) {
        if (!instance.terminate) throw new Error("InstallAssistant refused to quit");
    }
    const deadline = Date.now() + 10000;
    while (matches().length && Date.now() < deadline) {
        $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.2));
    }
    if (matches().length) throw new Error("InstallAssistant remained open");
    console.log("Closed the host macOS installer.");
}
