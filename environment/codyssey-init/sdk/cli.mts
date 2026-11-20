import {
  configureIterm2, configureMacOSFromTerminal, configureMacOSPreferences, configureShell, installIterm2,
  installLauncher, prepareWorker, startPrepared,
} from "./setup.mts";
import type { OperationResult, SetupOutput } from "./setup.mts";
import { constants } from "node:os";

const [operation, ...args] = process.argv.slice(2);
const controller = new AbortController();
function onOutput({ stream, text }: SetupOutput) {
  process[stream].write(text);
}

function execute(): Promise<OperationResult> {
  const options = { signal: controller.signal, onOutput };
  const terminal = { ...options, terminal: true };
  switch (operation) {
    case "configure-shell": return configureShell(options);
    case "install-launcher": return installLauncher(options);
    case "install-iterm2": return installIterm2(options);
    case "configure-iterm2": return configureIterm2(options);
    case "configure-input": return configureMacOSPreferences({ scope: "input" }, options);
    case "configure-macos": return configureMacOSFromTerminal(args, terminal);
    case "prepare-worker":
      if (args.length !== 2) break;
      return prepareWorker(args[0], args[1], options);
    case "start-prepared": return startPrepared(process.env, terminal);
  }
  throw new TypeError("Invalid setup SDK operation.");
}

const signals = ["SIGHUP", "SIGINT", "SIGTERM"] as const;
const handlers = signals.map(signal => {
  const handler = () => {
    process.exitCode = 128 + constants.signals[signal];
    controller.abort();
  };
  process.on(signal, handler);
  return handler;
});
try {
  process.exitCode = (await execute()).exitCode;
} catch (error) {
  if (!controller.signal.aborted) {
    console.error(error instanceof Error ? error.message : "Setup SDK operation failed.");
    process.exitCode = 1;
  }
} finally {
  signals.forEach((signal, index) => process.off(signal, handlers[index]));
}
