import {readStatus, changeRouting} from "./proxy.mjs";

async function updateBadge() {
  const status = await readStatus(chrome);
  await chrome.action.setBadgeText({text: status.enabled ? "ON" : ""});
  await chrome.action.setBadgeBackgroundColor({color: "#147d64"});
  await chrome.action.setTitle({title: status.enabled ? "Codyssey Tailnet: routing enabled" : "Codyssey Tailnet: routing off"});
  return status;
}

chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (sender.id !== chrome.runtime.id || !["status", "routing"].includes(message?.type)) return false;
  (async () => {
    if (message.type === "routing") await changeRouting(chrome, message.enabled === true, message.mode);
    return {status: await updateBadge()};
  })().then(respond, (error) => respond({error: error.message}));
  return true;
});

const refresh = () => { updateBadge().catch(() => {}); };
chrome.runtime.onInstalled.addListener((details) => {
  (async () => {
    if (details.reason === "install") {
      const startup = await fetch(chrome.runtime.getURL("startup.json")).then((response) => response.json());
      if (startup.enableOnInstall === true) await changeRouting(chrome, true, "tailnet");
    }
    await updateBadge();
  })().catch(() => {
    chrome.action.setBadgeText({text: "!"});
    chrome.action.setTitle({title: "Tailnet setup failed: open the extension to check routing"});
  });
});
chrome.runtime.onStartup.addListener(refresh);
chrome.proxy.settings.onChange.addListener(refresh);
chrome.proxy.onProxyError.addListener(() => {
  chrome.action.setBadgeText({text: "!"});
  chrome.action.setBadgeBackgroundColor({color: "#a53a33"});
  chrome.action.setTitle({title: "Tailnet proxy error: check the container and Tailscale login"});
});
