const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const source = fs.readFileSync("src/static/captcha/runtime.js", "utf8");

async function run(returnTo, {embedded = false, rejected = false, enabled = true, statusVerified = true} = {}) {
  let replaced, state = "idle", event, requests = 0, now = 0, timerId = 0;
  const timers = new Map(), handlers = {}, windowHandlers = {};
  const root = {addEventListener(name, fn) { handlers[name] = fn; }, dispatchEvent(e) { event = e.type; }};
  const error = {hidden: true};
  const location = new URL("https://example.test/_pingdom/captcha/");
  if (returnTo) location.searchParams.set("return_to", returnTo);
  if (embedded) location.searchParams.set("embed", "1");
  location.replace = url => { replaced = url; };
  const context = {
    URL, AbortSignal, location,
    setTimeout(fn, delay) { timers.set(++timerId, {fn, due: now + delay}); return timerId; },
    clearTimeout(id) { timers.delete(id); },
    CustomEvent: class { constructor(type) { this.type = type; } },
    crypto: require("node:crypto").webcrypto,
    window: {
      isSecureContext: true, addEventListener(name, fn) { windowHandlers[name] = fn; },
      PingCha: class { setState(s) { state = s; } destroy() {} },
    },
    document: {
      body: {classList: {add() {}}},
      getElementById: id => id === "captcha" ? root : error,
      currentScript: {src: "https://example.test/_pingdom/captcha/runtime.js"},
    },
    fetch: async path => {
      requests++;
      return {ok: !rejected, status: 403,
        json: async () => ({enabled, verified: path.endsWith("/status") ? statusVerified : enabled})};
    },
  };
  context.window.parent = context.window;
  vm.runInNewContext(source, context);
  const snapshot = () => ({replaced, state, event, requests, error: error.hidden, hidden: root.hidden});
  return {
    snapshot,
    click: async () => { await handlers["pingdom:verify"](); return snapshot(); },
    leave: () => windowHandlers.pagehide(),
    advance: async ms => {
      now += ms;
      for (const [id, task] of [...timers]) if (task.due <= now) { timers.delete(id); await task.fn(); }
      return snapshot();
    },
  };
}

(async () => {
  const success = await run("/console/login?next=%2Fusers");
  assert.equal(success.snapshot().requests, 0, "No verification request before a checkbox click");
  assert.equal(success.snapshot().state, "idle");
  await success.click();
  assert.equal(success.snapshot().state, "success");
  assert.equal(success.snapshot().replaced, undefined);
  assert.equal((await success.advance(999)).event, undefined, "Hold the success state for one second");
  assert.equal((await success.advance(1)).replaced, "https://example.test/console/login?next=%2Fusers");
  for (const path of ["//evil.test", "https://evil.test/", "/\\evil.test", "/\nevil.test", "/_pingdom/captcha/"]) {
    const blocked = await run(path);
    await blocked.click();
    assert.equal((await blocked.advance(1000)).replaced, undefined, path);
  }
  const embed = await run("/console/login", {embedded: true});
  await embed.click();
  assert.equal(embed.snapshot().event, undefined);
  assert.equal((await embed.advance(1000)).event, "pingcha:verified");
  const failure = await run("/console/login", {rejected: true});
  assert.equal((await failure.click()).state, "idle");
  assert.equal(failure.snapshot().error, false);
  const disabled = await run("/console/login", {enabled: false});
  assert.equal((await disabled.click()).hidden, true);
  assert.equal((await disabled.advance(1000)).event, undefined);
  const expired = await run("/console/login", {statusVerified: false});
  await expired.click();
  assert.equal((await expired.advance(1000)).state, "idle");
  assert.equal(expired.snapshot().event, undefined);
  const abandoned = await run("/console/login");
  await abandoned.click();
  abandoned.leave();
  assert.equal((await abandoned.advance(1000)).replaced, undefined);
  console.log("PASS PingCha runtime: click-to-start, 1-second success, expiry, safe return paths, page cleanup");
})();
