const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const listeners = {}, documentListeners = {}, frames = [], dialogs = [];
let verified = false, enabled = true, credentialRequests = 0, xhrSends = 0;
const next = () => new Promise(resolve => setImmediate(resolve));
class Element {
  constructor(tag) { this.tag = tag; this.contentWindow = {}; this.isConnected = true; }
  attachShadow() { return new Element("shadow"); }
  append() {}
  addEventListener() {}
  setAttribute() {}
  showModal() { this.open = true; }
  close() { this.open = false; }
  remove() { this.isConnected = false; }
  focus() {}
}
class XHR { open() {} send() { xhrSends++; } abort() {} }
let formSends = 0;
class Form extends Element {
  constructor() { super("form"); this.action = "https://example.test/auth/login"; this.method = "post"; }
  requestSubmit(submitter) {
    let prevented = false;
    documentListeners.submit({target: this, submitter, preventDefault() { prevented = true; }, stopImmediatePropagation() {}});
    if (!prevented) formSends++;
  }
}
const context = {
  URL, Request, AbortSignal, XMLHttpRequest: XHR, HTMLFormElement: Form,
  location: new URL("https://example.test/console/login"),
  document: {
    currentScript: {nonce: "test-nonce"}, activeElement: new Element("input"),
    body: new Element("body"), addEventListener(name, fn) { documentListeners[name] = fn; },
    createElement(tag) {
      const element = new Element(tag);
      if (tag === "iframe") frames.push(element);
      if (tag === "dialog") dialogs.push(element);
      return element;
    },
  },
  window: {
    addEventListener(name, fn) { listeners[name] = fn; },
    fetch: async url => {
      if (url === "/_pingdom/pingcha/status") return {ok: true, json: async () => ({enabled, verified})};
      if (url === "/auth/login") credentialRequests++;
      return {ok: true, status: 200};
    },
  },
};

const completion = (source = frames.at(-1).contentWindow, origin = "https://example.test") =>
  listeners.message({source, origin, data: {type: "pingcha:verified"}});

(async () => {
  vm.runInNewContext(fs.readFileSync("src/static/captcha/modal.js", "utf8"), context);
  await next();
  assert.equal(dialogs.at(-1).open, true);
  const login = context.window.fetch("/auth/login", {method: "POST"});
  await next();
  assert.equal(credentialRequests, 0);
  await completion({}, "https://example.test");
  await completion(frames.at(-1).contentWindow, "https://evil.test");
  await completion(); // A legitimate frame message is insufficient without a server cookie.
  assert.equal(dialogs.at(-1).open, true);
  assert.equal(credentialRequests, 0);
  verified = true;
  await completion();
  assert.equal((await login).status, 200);
  assert.equal(dialogs.at(-1).open, false);
  assert.equal(credentialRequests, 1, "Never replay login requests");

  verified = false;
  const xhr = new XHR();
  xhr.open("POST", "/auth/login");
  xhr.send("credentials");
  await next();
  xhr.abort();
  verified = true;
  await completion();
  await next();
  assert.equal(xhrSends, 0, "Cancelled XHR must not send after verification");
  const form = new Form();
  form.requestSubmit(new Element("button"));
  await next();
  assert.equal(formSends, 1, "Native forms resume once, without recursive resubmission");
  enabled = verified = false;
  const oldCount = dialogs.length;
  await context.window.fetch("/auth/login", {method: "POST"});
  assert.equal(dialogs.length, oldCount, "Disabled mode must not mount a modal");
  console.log("PASS PingCha modal: server-confirmed dismissal, message origin/source, single send, XHR cancellation");
})();
