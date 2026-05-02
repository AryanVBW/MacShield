// MacShield — Touch ID / Passkey enrollment & authentication (WebAuthn)
// Loaded by auth.html. Inline scripts are blocked by MV3 default CSP, so the
// logic must live in this external file.
(function () {
  "use strict";

  console.log("[MacShield/auth] script loaded");

  const params    = new URLSearchParams(location.search);
  const hostname  = params.get("host") || "Unknown";
  const mode      = params.get("mode") || "auth";
  const isEnroll  = mode === "enroll";
  const isMaster  = hostname === "_master"; // unlock popup master overlay
  const isEmbedded = params.get("embedded") === "1"; // iframed into a page overlay

  if (isEmbedded) document.body.classList.add("embedded");

  // Notify parent window when we finish. Used only in embedded mode where
  // we can't call window.close() on ourselves.
  function notifyParent(type, extra) {
    if (!isEmbedded) return;
    try {
      window.parent.postMessage(
        Object.assign({ type: "macshield-auth-" + type, hostname }, extra || {}),
        "*"
      );
    } catch (_) { /* parent gone — ignore */ }
  }

  // Close helper: in a standalone tab/window, use window.close(); in an iframe,
  // tell the parent to tear us down.
  function finish(type, extra, delay) {
    delay = delay == null ? 600 : delay;
    if (isEmbedded) {
      setTimeout(() => notifyParent(type, extra), delay);
    } else {
      setTimeout(() => window.close(), delay);
    }
  }

  const statusEl  = document.getElementById("statusMsg");
  const actionBtn = document.getElementById("actionBtn");
  const hostBadge = document.getElementById("hostBadge");
  const authTitle = document.getElementById("authTitle");
  const authSub   = document.getElementById("authSub");

  const MS_CRED_KEY = "ms_webauthn_cred_id";

  // Cached credential ID. Critical: navigator.credentials.get() MUST run in the
  // same synchronous task as the user click to preserve transient user
  // activation — especially on retries after a NotAllowedError, where Chrome
  // strictly enforces same-task activation. So we prefetch instead of doing
  // chrome.storage.local.get() inside the click handler.
  let cachedCredId = null;

  // ── base64url decode — credential.id from WebAuthn is already base64url,
  //    so we only need a decoder (backward-compat with legacy std base64 too) ──
  function b64urlToBuf(b64) {
    const s = b64.replace(/-/g, "+").replace(/_/g, "/");
    const padded = s + "=".repeat((4 - s.length % 4) % 4);
    const binary = atob(padded);
    const buf = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) buf[i] = binary.charCodeAt(i);
    return buf.buffer;
  }

  // ── AbortController — cancel in-flight WebAuthn call before retrying ──
  let abortCtrl = null;
  function freshSignal() {
    if (abortCtrl) abortCtrl.abort();
    abortCtrl = new AbortController();
    return abortCtrl.signal;
  }

  // ── Customise UI per mode ──
  if (isEnroll) {
    authTitle.textContent = "Set Up Passkey";
    authSub.textContent   = "Create a Touch ID passkey for MacShield";
    hostBadge.className   = "auth-host-enroll";
    hostBadge.textContent = "One-time setup";
    actionBtn.textContent = "Create Passkey";
  } else if (isMaster) {
    authTitle.textContent = "MacShield Locked";
    authSub.textContent   = "Verify with Touch ID to access settings";
    hostBadge.className   = "auth-host";
    hostBadge.textContent = "MacShield Protection";
    actionBtn.textContent = "Use Touch ID";
  } else {
    authTitle.textContent = "Passkey Required";
    authSub.textContent   = "Authenticate with Touch ID to unlock";
    hostBadge.className   = "auth-host";
    hostBadge.textContent = hostname;
    actionBtn.textContent = "Use Touch ID";
  }

  // ── Feature detection + show button ──
  // WebAuthn requires transient user activation in THIS window — a click is
  // the most reliable way to obtain it across Chrome's window-creation paths.
  actionBtn.style.display = "none";
  actionBtn.disabled      = true;
  statusEl.textContent    = "Checking device capability\u2026";
  statusEl.className      = "status-msg";

  actionBtn.addEventListener("click", () => {
    console.log("[MacShield/auth] button clicked, starting flow");
    start();
  });

  // Spec gate: isUserVerifyingPlatformAuthenticatorAvailable before passkey UI.
  // Also prefetch the credential ID so the click handler is fully synchronous.
  (async () => {
    if (!window.PublicKeyCredential ||
        !PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable) {
      statusEl.textContent = "Passkeys not supported in this browser";
      statusEl.className   = "status-msg error";
      console.warn("[MacShield/auth] PublicKeyCredential not available");
      return;
    }
    let available = false;
    try {
      available = await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable();
    } catch (e) {
      console.warn("[MacShield/auth] availability check threw", e);
    }
    if (!available) {
      statusEl.textContent = "Touch ID / biometric not available on this device";
      statusEl.className   = "status-msg error";
      return;
    }

    // Prefetch cached credential ID for auth mode (skip for enroll/master).
    if (!isEnroll) {
      cachedCredId = await new Promise((resolve) =>
        chrome.storage.local.get([MS_CRED_KEY], (r) => resolve(r[MS_CRED_KEY] || null))
      );
      if (!cachedCredId && !isMaster) {
        statusEl.textContent = "No passkey found \u2014 enroll first in MacShield Settings";
        statusEl.className   = "status-msg error";
        return;
      }
    }

    statusEl.textContent = isEnroll
      ? "Click below to create your passkey"
      : "Click below to authenticate with Touch ID";
    actionBtn.style.display = "inline-block";
    actionBtn.disabled      = false;
    actionBtn.focus();
    console.log("[MacShield/auth] ready, mode:", mode, "host:", hostname,
                "credId:", cachedCredId ? "loaded" : "none");
  })();

  function start() {
    // CRITICAL: this function MUST stay fully synchronous up to the
    // navigator.credentials.* call. Any async hop (await, chrome.storage,
    // setTimeout, etc.) between the user click and the WebAuthn call will
    // consume user activation — Chrome silently rejects subsequent calls
    // with NotAllowedError, especially after a prior cancellation.
    actionBtn.style.display = "none";
    actionBtn.disabled      = true;
    actionBtn.classList.remove("secondary");
    statusEl.className      = "status-msg";

    if (isEnroll) {
      statusEl.textContent = "Follow the system prompt\u2026";
      register();
      return;
    }

    if (!cachedCredId) {
      statusEl.textContent = "No passkey found \u2014 enroll first in MacShield Settings";
      statusEl.className   = "status-msg error";
      return;
    }

    statusEl.textContent = "Touch ID prompt opening\u2026";
    authenticate(cachedCredId); // synchronous — preserves user activation
  }

  // ── Register: create new platform credential ──
  function register() {
    console.log("[MacShield/auth] calling navigator.credentials.create()");
    const challenge = crypto.getRandomValues(new Uint8Array(32));
    const userId    = crypto.getRandomValues(new Uint8Array(16));

    navigator.credentials.create({
      publicKey: {
        challenge,
        rp: { name: "MacShield" }, // rpId omitted — defaults to extension origin
        user: {
          id:          userId,
          name:        "macshield-user",
          displayName: "MacShield User",
        },
        pubKeyCredParams: [
          { alg: -7,   type: "public-key" }, // ES256
          { alg: -257, type: "public-key" }, // RS256 fallback
        ],
        authenticatorSelection: {
          authenticatorAttachment: "platform",
          residentKey:             "preferred",
          requireResidentKey:      false,
          userVerification:        "required",
        },
        timeout:     60000,
        attestation: "none",
      },
      signal: freshSignal(),
    })
    .then((credential) => {
      console.log("[MacShield/auth] credential created:", credential.id);
      // credential.id is already base64url per spec — store it directly
      chrome.storage.local.set({ [MS_CRED_KEY]: credential.id }, () => {
        statusEl.textContent = "Passkey enrolled \u2014 you're all set!";
        statusEl.className   = "status-msg success";
        finish("enrolled", null, 1200);
      });
    })
    .catch((err) => {
      console.error("[MacShield/auth] create() failed:", err.name, err.message);
      handleError(err, "enroll");
    });
  }

  // ── Authenticate: assert existing platform credential ──
  function authenticate(credIdB64) {
    console.log("[MacShield/auth] calling navigator.credentials.get()");
    statusEl.textContent = "Touch ID prompt opening\u2026";
    statusEl.className   = "status-msg";
    actionBtn.style.display = "none";

    const challenge = crypto.getRandomValues(new Uint8Array(32));

    navigator.credentials.get({
      publicKey: {
        challenge,
        allowCredentials: [{
          id:         b64urlToBuf(credIdB64),
          type:       "public-key",
          transports: ["internal"],
        }],
        userVerification: "required",
        timeout:          60000,
      },
      signal: freshSignal(),
    })
    .then(() => {
      statusEl.textContent = "Verified \u2014 returning to page\u2026";
      statusEl.className   = "status-msg success";

      // Pass the original tab id so background can switch focus back to the
      // page that triggered auth and then close this auth tab cleanly.
      const originalTabId = parseInt(params.get("tabId"), 10);

      if (isMaster) {
        chrome.runtime.sendMessage({ action: "ms_masterUnlocked" });
        finish("verified", null, 500);
      } else {
        chrome.runtime.sendMessage({
          action: "ms_touchIDSuccess",
          hostname,
          originalTabId: Number.isFinite(originalTabId) ? originalTabId : null,
        });
        // Background will switch to the original tab and close this one.
        // Skip finish() so we don't race with background's chrome.tabs.remove.
      }
    })
    .catch((err) => {
      console.error("[MacShield/auth] get() failed:", err.name, err.message);
      handleError(err, "auth");
    });
  }

  // ── Centralised error handler (spec error names) ──
  function handleError(err, phase) {
    if (err.name === "AbortError") return; // our own abort — silent

    if (err.name === "InvalidStateError") {
      // Spec: passkey already exists on device — not an error
      chrome.storage.local.get([MS_CRED_KEY], (r) => {
        if (r[MS_CRED_KEY]) {
          statusEl.textContent = "Already enrolled \u2014 Touch ID is ready to use";
          statusEl.className   = "status-msg success";
          finish("enrolled", null, 1500);
        } else {
          statusEl.textContent = "Passkey exists on device but not in MacShield \u2014 reset from Settings and re-enroll";
          statusEl.className   = "status-msg error";
        }
      });
      return;
    }

    if (err.name === "NotAllowedError") {
      statusEl.textContent = phase === "enroll"
        ? "Setup cancelled — click to try again"
        : "Touch ID cancelled — click to retry";
    } else if (err.name === "SecurityError") {
      statusEl.textContent = "Security error — reload and try again";
    } else {
      statusEl.textContent = "Error: " + (err.message || err.name);
    }

    statusEl.className      = "status-msg error";
    actionBtn.style.display = "inline-block";
    actionBtn.disabled      = false;
    actionBtn.textContent   = phase === "enroll" ? "Try Again" : "Retry Touch ID";
    actionBtn.classList.add("secondary");
    actionBtn.focus();
  }
})();
