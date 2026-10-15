"use strict";

// Presentation only: the caller must obtain and validate server proof separately.
class PingCha {
  constructor(root) {
    this.root = root;
    this.control = root.querySelector(".captcha-control");
    this.label = root.querySelector(".captcha-label");
    this.icons = {
      idle: root.querySelector(".captcha-checkbox"),
      verifying: root.querySelector(".captcha-verifying"),
      success: root.querySelector(".captcha-success"),
    };
    this.resizeObserver = new ResizeObserver(([entry]) => {
      root.style.setProperty("--captcha-scale", Math.min(entry.contentRect.width / 601, 1));
    });
    this.resizeObserver.observe(root);
    this.handleClick = () => {
      if (this.state !== "idle") return;
      this.setState("verifying");
      root.dispatchEvent(new CustomEvent("pingdom:verify", { bubbles: true }));
    };
    this.control.addEventListener("click", this.handleClick);
    this.setState("idle");
  }

  setState(state) {
    const labels = { idle: "Verify you are human", verifying: "Verifying...", success: "인증되었습니다" };
    if (!Object.hasOwn(labels, state)) throw new TypeError("Unknown CAPTCHA state");
    this.state = state;
    this.root.dataset.state = state;
    this.control.disabled = state !== "idle";
    this.control.setAttribute("aria-checked", state === "success" ? "true" : state === "verifying" ? "mixed" : "false");
    this.control.setAttribute("aria-label", labels[state]);
    this.label.textContent = labels[state];
    for (const [name, icon] of Object.entries(this.icons)) icon.hidden = name !== state;
  }

  destroy() {
    this.resizeObserver.disconnect();
    this.control.removeEventListener("click", this.handleClick);
  }
}

window.PingCha = PingCha;
