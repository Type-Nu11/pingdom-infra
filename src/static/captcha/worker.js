"use strict";

// One worker, at most 16,384 small hashes or 1.5 seconds of work per attempt.
self.onmessage = async ({data}) => {
  try {
    if (typeof data.nonce !== "string" || !/^[a-f0-9]{64}$/.test(data.nonce) || data.difficulty !== 10) {
      throw new Error("Invalid challenge");
    }
    const encoder = new TextEncoder();
    const started = performance.now();
    for (let counter = 0; counter < 16384 && performance.now() - started < 1500; counter++) {
      const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(`${data.nonce}:${counter}`)));
      if (bytes[0] === 0 && bytes[1] < 64) {
        self.postMessage({counter});
        return;
      }
    }
    throw new Error("Verification timed out");
  } catch (error) {
    self.postMessage({error: error.message});
  }
};
