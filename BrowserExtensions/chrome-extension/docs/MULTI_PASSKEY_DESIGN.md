# Multi-Passkey Authentication — Design Plan

> Status: **Planning / not implemented**
> Scope: MacShield Chrome extension (MV3). Extends the existing single-credential
> WebAuthn flow in `auth.js` / `background.js` to a multi-credential model that
> supports platform, cross-device (hybrid / caBLE), and roaming passkeys.

---

## 1. Goals

1. Let a user register **N passkeys** against the same MacShield account.
2. Support three passkey classes:
   - **Platform** — Touch ID, Windows Hello, Android biometric (built into the device).
   - **Cross-device / hybrid (caBLE)** — phone scans a QR shown by the browser (Google Passkeys, iCloud Keychain, Samsung Pass, etc.).
   - **Roaming / Bluetooth** — external authenticator (YubiKey, phone used as security key).
3. Give first-class UI for add / list / rename / revoke / recover.
4. Keep password as a universal fallback; never allow total lockout.

Non-goals (v1): server-side sync, shared accounts, attestation verification.

---

## 2. Current state (baseline)

Relevant today:

- `@/Volumes/DATA_vivek/GITHUB/MacShield/BrowserExtensions/chrome-extension/auth.js:47` — single credential stored under `ms_webauthn_cred_id`.
- `@/Volumes/DATA_vivek/GITHUB/MacShield/BrowserExtensions/chrome-extension/auth.js:186-208` — `create()` forces `authenticatorAttachment: "platform"`.
- `@/Volumes/DATA_vivek/GITHUB/MacShield/BrowserExtensions/chrome-extension/auth.js:234-246` — `get()` uses a single-entry `allowCredentials` with `transports: ["internal"]`.
- `@/Volumes/DATA_vivek/GITHUB/MacShield/BrowserExtensions/chrome-extension/background.js:166-176` — `ms_getLockState` reports `hasTouchID` from the single key.

All of this has to become list-aware.

---

## 3. Data model

New storage key (in `chrome.storage.local`):

```js
ms_passkeys: [
  {
    id:            "base64url-credential-id",   // from credential.id
    label:         "MacBook Pro (Touch ID)",    // user-editable
    kind:          "platform" | "cross-device" | "roaming",
    transports:    ["internal"] | ["hybrid"] | ["usb","nfc","ble"] | [...],
    createdAt:     1730000000000,
    lastUsedAt:    1730000500000,
    lastUsedHost:  "web.whatsapp.com" | "_master" | null,
    aaguid:        "…" | null,                  // optional, for device labels
    backupEligible:true,                        // BE flag from authenticator data
    backupState:   true,                        // BS flag (synced?)
  },
  …
]
```

Migration from v3.1:

- On load, if `ms_webauthn_cred_id` exists and `ms_passkeys` is empty → seed one entry:
  ```
  { id: <existing>, label: "This device", kind: "platform",
    transports: ["internal"], createdAt: Date.now(), lastUsedAt: null }
  ```
  Keep the old key for one release as a read fallback, then delete.

Audit log (for "security alerts"):

```js
ms_passkey_events: [
  { t: 1730…, type: "added"|"removed"|"used"|"failed", credId, host, ua }
]
// capped to last 50 entries
```

Recovery:

```js
ms_recovery_codes: [ "xxxx-xxxx-xxxx", … ]   // hashed (sha256+salt), one-time
```

---

## 4. Registration flows

All three share the same `navigator.credentials.create()` call — the difference
is only in `authenticatorSelection` and UI copy.

### 4.1 Add platform passkey (this device)

```js
authenticatorSelection: {
  authenticatorAttachment: "platform",
  residentKey: "preferred",
  userVerification: "required",
}
```

Same as today; just push into `ms_passkeys`.

### 4.2 Add cross-device passkey (phone / Google Passkey)

```js
authenticatorSelection: {
  // OMIT authenticatorAttachment → browser shows the full chooser, which
  // includes the "Use a phone or tablet" QR-code option (hybrid transport).
  residentKey: "preferred",
  userVerification: "required",
},
// hints is the modern steering mechanism (Chrome 122+). Fall back gracefully.
hints: ["hybrid", "security-key"],
```

UI: "Scan the QR code with your phone's camera. Your phone's passkey manager
(Google Password Manager, iCloud Keychain, 1Password, etc.) will create a passkey."

### 4.3 Add roaming / security key (Bluetooth / USB / NFC)

```js
authenticatorSelection: {
  authenticatorAttachment: "cross-platform",
  residentKey: "preferred",
  userVerification: "required",
},
hints: ["security-key"],
```

### 4.4 Exclude-list to prevent duplicates

```js
excludeCredentials: ms_passkeys.map(p => ({
  id: b64urlToBuf(p.id),
  type: "public-key",
  transports: p.transports,
}))
```

This makes the authenticator refuse to create a second credential on a device
that already has one — handled today via the `InvalidStateError` branch
(`@/Volumes/DATA_vivek/GITHUB/MacShield/BrowserExtensions/chrome-extension/auth.js:278-291`);
keep that handler and show "This device already has a passkey called X".

---

## 5. Authentication flow

### 5.1 Default: let the browser pick

```js
navigator.credentials.get({
  publicKey: {
    challenge,
    allowCredentials: ms_passkeys.map(p => ({
      id: b64urlToBuf(p.id),
      type: "public-key",
      transports: p.transports,   // critical — drives UI & speed
    })),
    userVerification: "required",
    timeout: 60000,
  },
  signal: freshSignal(),
  mediation: "optional",          // allow conditional UI where supported
})
```

- Chrome's native chooser lists every matching credential with the correct
  icon (Touch ID, phone-via-QR, security key) — no in-extension picker needed
  for the common case.
- `transports` per-credential is what makes the QR / BLE flow appear for
  hybrid entries and stay hidden for platform-only entries. **Do not collapse
  them to a single array.**

### 5.2 Pre-auth picker (optional, power-user)

If the user wants to pin the attempt to a specific key (e.g. "Use my YubiKey"),
show an in-extension list and call `get()` with a single-entry
`allowCredentials`. This is the same pattern `auth.js` uses today — just
parameterised by which `ms_passkeys[i]` is selected.

### 5.3 Fallback chain

```
passkey (default) ─✗─► passkey (explicit picker)
                              │
                              ✗
                              ▼
                        master password
                              │
                              ✗
                              ▼
                        recovery code
```

Fallback is already partly wired in `popup.html` (Touch ID button + password
field). Extend `mLoginMsg` copy after N failures to point at recovery.

---

## 6. UI / UX

### 6.1 Settings → "Passkeys" section (replaces current Touch ID card)

```
┌─ Passkeys ──────────────────────────────────── [+ Add] ─┐
│ ◉ MacBook Pro (Touch ID)           Last used 2m ago    │
│    Platform · this device                     [ ⋯ ]    │
│ ◉ iPhone 15                         Last used 3d ago    │
│    Cross-device · synced via iCloud           [ ⋯ ]    │
│ ◉ YubiKey 5C                        Never used         │
│    Security key · USB/NFC                     [ ⋯ ]    │
└────────────────────────────────────────────────────────┘
```

- `[+ Add]` opens a modal with three cards:
  1. **This device** — platform authenticator.
  2. **Phone or tablet** — QR / hybrid.
  3. **Security key** — USB / NFC / BLE.
- `[ ⋯ ]` menu per row: **Rename**, **Test**, **Remove**.
- Guard: removing the last passkey shows a confirm dialog and only proceeds
  if a master password is set.

### 6.2 Labels (auto-suggested)

Order of preference:

1. `PublicKeyCredential.authenticatorAttachment` + `getClientExtensionResults()` AAGUID lookup against a bundled static table (e.g. YubiKey AAGUIDs).
2. Transport-derived guess: `internal` → "This device"; `hybrid` → "Phone or tablet"; `usb`/`nfc`/`ble` → "Security key".
3. UA parse from registration time (`Mac`, `Windows`, `iPhone`, `Android`).

User can always override via **Rename**.

### 6.3 Master login screen

Extend `@/Volumes/DATA_vivek/GITHUB/MacShield/BrowserExtensions/chrome-extension/popup.html:414-431`:

- Primary button: **"Sign in with passkey"** (shown whenever `ms_passkeys.length > 0`, not gated on `os === 'mac'`).
- Secondary link: **"Use a different passkey"** → in-extension picker.
- Tertiary: password input.
- Footer link: **"Can't sign in? Use recovery code"**.

---

## 7. Messaging / background changes

New / changed `chrome.runtime` actions:

| Action | Purpose |
|---|---|
| `ms_listPasskeys` | Return sanitised list (no raw IDs unless requested) |
| `ms_addPasskey` | `{ credential, kind, label }` → push + audit log |
| `ms_renamePasskey` | `{ id, label }` |
| `ms_removePasskey` | `{ id }` → splice + audit log + alert |
| `ms_touchIDSuccess` | **Change**: now also accepts `credId` so we can update `lastUsedAt` |
| `ms_generateRecoveryCodes` | Generate 8 one-time codes, store hashes, return plaintext once |
| `ms_consumeRecoveryCode` | Verify + mark used |

`ms_getLockState` (`@/Volumes/DATA_vivek/GITHUB/MacShield/BrowserExtensions/chrome-extension/background.js:164-180`) should return
`passkeyCount` instead of the boolean `hasTouchID`. Keep `hasTouchID` as an
alias (`passkeyCount > 0`) for one release.

---

## 8. Security alerts

Trigger a Chrome notification (requires adding `"notifications"` to
`permissions` in `@/Volumes/DATA_vivek/GITHUB/MacShield/BrowserExtensions/chrome-extension/manifest.json:6`) whenever:

- A new passkey is added → "New passkey 'iPhone 15' added to MacShield."
- A passkey is removed → "Passkey '…' removed."
- 3+ failed auth attempts in 60s on the master overlay.

All events also land in `ms_passkey_events` so Settings can show an
"Activity" sub-tab.

---

## 9. Recovery

- On first password setup **or** when the user enables multi-passkey, prompt
  to generate 8 one-time recovery codes. Show once, store only salted sha256
  hashes. Offer "Download .txt" / "Copy all".
- A recovery code validates like the password (`ms_verifyPassword`-style) and
  additionally **revokes all existing passkeys** on success, forcing re-enrolment — this is the "all passkeys lost" path.
- Remote revoke (v1.5): if/when we add an optional account sync backend, a
  `revoke(credId)` RPC can mark an entry `revoked: true` locally on next sync.
  No-op for now.

---

## 10. Cross-platform caveats

- **Hybrid (QR) works in Chrome on Mac, Windows, Linux, ChromeOS** as long as
  the paired phone has Bluetooth + internet. It does **not** require Bluetooth
  on the desktop in modern caBLE v2 (CTAP 2.2) — only proximity signalling.
  Still: surface a "Bluetooth off?" hint on failure.
- **Linux + platform authenticator** = usually unavailable → hide "This device"
  option when `isUserVerifyingPlatformAuthenticatorAvailable()` returns false
  (logic already exists at `@/Volumes/DATA_vivek/GITHUB/MacShield/BrowserExtensions/chrome-extension/auth.js:119-129`).
- **Chrome extension origin**: `rp.id` is implicit and equals the extension
  origin. Passkeys therefore do **not** roam across browsers (Firefox will not
  see Chrome-origin credentials). Document this; recommend enrolling one
  passkey per browser the user cares about.

---

## 11. Implementation phases

1. **Phase 1 — data layer**
   - Introduce `ms_passkeys`, migration from `ms_webauthn_cred_id`, updated
     background handlers. Ship behind a flag, keep current UI.
2. **Phase 2 — add/remove UI**
   - Replace Touch ID card with the passkey list. Single "Add" button that
     defaults to platform (parity with today).
3. **Phase 3 — cross-device + roaming**
   - Add the three-card "Add a passkey" modal. Wire `hints` / `attachment`
     variants. Update `allowCredentials` to the full list.
4. **Phase 4 — labels, last-used, alerts**
   - AAGUID table, notification permission, activity sub-tab.
5. **Phase 5 — recovery codes**
   - Generation, storage, consume path, "revoke all" behaviour.

Each phase is independently shippable and leaves the extension in a working
state.

---

## 12. Open questions

- Do we want **conditional UI** (autofill-style) for the master overlay? It's
  a nice touch but only fires on `<input autocomplete="webauthn">` fields and
  needs `mediation: "conditional"` + `isConditionalMediationAvailable()`.
- Should recovery codes also revoke the **password**, or only passkeys? Leaning
  passkeys-only, so the password remains the deterministic fallback.
- AAGUID table: bundle static JSON vs. fetch from FIDO MDS. Static is simpler
  and matches the "no network" promise in `README.md`.
