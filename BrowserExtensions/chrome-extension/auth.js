// MacShield — Multi-passkey enrollment & authentication (WebAuthn)
// Loaded by auth.html. Inline scripts are blocked by MV3 default CSP, so the
// logic must live in this external file.
//
// Supported URL params:
//   host      : hostname the caller wants unlocked (or "_master", "_setup")
//   mode      : "auth" | "enroll"
//   kind      : "platform" | "cross-device" | "roaming"   (enroll only)
//   label     : user-supplied label to store on success   (enroll only)
//   tabId     : id of the original tab that triggered auth (for focus return)
//   embedded  : "1" if this document is iframed into a page overlay
//
(function () {
  "use strict";

  console.log("[MacShield/auth] script loaded");

  const params    = new URLSearchParams(location.search);
  const hostname  = params.get("host")  || "Unknown";
  const mode      = params.get("mode")  || "auth";
  const kind      = params.get("kind")  || "platform";
  const labelHint = params.get("label") || "";
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

  const MS_PASSKEYS_KEY = "ms_passkeys";
  const MS_LEGACY_KEY   = "ms_webauthn_cred_id";

  // Cached passkey list. Critical: navigator.credentials.get() MUST run in the
  // same synchronous task as the user click to preserve transient user
  // activation — especially on retries after a NotAllowedError, where Chrome
  // strictly enforces same-task activation. So we prefetch instead of doing
  // chrome.storage.local.get() inside the click handler.
  let cachedPasskeys = [];   // Array<{id, kind, transports, ...}>

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
    if (kind === "cross-device") {
      authTitle.textContent = "Add Phone or Tablet";
      authSub.textContent   = "Use your phone's camera to scan the QR code shown by Chrome.";
      actionBtn.textContent = "Show QR Code";
    } else if (kind === "roaming") {
      authTitle.textContent = "Add Security Key";
      authSub.textContent   = "Insert or tap your security key when prompted (USB, NFC, or Bluetooth).";
      actionBtn.textContent = "Connect Security Key";
    } else {
      authTitle.textContent = "Set Up Passkey";
      authSub.textContent   = "Create a biometric passkey on this device.";
      actionBtn.textContent = "Create Passkey";
    }
    hostBadge.className   = "auth-host-enroll";
    hostBadge.textContent = labelHint ? ("Labelling as \u201C" + labelHint + "\u201D") : "One-time setup";
  } else if (isMaster) {
    authTitle.textContent = "MacShield Locked";
    authSub.textContent   = "Verify with a passkey to access settings";
    hostBadge.className   = "auth-host";
    hostBadge.textContent = "MacShield Protection";
    actionBtn.textContent = "Use Passkey";
  } else {
    authTitle.textContent = "Passkey Required";
    authSub.textContent   = "Authenticate with a passkey to unlock";
    hostBadge.className   = "auth-host";
    hostBadge.textContent = hostname;
    actionBtn.textContent = "Use Passkey";
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

  // Prefetch passkey list + run spec gates before showing the button.
  (async () => {
    if (!window.PublicKeyCredential) {
      statusEl.textContent = "Passkeys not supported in this browser";
      statusEl.className   = "status-msg error";
      console.warn("[MacShield/auth] PublicKeyCredential not available");
      return;
    }

    // Platform-authenticator availability is only REQUIRED for platform enroll.
    // Cross-device and roaming flows don't need a local UVPA — a phone or
    // security key provides the verification.
    if (isEnroll && kind === "platform") {
      let available = false;
      try {
        if (PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable) {
          available = await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable();
        }
      } catch (e) { console.warn("[MacShield/auth] UVPA check threw", e); }
      if (!available) {
        statusEl.textContent = "Biometric authentication not available on this device";
        statusEl.className   = "status-msg error";
        return;
      }
    }

    // Load the multi-passkey list. Fall back to the legacy single-cred key
    // for users who haven't migrated yet.
    cachedPasskeys = await new Promise((resolve) =>
      chrome.storage.local.get([MS_PASSKEYS_KEY, MS_LEGACY_KEY], (r) => {
        if (Array.isArray(r[MS_PASSKEYS_KEY]) && r[MS_PASSKEYS_KEY].length) {
          resolve(r[MS_PASSKEYS_KEY]);
        } else if (r[MS_LEGACY_KEY]) {
          resolve([{ id: r[MS_LEGACY_KEY], kind: "platform", transports: ["internal"] }]);
        } else {
          resolve([]);
        }
      })
    );

    if (!isEnroll && cachedPasskeys.length === 0 && !isMaster) {
      statusEl.textContent = "No passkey found \u2014 enroll first in MacShield Settings";
      statusEl.className   = "status-msg error";
      return;
    }

    statusEl.textContent = isEnroll
      ? (kind === "cross-device"
          ? "Click below — Chrome will show a QR code."
          : kind === "roaming"
            ? "Click below, then insert/tap your security key."
            : "Click below to create your passkey.")
      : "Click below to authenticate.";
    actionBtn.style.display = "inline-block";
    actionBtn.disabled      = false;
    actionBtn.focus();
    console.log("[MacShield/auth] ready — mode:", mode, "kind:", kind,
                "host:", hostname, "passkeys:", cachedPasskeys.length);
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

    if (cachedPasskeys.length === 0) {
      statusEl.textContent = "No passkey found \u2014 enroll first in MacShield Settings";
      statusEl.className   = "status-msg error";
      return;
    }

    statusEl.textContent = "Opening authenticator\u2026";
    authenticate(cachedPasskeys); // synchronous — preserves user activation
  }

  // ── Build authenticatorSelection for a given kind ──
  function selectionFor(kind) {
    if (kind === "cross-device") {
      // Omit authenticatorAttachment so Chrome shows the full chooser which
      // includes the "Use a phone or tablet" (hybrid / caBLE) option.
      return {
        residentKey:        "preferred",
        userVerification:   "required",
      };
    }
    if (kind === "roaming") {
      return {
        authenticatorAttachment: "cross-platform",
        residentKey:             "preferred",
        userVerification:        "required",
      };
    }
    return {
      authenticatorAttachment: "platform",
      residentKey:             "preferred",
      requireResidentKey:      false,
      userVerification:        "required",
    };
  }

  // ── Register: create a new credential of the requested kind ──
  function register() {
    console.log("[MacShield/auth] create() — kind:", kind);
    const challenge = crypto.getRandomValues(new Uint8Array(32));
    const userId    = crypto.getRandomValues(new Uint8Array(16));

    // Exclude existing credentials so the same authenticator can't enrol twice.
    const excludeCredentials = cachedPasskeys
      .filter((p) => p && p.id)
      .map((p) => ({
        id:         b64urlToBuf(p.id),
        type:       "public-key",
        transports: Array.isArray(p.transports) && p.transports.length
                      ? p.transports
                      : undefined,
      }));

    const publicKey = {
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
      authenticatorSelection: selectionFor(kind),
      excludeCredentials,
      timeout:     120000,
      attestation: "none",
    };

    // hints (Chrome 122+) steers the chooser toward the right UI affordance.
    // Unknown hints are ignored per spec, so it's safe on older browsers.
    if (kind === "cross-device") publicKey.hints = ["hybrid", "security-key"];
    else if (kind === "roaming") publicKey.hints = ["security-key"];
    else                         publicKey.hints = ["client-device"];

    navigator.credentials.create({ publicKey, signal: freshSignal() })
      .then((credential) => {
        console.log("[MacShield/auth] credential created:", credential.id);

        // Pull transports the authenticator actually reported — the list we
        // pass to get() later drives UI affordances (QR code vs BLE vs USB).
        let transports = [];
        try {
          const resp = credential.response;
          if (resp && typeof resp.getTransports === "function") {
            transports = resp.getTransports() || [];
          }
        } catch (_) {}

        chrome.runtime.sendMessage({
          action:     "ms_addPasskey",
          credId:     credential.id,           // already base64url per spec
          kind,
          label:      labelHint,
          transports,
        }, (resp) => {
          if (!resp || !resp.ok) {
            statusEl.textContent = "Saved locally, but registry write failed";
            statusEl.className   = "status-msg error";
          } else {
            statusEl.textContent = "Passkey enrolled \u2014 you're all set!";
            statusEl.className   = "status-msg success";
          }
          finish("enrolled", { credId: credential.id }, 1200);
        });
      })
      .catch((err) => {
        console.error("[MacShield/auth] create() failed:", err.name, err.message);
        handleError(err, "enroll");
      });
  }

  // ── Authenticate: assert any credential from the registry ──
  function authenticate(passkeys) {
    console.log("[MacShield/auth] get() — allowCredentials:", passkeys.length);
    statusEl.textContent    = "Opening authenticator\u2026";
    statusEl.className      = "status-msg";
    actionBtn.style.display = "none";

    const challenge = crypto.getRandomValues(new Uint8Array(32));

    // Per-credential transports let Chrome present the right affordance
    // (QR for hybrid, Bluetooth/USB for roaming, immediate biometric for
    // platform). Do NOT collapse them into one array.
    const allowCredentials = passkeys
      .filter((p) => p && p.id)
      .map((p) => ({
        id:         b64urlToBuf(p.id),
        type:       "public-key",
        transports: Array.isArray(p.transports) && p.transports.length
                      ? p.transports
                      : ["internal"],
      }));

    navigator.credentials.get({
      publicKey: {
        challenge,
        allowCredentials,
        userVerification: "required",
        timeout:          120000,
      },
      signal: freshSignal(),
    })
    .then((assertion) => {
      const usedCredId = assertion && assertion.id ? assertion.id : null;
      statusEl.textContent = "Verified \u2014 returning to page\u2026";
      statusEl.className   = "status-msg success";

      // Pass the original tab id so background can switch focus back to the
      // page that triggered auth and then close this auth tab.
      const originalTabId = parseInt(params.get("tabId"), 10);

      if (isMaster) {
        chrome.runtime.sendMessage({ action: "ms_masterUnlocked", credId: usedCredId });
        finish("verified", { credId: usedCredId }, 500);
      } else {
        chrome.runtime.sendMessage({
          action:        "ms_touchIDSuccess",
          hostname,
          credId:        usedCredId,
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
      // Spec: the selected authenticator already has a credential from our
      // excludeCredentials list. Treat as success if the registry knows it,
      // otherwise guide the user to reset and re-enrol.
      if (cachedPasskeys.length > 0) {
        statusEl.textContent = "This device is already enrolled \u2014 you're set";
        statusEl.className   = "status-msg success";
        finish("enrolled", null, 1500);
      } else {
        statusEl.textContent = "A passkey exists on this device but not in MacShield \u2014 reset from Settings and re-enroll";
        statusEl.className   = "status-msg error";
      }
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
