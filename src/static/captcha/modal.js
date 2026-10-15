"use strict";

(() => {
  if (window.PingChaModal) return;
  const nonce = document.currentScript.nonce;
  const rawFetch = window.fetch.bind(window);
  let dialog, frame, host, pending, resolvePending, previouslyFocused;

  async function cleared() {
    const response = await rawFetch("/_pingdom/pingcha/status", {
      credentials: "same-origin", cache: "no-store", signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) return false;
    const status = await response.json();
    return status.enabled === false || status.verified === true;
  }

  function show() {
    if (pending) return pending;
    pending = new Promise(resolve => { resolvePending = resolve; });
    previouslyFocused = document.activeElement;
    host = document.createElement("pingcha-modal");
    const shadow = host.attachShadow({mode: "open"});
    const style = document.createElement("link");
    style.rel = "stylesheet";
    style.href = "/_pingdom/captcha/modal.css";
    style.nonce = nonce;
    dialog = document.createElement("dialog");
    dialog.setAttribute("aria-label", "PingCha 브라우저 검증");
    dialog.addEventListener("cancel", event => event.preventDefault());
    frame = document.createElement("iframe");
    frame.src = "/_pingdom/captcha/?embed=1";
    frame.height = "80";
    frame.title = "PingCha 브라우저 검증";
    dialog.append(frame);
    shadow.append(style, dialog);
    document.body.append(host);
    dialog.showModal();
    return pending;
  }

  async function ensure() {
    if (pending) return pending;
    try { if (await cleared()) return; } catch (_) { /* The widget offers retry. */ }
    return show();
  }

  window.addEventListener("message", async event => {
    if (!pending || event.origin !== location.origin || event.source !== frame.contentWindow
        || !event.data) return;
    if (event.data.type === "pingcha:resize" && Number.isFinite(event.data.height)) {
      frame.height = String(Math.max(48, Math.min(180, Math.ceil(event.data.height))));
      return;
    }
    if (event.data.type !== "pingcha:verified" && event.data.type !== "pingcha:disabled") return;
    try { if (!await cleared()) return; } catch (_) { return; }
    const resolve = resolvePending;
    dialog.close();
    host.remove();
    pending = resolvePending = dialog = frame = host = undefined;
    if (previouslyFocused?.isConnected) previouslyFocused.focus();
    resolve();
  });

  function protectedAction(input, method = "GET") {
    if (method.toUpperCase() === "OPTIONS") return false;
    let url;
    try { url = new URL(input, location.href); } catch (_) { return false; }
    if (url.origin !== location.origin) return false;
    const path = url.pathname.replace(/^\/api\//, "/");
    if (path === "/auth/refresh" || path === "/auth/logout"
        || /^\/auth\/.*\/callback$/.test(path) || path.startsWith("/auth/callback")) return false;
    return path.startsWith("/auth/");
  }

  window.fetch = async function(input, init) {
    const url = input instanceof Request ? input.url : String(input);
    const method = init?.method || (input instanceof Request ? input.method : "GET");
    if (protectedAction(url, method)) await ensure();
    const response = await rawFetch(input, init);
    if (response.status === 403 && new URL(url, location.href).origin === location.origin) {
      try {
        if ((await response.clone().json()).code === "PINGCHA_REQUIRED") void show();
      } catch (_) { /* Preserve the application's original response. */ }
    }
    return response;
  };

  // Axios commonly uses XHR. Delay sending credentials, and preserve cancellation.
  const xhrOpen = XMLHttpRequest.prototype.open;
  const xhrSend = XMLHttpRequest.prototype.send;
  const xhrAbort = XMLHttpRequest.prototype.abort;
  const requests = new WeakMap();
  XMLHttpRequest.prototype.open = function(method, url, async = true, ...rest) {
    requests.set(this, {protected: async !== false && protectedAction(String(url), method), cancelled: false});
    return xhrOpen.call(this, method, url, async, ...rest);
  };
  XMLHttpRequest.prototype.abort = function() {
    const request = requests.get(this);
    if (request) request.cancelled = true;
    return xhrAbort.call(this);
  };
  XMLHttpRequest.prototype.send = function(body) {
    const request = requests.get(this);
    if (!request?.protected) return xhrSend.call(this, body);
    ensure().then(() => {
      if (!request.cancelled && requests.get(this) === request) xhrSend.call(this, body);
    }).catch(() => this.abort());
  };

  const submitting = new WeakSet();
  document.addEventListener("submit", event => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement) || submitting.has(form)
        || !protectedAction(form.action, form.method)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    const submitter = event.submitter;
    ensure().then(() => {
      if (!form.isConnected) return;
      submitting.add(form);
      try { form.requestSubmit(submitter?.isConnected ? submitter : undefined); }
      finally { submitting.delete(form); }
    });
  }, true);

  window.PingChaModal = {open: ensure};
  void ensure();
})();
