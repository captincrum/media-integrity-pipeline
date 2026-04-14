// ===============================================================
// LOG PANE TOGGLING + SPLITTER RESIZE
// ===============================================================

const logPane = document.getElementById("logPane");
const splitter = document.getElementById("splitter");
const humanLogBtn = document.getElementById("humanLogBtn");
const machineLogBtn = document.getElementById("machineLogBtn");
const logViewer = document.getElementById("logViewer");
const resumeScrollBtn = document.getElementById("resumeScrollBtn");

let logAutoScroll = true;
let logOpen = false;
let isResizing = false;
let startX = 0;
let startWidth = 0;

// ===============================================================
// AUTOSCROLL USER TAKEOVER + RESUME BUTTON
// ===============================================================

// Detect when user scrolls up (disable autoscroll)
logViewer.addEventListener("scroll", () => {
    const atBottom =
        logViewer.scrollTop + logViewer.clientHeight >= logViewer.scrollHeight - 5;

    logAutoScroll = atBottom;

    if (!atBottom) {
        // User scrolled up → show resume button
        resumeScrollBtn.classList.remove("hidden");
    } else {
        // User returned to bottom → hide resume button
        resumeScrollBtn.classList.add("hidden");
    }
});

// Resume autoscroll when button is clicked
resumeScrollBtn.addEventListener("click", () => {
    logAutoScroll = true;
    logViewer.scrollTop = logViewer.scrollHeight;
    resumeScrollBtn.classList.add("hidden");
});


function setUIRunningState(isRunning) {
    const rootInput = document.getElementById("rootPath");
    const repairedInput = document.getElementById("repairedPath");
    const browseRoot = document.getElementById("browseRoot");
    const browseRepaired = document.getElementById("browseRepaired");
    const scanAll = document.getElementById("scanAllEpisodes");
    const modeRadios = document.querySelectorAll("input[name='mode']");
    const clearLogsBtn = document.getElementById("clearLogsBtn");
    const startBtn = document.getElementById("startBtn");

    if (isRunning) {
        rootInput.disabled = true;
        repairedInput.disabled = true;
        browseRoot.disabled = true;
        browseRepaired.disabled = true;
        scanAll.disabled = true;
        clearLogsBtn.disabled = true;
        startBtn.disabled = true;
        modeRadios.forEach(r => r.disabled = true);

        rootInput.classList.add("disabled-ui");
        repairedInput.classList.add("disabled-ui");
        browseRoot.classList.add("disabled-ui");
        browseRepaired.classList.add("disabled-ui");
        scanAll.classList.add("disabled-ui");
        clearLogsBtn.classList.add("disabled-ui");
        startBtn.classList.add("disabled-ui");
        modeRadios.forEach(r => r.classList.add("disabled-ui"));
    } else {
        rootInput.disabled = false;
        repairedInput.disabled = false;
        browseRoot.disabled = false;
        browseRepaired.disabled = false;
        scanAll.disabled = false;
        clearLogsBtn.disabled = false;
        startBtn.disabled = false;
        modeRadios.forEach(r => r.disabled = false);

        rootInput.classList.remove("disabled-ui");
        repairedInput.classList.remove("disabled-ui");
        browseRoot.classList.remove("disabled-ui");
        browseRepaired.classList.remove("disabled-ui");
        scanAll.classList.remove("disabled-ui");
        clearLogsBtn.classList.remove("disabled-ui");
        startBtn.classList.remove("disabled-ui");
        modeRadios.forEach(r => r.classList.remove("disabled-ui"));
    }
}

// ===============================================================
// MODE-BASED UI BEHAVIOR (Full / ScanOnly / RepairOnly)
// ===============================================================

// ===============================================================
// MODE-BASED UI BEHAVIOR (Full / ScanOnly / RepairOnly)
// ===============================================================

function applyModeRules() {
    const rootInput = document.getElementById("rootPath");
    const browseRoot = document.getElementById("browseRoot");
    const repairedInput = document.getElementById("repairedPath");
    const browseRepaired = document.getElementById("browseRepaired");
    const scanAll = document.getElementById("scanAllEpisodes");

    const selectedMode = document.querySelector("input[name='mode']:checked")?.value;

    // If running, do NOT override running-state disables
    const isRunning = document.getElementById("startBtn").disabled;
    if (isRunning) return;

    const isScanOnly = selectedMode === "ScanOnly";
    const isRepairOnly = selectedMode === "RepairOnly";

    // -----------------------------
    // Scan Only → disable repaired output
    // -----------------------------
    repairedInput.disabled = isScanOnly;
    browseRepaired.disabled = isScanOnly;

    repairedInput.classList.toggle("disabled-ui", isScanOnly);
    browseRepaired.classList.toggle("disabled-ui", isScanOnly);

    // -----------------------------
    // Repair Only → disable root + scanAll
    // -----------------------------
    rootInput.disabled = isRepairOnly;
    browseRoot.disabled = isRepairOnly;
    scanAll.disabled = isRepairOnly;

    rootInput.classList.toggle("disabled-ui", isRepairOnly);
    browseRoot.classList.toggle("disabled-ui", isRepairOnly);
    scanAll.classList.toggle("disabled-ui", isRepairOnly);

    // -----------------------------
    // Full mode → everything enabled (idle only)
    // -----------------------------
    if (!isScanOnly && !isRepairOnly) {
        rootInput.disabled = false;
        browseRoot.disabled = false;
        repairedInput.disabled = false;
        browseRepaired.disabled = false;
        scanAll.disabled = false;

        rootInput.classList.remove("disabled-ui");
        browseRoot.classList.remove("disabled-ui");
        repairedInput.classList.remove("disabled-ui");
        browseRepaired.classList.remove("disabled-ui");
        scanAll.classList.remove("disabled-ui");
    }
}

let activeLogMode = "live";

function openLogPane() {
    logOpen = true;
    logPane.classList.add("open");
    logPane.style.width = "520px";
}

function closeLogPane() {
    logOpen = false;
    logPane.classList.remove("open");
    logPane.style.width = "0px";
    activeLogMode = "live";
}

function toggleLogPane() {
    if (logOpen) closeLogPane();
    else openLogPane();
}

// HUMAN LOG BUTTON
humanLogBtn.addEventListener("click", async () => {
    const isActivating = !humanLogBtn.classList.contains("active");

    humanLogBtn.classList.toggle("active", isActivating);
    machineLogBtn.classList.remove("active");

    if (isActivating) {
        activeLogMode = "human";
        openLogPane();
        const data = await apiLoadHumanLog();
        renderLogFile(data.entries);
    } else {
        closeLogPane();
    }
});

// MACHINE LOG BUTTON
machineLogBtn.addEventListener("click", async () => {
    const isActivating = !machineLogBtn.classList.contains("active");

    machineLogBtn.classList.toggle("active", isActivating);
    humanLogBtn.classList.remove("active");

    if (isActivating) {
        activeLogMode = "machine";
        openLogPane();
        const data = await apiLoadMachineLog();
        renderLogFile(data.entries);
    } else {
        closeLogPane();
    }
});

// SPLITTER DRAGGING
splitter.addEventListener("mousedown", e => {
    if (!logOpen) return;

    isResizing = true;
    startX = e.clientX;
    startWidth = logPane.getBoundingClientRect().width;

    document.body.style.cursor = "col-resize";
    document.body.classList.add("no-select");
});

window.addEventListener("mousemove", e => {
    if (!isResizing) return;

    const dx = e.clientX - startX;
    let newWidth = startWidth + dx;

    const shellWidth = document.querySelector(".shell").getBoundingClientRect().width;
    const maxWidth = shellWidth * 1.0;

    newWidth = Math.max(260, Math.min(newWidth, maxWidth));
    logPane.style.width = newWidth + "px";
});

window.addEventListener("mouseup", () => {
    if (!isResizing) return;
    isResizing = false;
    document.body.style.cursor = "default";
    document.body.classList.remove("no-select");
});

// ===============================================================
// API HELPERS
// ===============================================================

async function apiStart(root, repaired, mode, scanAll) {
    const url = `/start?root=${encodeURIComponent(root)}&repaired=${encodeURIComponent(repaired)}&mode=${encodeURIComponent(mode)}&scanAll=${scanAll}`;
    const res = await fetch(url);
    return res.json();
}

async function apiCancel() {
    const res = await fetch("/cancel");
    return res.json();
}

async function apiStatus() {
    const res = await fetch("/status");
    return res.json();
}

async function apiBrowseFolder() {
    const res = await fetch("/browse-folder");
    return res.json();
}

async function apiStatusConsole() {
    const res = await fetch("/status-console");
    return res.json();
}

async function apiLoadHumanLog() {
    const res = await fetch("/logs/human");
    return res.json();
}

async function apiLoadMachineLog() {
    const res = await fetch("/logs/machine");
    return res.json();
}

async function clearLogs() {
    const modal = document.getElementById("confirmModal");
    const yesBtn = document.getElementById("confirmYes");
    const noBtn = document.getElementById("confirmNo");

    modal.classList.remove("hidden");

    return new Promise(resolve => {
        yesBtn.onclick = async () => {
            modal.classList.add("hidden");

            const res = await fetch("/logs/clear");
            const data = await res.json();

            if (data.ok) {
                renderLogFile([]);
            } else {
                alert("Failed to clear logs: " + data.error);
            }

            resolve(true);
        };

        noBtn.onclick = () => {
            modal.classList.add("hidden");
            resolve(false);
        };
    });
}

async function loadConfig() {
    const res = await fetch("/config");
    const data = await res.json();

    if (!data.ok) return;

    const cfg = data.config;

    document.getElementById("rootPath").value = cfg.RootPath || "";
    document.getElementById("repairedPath").value = cfg.RepairedPath || "";
    document.getElementById("scanAllEpisodes").checked = cfg.ScanAllEpisodes;

    const modeRadio = document.querySelector(`input[name="mode"][value="${cfg.Mode}"]`);
    if (modeRadio) modeRadio.checked = true;
}

window.addEventListener("DOMContentLoaded", loadConfig);

// Apply mode rules when user changes mode
document.querySelectorAll("input[name='mode']").forEach(radio => {
    radio.addEventListener("change", applyModeRules);
});

// Apply mode rules on page load
applyModeRules();

// ===============================================================
// BUTTON WIRING
// ===============================================================

document.getElementById("startBtn").addEventListener("click", async () => {
    const startBtn = document.getElementById("startBtn");
    startBtn.classList.add("running");   // turn Start button active color

    const root = document.getElementById("rootPath").value.trim();
    const repaired = document.getElementById("repairedPath").value.trim();
    const mode = document.querySelector("input[name='mode']:checked").value;
    const scanAll = document.getElementById("scanAllEpisodes").checked;

    const result = await apiStart(root, repaired, mode, scanAll);
    console.log("Start:", result);
});

document.getElementById("cancelBtn").addEventListener("click", async () => {
    const startBtn = document.getElementById("startBtn");
    startBtn.classList.remove("running");   // restore default Start button color

    const result = await apiCancel();
    console.log("Cancel:", result);
});

document.getElementById("browseRoot").addEventListener("click", async () => {
    const result = await apiBrowseFolder();
    if (result.ok) {
        document.getElementById("rootPath").value = result.path;
    }
});

document.getElementById("browseRepaired").addEventListener("click", async () => {
    const result = await apiBrowseFolder();
    if (result.ok) {
        document.getElementById("repairedPath").value = result.path;
    }
});

document.getElementById("clearLogsBtn").addEventListener("click", clearLogs);

// ===============================================================
// STATUS BADGE POLLING (1s)
// ===============================================================

setInterval(async () => {
    const status = await apiStatus();
    const badge = document.getElementById("statusBadge");

    badge.textContent = status.status.charAt(0).toUpperCase() + status.status.slice(1);
	
	setUIRunningState(status.status === "running");
	applyModeRules();

	if (status.status === "running") {
		badge.classList.remove("idle");
		badge.classList.add("running");
	} else {
		badge.classList.remove("running");
		badge.classList.add("idle");

		// Reset Start button when scan completes
		const startBtn = document.getElementById("startBtn");
		startBtn.classList.remove("running");
	}

}, 1000);

// ===============================================================
// LIVE CONSOLE RENDERING
// ===============================================================

let currentPhase = "none"; 
// "none" | "phase1" | "phase2" | "phase3"

function renderStatusBlock(data) {
    const consoleEl = document.getElementById("consoleOutput");
    if (!data || !data.status) return;

    const s = data.status;
    let block = "";

    // -------------------------
    // Detect phase transitions
    // -------------------------

    // Phase 1: any Console output before ScanProgress
    if (currentPhase === "none" && s.Type === "Console") {
        currentPhase = "phase1";
    }

    // Phase 2 begins
    if (s.Type === "ScanProgress") {
        currentPhase = "phase2";
    }

    // Phase 3 begins
    if (s.Type === "RepairProgress") {
        currentPhase = "phase3";
    }

    // -------------------------
    // Render based on phase
    // -------------------------

    // PHASE 1
    if (currentPhase === "phase1") {
        consoleEl.textContent = s.Message;
        return;
    }

    // PHASE 2
    if (currentPhase === "phase2" && s.Type === "ScanProgress") {
        block += "Phase 2       : Scanning & Logging\n";
		block += `Mode          : ${s.Mode}\n`;
        block += `Scanning File : ${s.File}\n`;
        block += `Elapsed Time  : ${s.Elapsed}\n`;
        block += `Scanned       : ${s.Scanned}/${s.Total}\n`;
        block += `Completion    : ${Math.round((s.Scanned / s.Total) * 100)}%\n`;
        consoleEl.textContent = block;
        return;
    }

    // PHASE 3
    if (currentPhase === "phase3" && s.Type === "RepairProgress") {
        block += "Phase 3          : Repairing & Logging\n";
		block += `Mode             : ${s.Mode}\n`;
        block += `Repairing        : ${s.SourcePath}\n`;
        block += `Repair Attempt   : ${s.AttemptCount}\n`;
		block += `Attempt Time     : ${s.Elapsed}\n`;
        block += "----------------------------------------\n";
        block += `Repairing File   : ${s.ItemIndex} / ${s.TotalItems}\n`;
		block += `File Time        : ${s.Elapsed}\n`;
        block += "----------------------------------------\n";
        block += `Repair Type      : ${s.StageFriendly} (CRF ${s.CRF})\n`;
		block += `Elapsed Time     : ${s.Elapsed}\n`;
        consoleEl.textContent = block;
        return;
    }

    // Fallback for generic console messages
    if (s.Type === "Console") {
        consoleEl.textContent = s.Message + "\n";
    }
}

// ===============================================================
// LOG FILE RENDERING
// ===============================================================

function renderLogFile(entries) {
    if (!entries || !Array.isArray(entries) || entries.length === 0) {
        logViewer.textContent = "No logs found";
        return;
    }

    const keyOrder = [
        "Type",
        "Path",
        "Library",
        "Errors",
        "RepairStatus",
        "StageFriendly",
        "CRF",
        "OriginalSizeMB",
        "RepairedSizeMB",
        "SizeRatio",
        "ErrorsAfter",
        "OutputPath",
        "Timestamp"
    ];

    function formatEntry(obj) {
        const cleaned = {};
        for (const key of Object.keys(obj)) {
            if (key === "AddedAt") continue;
            cleaned[key] = obj[key];
        }

        const sortedKeys = Object.keys(cleaned).sort((a, b) => {
            const ai = keyOrder.indexOf(a);
            const bi = keyOrder.indexOf(b);
            if (ai === -1 && bi === -1) return a.localeCompare(b);
            if (ai === -1) return 1;
            if (bi === -1) return -1;
            return ai - bi;
        });

        const longestKey = sortedKeys.reduce((max, k) => Math.max(max, k.length), 0);

        const lines = [];
        lines.push("{");

        for (const key of sortedKeys) {
            const value = cleaned[key];

            let formattedValue;
            if (Array.isArray(value)) {
                formattedValue = `[ ${value.map(v => JSON.stringify(v)).join(", ")} ]`;
            } else {
                formattedValue = JSON.stringify(value);
            }

            const paddedKey = `"${key}"`.padEnd(longestKey + 2, " ");
            lines.push(`    ${paddedKey} : ${formattedValue}`);
        }

        lines.push("}");
        return lines.join("\n");
    }

    // MACHINE LOG
    if (activeLogMode === "machine") {
        let text = "";
        for (const e of entries) {
            text += JSON.stringify(e) + "\n\n";
        }
        logViewer.textContent = text;

        if (logAutoScroll) {
            logViewer.scrollTop = logViewer.scrollHeight;
        }
        return;
    }

    // HUMAN LOG
    if (activeLogMode === "human") {
        let text = "";
        for (const e of entries) {
            text += formatEntry(e) + "\n\n";
        }
        logViewer.textContent = text;

        if (logAutoScroll) {
            logViewer.scrollTop = logViewer.scrollHeight;
        }
    }
}

// ===============================================================
// LIVE POLLING (250ms)
// ===============================================================

setInterval(async () => {
    const data = await apiStatusConsole();
    renderStatusBlock(data);
}, 250);

// ===============================================================
// LIVE LOG POLLING (250ms)
// ===============================================================

setInterval(async () => {
    if (!logOpen) return; // log pane closed → do nothing

    if (activeLogMode === "human") {
        const data = await apiLoadHumanLog();
        renderLogFile(data.entries);
    }

    if (activeLogMode === "machine") {
        const data = await apiLoadMachineLog();
        renderLogFile(data.entries);
    }
}, 250);
