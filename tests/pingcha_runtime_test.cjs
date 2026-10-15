const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const source = fs.readFileSync("src/static/captcha/runtime.js", "utf8");

async function run(returnTo, {embedded = false, rejected = false, enabled = true} = {}) {
  let replaced, state, event;
  const root = {addEventListener() {}, dispatchEvent(e) { event = e.type; }};
  const error = {hidden: true};
  const location = new URL("https://example.test/_pingdom/captcha/");
  if (returnTo) location.searchParams.set("return_to", returnTo);
  if (embedded) location.searchParams.set("embed", "1");
  location.replace = url => { replaced = url; };
  const context = {
    URL, AbortSignal, setTimeout, clearTimeout, location,
    CustomEvent: class { constructor(type) { this.type = type; } },
    crypto: require("node:crypto").webcrypto,
    window: {isSecureContext: true, addEventListener() {}, PingCha: class { setState(s) { state = s; } }},
    document: {
      body: {classList: {add() {}}},
      getElementById: id => id === "captcha" ? root : error,
      currentScript: {src: "https://example.test/_pingdom/captcha/runtime.js"},
    },
    fetch: async () => ({ok: !rejected, status: 403, json: async () => ({enabled, verified: enabled})}),
  };
  context.window.parent = context.window;
  vm.runInNewContext(source, context);
  await new Promise(resolve => setImmediate(resolve));
  return {replaced, state, event, error: error.hidden, hidden: root.hidden};
}

(async () => {
  assert.equal((await run("/console/login?next=%2Fusers")).replaced, "https://example.test/console/login?next=%2Fusers");
  for (const path of ["//evil.test", "https://evil.test/", "/\\evil.test", "/\nevil.test", "/_pingdom/captcha/"]) {
    assert.equal((await run(path)).replaced, undefined, path);
  }
  const embed = await run("/console/login", {embedded: true});
  assert.equal(embed.replaced, undefined);
  assert.equal(embed.event, "pingcha:verified");
  assert.equal(embed.state, "success");
  const failure = await run("/console/login", {rejected: true});
  assert.equal(failure.state, "idle");
  assert.equal(failure.replaced, undefined);
  assert.equal(failure.error, false);
  const disabled = await run("/console/login", {enabled: false});
  assert.equal(disabled.hidden, true);
  assert.equal(disabled.event, undefined);
  assert.equal(disabled.replaced, undefined);
  console.log("PASS PingCha runtime: safe return paths, embed completion, rejected verification");
})();
