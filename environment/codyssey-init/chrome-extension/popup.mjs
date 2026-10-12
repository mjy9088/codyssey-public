const button = document.querySelector("#toggle");
const mode = document.querySelector("#mode");
const label = document.querySelector("#status");
const errorBox = document.querySelector("#error");
let enabled = false;

function send(message) {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendMessage(message, (response) => {
      const error = chrome.runtime.lastError;
      if (error || response?.error || !response?.status) {
        reject(new Error(error?.message || response?.error || "The extension did not respond."));
      } else resolve(response.status);
    });
  });
}

function render(status) {
  enabled = status.enabled;
  mode.value = status.mode;
  mode.disabled = enabled || status.blocked;
  button.textContent = enabled ? "Disable routing" : "Enable routing";
  button.disabled = status.blocked && !enabled;
  label.textContent = enabled ? "Routing enabled" : status.blocked ? "Proxy controlled elsewhere" : "Routing off";
}

function showError(error) {
  errorBox.textContent = error.message;
  errorBox.hidden = false;
}

// First-install routing can finish after the popup's initial status request.
// Also refresh when policy or another proxy extension changes the effective setting.
chrome.proxy.settings.onChange.addListener(() => {
  send({type: "status"}).then(render, showError);
});

button.addEventListener("click", async () => {
  button.disabled = true;
  errorBox.hidden = true;
  try {
    render(await send({type: "routing", enabled: !enabled, mode: mode.value}));
  } catch (error) {
    showError(error);
    try { render(await send({type: "status"})); } catch { button.disabled = false; }
  }
});

send({type: "status"}).then(render, (error) => {
  label.textContent = "Could not read proxy settings";
  showError(error);
});
