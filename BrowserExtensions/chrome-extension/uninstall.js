const pw = document.getElementById("pw");
const btn = document.getElementById("btn");
const err = document.getElementById("err");

function auth() {
  if (!pw.value) return;
  btn.textContent = "Verifying...";
  btn.disabled = true;
  chrome.runtime.sendMessage({ action: "ms_verifyPassword", password: pw.value }, resp => {
    if (chrome.runtime.lastError) {
      btn.disabled = false;
      btn.textContent = "Unlock Access";
      err.textContent = "Extension error — try again.";
      err.style.display = "block";
      return;
    }
    btn.disabled = false;
    btn.textContent = "Unlock Access";
    if (resp && resp.ok) {
      const rt = new URLSearchParams(location.search).get("rt");
      const targetUrl = rt || "chrome://extensions/";
      chrome.runtime.sendMessage({ action: "ms_unlockUninstall", targetUrl: targetUrl }, () => window.close());
    } else {
      err.textContent = resp && resp.error === "no_password"
        ? "No password set — open MacShield to configure."
        : "Incorrect password.";
      err.style.display = "block";
      pw.value = "";
      pw.focus();
    }
  });
}

btn.addEventListener("click", auth);
pw.addEventListener("keydown", e => {
  if (e.key === "Enter") auth();
  err.style.display = "none";
});
