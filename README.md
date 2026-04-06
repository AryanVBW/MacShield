# 🔒 PrivyBlur — Chat Privacy Shield

**Free, open-source Chrome extension that blurs all chat messages across every major platform. Only the chat you hover over becomes readable.**

## Supported Platforms

| Platform | Web URL | Status |
|----------|---------|--------|
| WhatsApp | web.whatsapp.com | ✅ Full support |
| Instagram | www.instagram.com/direct | ✅ Full support |
| Telegram | web.telegram.org | ✅ Full support |
| Messenger | www.messenger.com | ✅ Full support |
| Discord | discord.com | ✅ Full support |
| Slack | app.slack.com | ✅ Full support |
| X / Twitter | x.com, twitter.com | ✅ DMs & tweets |
| LinkedIn | www.linkedin.com | ✅ Messaging |
| Gmail | mail.google.com | ✅ Inbox & emails |
| Microsoft Teams | teams.microsoft.com | ✅ Full support |
| Facebook | www.facebook.com | ✅ Chat messages |
| Signal | signal.group | ✅ Basic support |
| Element | app.element.io | ✅ Basic support |

## How It Works

1. **All messages are blurred** by default when you open a supported chat app
2. **Hover over any message** to reveal it — only that message unblurs
3. **Move your mouse away** — the message blurs again
4. **Press `Alt + X`** to toggle blur on/off instantly
5. **Adjust blur intensity** from the popup (2px to 20px)

## Installation (3 minutes)

### Option A: Load as Unpacked Extension (Recommended)

1. Open Chrome and go to `chrome://extensions/`
2. Enable **Developer mode** (toggle in top-right corner)
3. Click **"Load unpacked"**
4. Select the `privyblur-extension` folder
5. Done! The extension icon appears in your toolbar

### Option B: From ZIP

1. Unzip the `privyblur-extension.zip` file
2. Follow steps 1-5 above

## Usage

- Click the **PrivyBlur icon** in your toolbar to see the control panel
- Use the **toggle switch** to turn blur on/off for the current site
- Use the **blur intensity slider** to adjust how strong the blur is
- Press **Alt + X** on any supported site to quickly toggle

## Privacy & Security

- ✅ **Zero data collection** — nothing is sent anywhere
- ✅ **No analytics** — no tracking of any kind
- ✅ **Runs locally** — blur is applied via CSS only
- ✅ **Open source** — inspect every line of code
- ✅ **No network requests** — works fully offline
- ✅ **Minimal permissions** — only `storage` and `activeTab`

## How to Customize

### Add more sites

Edit `manifest.json` and add URLs to the `content_scripts.matches` array:

```json
"*://your-chat-app.com/*"
```

Then add CSS selectors in `blur.css` for that site's message elements.

### Change the keyboard shortcut

Edit `content.js` and find the `keydown` listener. Change `e.key.toLowerCase() === "x"` to your preferred key.

## Technical Details

- **Manifest V3** Chrome extension
- Pure CSS blur via `filter: blur()` — no DOM manipulation of messages
- `MutationObserver` for dynamically loaded content in SPAs
- Per-site state saved in `chrome.storage.local`
- No background service worker needed

## License

MIT License — use it, modify it, share it freely.
