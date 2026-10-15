"use strict";

(() => {
  const embedded = new URL(location.href).searchParams.get("embed") === "1";
  if (embedded) document.body.classList.add("is-embedded");
  const root = document.getElementById("captcha");
  const widget = new window.PingCha(root);
  const errorMessage = document.getElementById("pingcha-error");
  const scriptUrl = document.currentScript.src;
  let active = false;
  let worker;
  let frameSizer;
  if (embedded && window.parent !== window) {
    frameSizer = new ResizeObserver(([entry]) => {
      window.parent.postMessage({type: "pingcha:resize", height: entry.contentRect.height}, location.origin);
    });
    frameSizer.observe(root.parentElement);
  }

  async function request(path, options = {}) {
    const res = await fetch(`/_pingdom/pingcha/${path}`, {
      ...options, credentials: "same-origin", cache: "no-store", signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) throw new Error(`Verification failed (${res.status})`);
    return res.json();
  }

  function solve(challenge) {
    return new Promise((resolve, reject) => {
      worker = new Worker(new URL("worker.js", scriptUrl));
      const deadline = setTimeout(() => { worker.terminate(); reject(new Error("Worker timeout")); }, 2500);
      worker.onmessage = ({data}) => {
        clearTimeout(deadline);
        worker.terminate();
        if (data.error) reject(new Error(data.error));
        else resolve(data.counter);
      };
      worker.onerror = () => { clearTimeout(deadline); worker.terminate(); reject(new Error("Worker unavailable")); };
      worker.postMessage(challenge);
    });
  }

  function complete() {
    widget.setState("success");
    root.dispatchEvent(new CustomEvent("pingcha:verified", {bubbles: true}));
    if (embedded) {
      if (window.parent !== window) window.parent.postMessage({type: "pingcha:verified"}, location.origin);
      return;
    }
    const returnTo = new URL(location.href).searchParams.get("return_to");
    if (!returnTo || !returnTo.startsWith("/") || returnTo.startsWith("//") || /[\\\u0000-\u0020]/.test(returnTo)) return;
    const target = new URL(returnTo, location.origin);
    if (target.origin === location.origin && !target.pathname.startsWith("/_pingdom/")) {
      location.replace(target.href);
    }
  }

  function disabled() {
    root.hidden = true;
    if (embedded && window.parent !== window) {
      window.parent.postMessage({type: "pingcha:disabled"}, location.origin);
    }
  }

  async function verify() {
    if (active) return;
    active = true;
    errorMessage.hidden = true;
    widget.setState("verifying");
    try {
      if (!window.isSecureContext || !crypto.subtle) throw new Error("Secure context required");
      const challenge = await request("challenge");
      if (challenge.enabled === false) return disabled();
      if (challenge.verified !== true) {
        const counter = await solve(challenge);
        const result = await request("verify", {
          method: "POST", headers: {"Content-Type": "application/json"},
          body: JSON.stringify({id: challenge.id, counter}),
        });
        if (result.enabled === false) return disabled();
        if (result.verified !== true) throw new Error("Verification rejected");
        // Verify that the HttpOnly clearance cookie was actually accepted by the browser.
        const clearance = await request("challenge");
        if (clearance.enabled === false) return disabled();
        if (clearance.verified !== true) throw new Error("Clearance cookie unavailable");
      }
      complete();
    } catch (error) {
      widget.setState("idle");
      errorMessage.textContent = "검증을 완료하지 못했어요. 체크박스를 눌러 다시 시도해 주세요.";
      errorMessage.hidden = false;
    } finally { active = false; }
  }

  root.addEventListener("pingdom:verify", verify);
  window.addEventListener("pagehide", () => {
    if (worker) worker.terminate();
    if (frameSizer) frameSizer.disconnect();
    widget.destroy();
  });
  window.addEventListener("pageshow", (event) => { if (event.persisted) location.reload(); });
  if (location.protocol === "file:" || location.pathname.startsWith("/static/")) {
    errorMessage.textContent = "서버 검증은 OpenResty의 /_pingdom/captcha/에서 실행됩니다.";
    errorMessage.hidden = false;
    return;
  }
  verify();
})();
