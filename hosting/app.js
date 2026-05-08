const params = new URLSearchParams(window.location.search);
const uid = (params.get("uid") || "").trim();
const token = (params.get("token") || "").trim();
const hasApproval = uid && token;
const endpoint =
  "https://europe-west1-spargo-app.cloudfunctions.net/approveDeviceLogin";

const approval = document.getElementById("approval");
const approvalState = document.getElementById("approval-state");
const approvalTitle = document.getElementById("approval-title");
const approvalMessage = document.getElementById("approval-message");
const approvalRetry = document.getElementById("approval-retry");
const approvalReload = document.getElementById("approval-reload");

function showApproval() {
  approval.classList.add("is-visible");
}

function setApprovalLoading() {
  approvalState.innerHTML =
    '<span class="spinner"></span><span id="approval-state-text">Freigabe laeuft</span>';
  approvalTitle.textContent = "Neues Geraet wird bestaetigt.";
  approvalMessage.textContent =
    "Bitte einen kurzen Moment warten. Danach kannst du dich in sparGO auf deinem neuen Geraet erneut anmelden.";
  approvalRetry.hidden = true;
  approvalReload.hidden = true;
}

function setApprovalResult(ok, text) {
  approvalState.innerHTML =
    '<span style="width:10px;height:10px;border-radius:999px;background:currentColor;display:inline-block"></span>' +
    '<span id="approval-state-text">' +
    (ok ? "Freigeschaltet" : "Fehlgeschlagen") +
    "</span>";
  approvalState.style.background = ok
    ? "rgba(219, 33, 73, 0.08)"
    : "rgba(91, 32, 47, 0.08)";
  approvalState.style.color = ok ? "var(--brand)" : "#7a3044";
  approvalTitle.textContent = ok
    ? "Dein neues Geraet ist jetzt freigeschaltet."
    : "Die Freigabe konnte nicht abgeschlossen werden.";
  approvalMessage.textContent = text;
  approvalRetry.hidden = ok;
  approvalReload.hidden = false;
}

async function runApproval() {
  if (!hasApproval) {
    return;
  }

  showApproval();
  setApprovalLoading();

  try {
    const response = await fetch(
      `${endpoint}?uid=${encodeURIComponent(uid)}&token=${encodeURIComponent(token)}&format=json`,
      {
        method: "GET",
        headers: {
          Accept: "application/json",
        },
      }
    );

    const data = await response.json().catch(() => ({}));
    const text =
      typeof data.message === "string" && data.message.trim()
        ? data.message.trim()
        : "Die Freigabe konnte gerade nicht bestaetigt werden.";
    setApprovalResult(response.ok, text);
  } catch (_) {
    setApprovalResult(
      false,
      "Die Freigabe konnte gerade nicht bestaetigt werden."
    );
  }
}

approvalRetry.addEventListener("click", runApproval);
approvalReload.addEventListener("click", () => window.location.reload());

if (hasApproval) {
  runApproval();
}
