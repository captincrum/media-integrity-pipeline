/* ------------------------[           DOM references           ]------------------------ */

const logPane         = document.getElementById("logPane");
const splitter        = document.getElementById("splitter");
const humanLogBtn     = document.getElementById("humanLogBtn");
const machineLogBtn   = document.getElementById("machineLogBtn");
const logViewer       = document.getElementById("logViewer");
const resumeScrollBtn = document.getElementById("resumeScrollBtn");

/* ------------------------[          UI state tracking         ]------------------------ */

let logAutoScroll      = true;
let logOpen            = false;
let isResizing         = false;
let startX             = 0;
let startWidth         = 0;

let activeLogMode      = "live";

let lastRepairStatus   = null;
let lastRepairUpdateAt = null;
let currentPhase       = "none"; // "none" | "phase1" | "phase2" | "phase3"

/* ------------------------[        Core UI state helpers       ]------------------------ */

function setUIRunningState(isRunning) {
    const rootInput      = document.getElementById("rootPath");
    const repairedInput  = document.getElementById("repairedPath");
    const browseRoot     = document.getElementById("browseRoot");
    const browseRepaired = document.getElementById("browseRepaired");
    const scanAll        = document.getElementById("scanAllEpisodes");
    const modeRadios     = document.querySelectorAll("input[name='mode']");
    const clearLogsBtn   = document.getElementById("clearLogsBtn");
    const startBtn       = document.getElementById("startBtn");

    if (isRunning) {
        rootInput.disabled      = true;
        repairedInput.disabled  = true;
        browseRoot.disabled     = true;
        browseRepaired.disabled = true;
        scanAll.disabled        = true;
        clearLogsBtn.disabled   = true;
        startBtn.disabled       = true;
        modeRadios.forEach(r => (r.disabled = true));

        rootInput.classList.add("disabled-ui");
        repairedInput.classList.add("disabled-ui");
        browseRoot.classList.add("disabled-ui");
        browseRepaired.classList.add("disabled-ui");
        scanAll.classList.add("disabled-ui");
        clearLogsBtn.classList.add("disabled-ui");
        startBtn.classList.add("disabled-ui");
        modeRadios.forEach(r => r.classList.add("disabled-ui"));
    } else {
        rootInput.disabled      = false;
        repairedInput.disabled  = false;
        browseRoot.disabled     = false;
        browseRepaired.disabled = false;
        scanAll.disabled        = false;
        clearLogsBtn.disabled   = false;
        startBtn.disabled       = false;
        modeRadios.forEach(r => (r.disabled = false));

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

/* ------------------------[         Mode-based UI rules        ]------------------------ */

function applyModeRules() {
    const rootInput      = document.getElementById("rootPath");
    const browseRoot     = document.getElementById("browseRoot");
    const repairedInput  = document.getElementById("repairedPath");
    const browseRepaired = document.getElementById("browseRepaired");
    const scanAll        = document.getElementById("scanAllEpisodes");

    const selectedMode = document.querySelector("input[name='mode']:checked")?.value;

    const isRunning = document.getElementById("startBtn").disabled;
    if (isRunning) return;

    const isScanOnly   = selectedMode === "ScanOnly";
    const isRepairOnly = selectedMode === "RepairOnly";

    repairedInput.disabled  = isScanOnly;
    browseRepaired.disabled = isScanOnly;

    repairedInput.classList.toggle("disabled-ui", isScanOnly);
    browseRepaired.classList.toggle("disabled-ui", isScanOnly);

    rootInput.disabled  = isRepairOnly;
    browseRoot.disabled = isRepairOnly;
    scanAll.disabled    = isRepairOnly;

    rootInput.classList.toggle("disabled-ui", isRepairOnly);
    browseRoot.classList.toggle("disabled-ui", isRepairOnly);
    scanAll.classList.toggle("disabled-ui", isRepairOnly);

    if (!isScanOnly && !isRepairOnly) {
        rootInput.disabled      = false;
        browseRoot.disabled     = false;
        repairedInput.disabled  = false;
        browseRepaired.disabled = false;
        scanAll.disabled        = false;

        rootInput.classList.remove("disabled-ui");
        browseRoot.classList.remove("disabled-ui");
        repairedInput.classList.remove("disabled-ui");
        browseRepaired.classList.remove("disabled-ui");
        scanAll.classList.remove("disabled-ui");
    }
}

/* ------------------------[        Time formatting helpers     ]------------------------ */

function parseHmsToSeconds(hms) {
    if (!hms) return 0;
    const parts = hms.split(":").map(p => parseInt(p, 10));
    if (parts.length !== 3 || parts.some(isNaN)) return 0;
    return parts[0] * 3600 + parts[1] * 60 + parts[2];
}

function formatSecondsToHms(totalSeconds) {
    if (totalSeconds < 0) totalSeconds = 0;
    const h = Math.floor(totalSeconds / 3600);
    const m = Math.floor((totalSeconds % 3600) / 60);
    const s = totalSeconds % 60;
    return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

/* ------------------------[          Log rendering helpers     ]------------------------ */

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

/* ------------------------[        Phase 3 console rendering   ]------------------------ */

function renderRepairConsole() {
    if (!lastRepairStatus) return;

    const consoleEl = document.getElementById("consoleOutput");
    const s         = lastRepairStatus;

    const now      = Date.now();
    const deltaSec = lastRepairUpdateAt ? Math.floor((now - lastRepairUpdateAt) / 1000) : 0;

    const attemptBase = parseHmsToSeconds(s.AttemptTime);
    const fileBase    = parseHmsToSeconds(s.FileTime);
    const elapsedBase = parseHmsToSeconds(s.Elapsed);

    const attemptTime = formatSecondsToHms(attemptBase + deltaSec);
    const fileTime    = formatSecondsToHms(fileBase + deltaSec);
    const elapsedTime = formatSecondsToHms(elapsedBase + deltaSec);

    let block = "";
    block += "Phase 3          : Repairing & Logging\n";
    block += `Mode             : ${s.Mode}\n`;
    block += `Repairing        : ${s.SourcePath}\n`;
    block += `Repair Attempt   : ${s.AttemptCount + 1}\n`;
    block += `Attempt Time     : ${attemptTime}\n`;
    block += "----------------------------------------\n";
    block += `Repairing File   : ${s.ItemIndex} / ${s.TotalItems}\n`;
    block += `File Time        : ${fileTime}\n`;
    block += "----------------------------------------\n";
    block += `Repair Type      : ${s.StageFriendly} (CRF ${s.CRF})\n`;
    block += `Elapsed Time     : ${elapsedTime}\n`;
    consoleEl.textContent = block;
}

/* ------------------------[          Live console routing      ]------------------------ */

function renderStatusBlock(data) {
    const consoleEl = document.getElementById("consoleOutput");
    if (!data || !data.status) return;

    const s = data.status;
    let block = "";

    if (currentPhase === "none" && s.Type === "Console") {
        currentPhase = "phase1";
    }

    if (s.Type === "ScanProgress") {
        currentPhase = "phase2";
    }

    if (s.Type === "RepairProgress") {
        currentPhase = "phase3";
    }

    if (currentPhase === "phase1") {
        consoleEl.textContent = s.Message;
        return;
    }

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

    if (s.Type === "RepairProgress") {
        currentPhase = "phase3";

        const isNew =
            !lastRepairStatus ||
            lastRepairStatus.AttemptCount !== s.AttemptCount ||
            lastRepairStatus.StageFriendly !== s.StageFriendly ||
            lastRepairStatus.Elapsed !== s.Elapsed;

        if (isNew) {
            lastRepairStatus   = s;
            lastRepairUpdateAt = Date.now();
        }

        renderRepairConsole();
        return;
    }

    if (s.Type === "Console") {
        consoleEl.textContent = s.Message + "\n";
    }
}

/* ------------------------[              API helpers           ]------------------------ */

async function apiStart(root, repaired, mode, scanAll) {
    const url = `/start?root=${encodeURIComponent(root)}&repaired=${encodeURIComponent(
        repaired
    )}&mode=${encodeURIComponent(mode)}&scanAll=${scanAll}`;
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
    const modal  = document.getElementById("confirmModal");
    const yesBtn = document.getElementById("confirmYes");
    const noBtn  = document.getElementById("confirmNo");

    modal.classList.remove("hidden");

    return new Promise(resolve => {
        yesBtn.onclick = async () => {
            modal.classList.add("hidden");

            const res  = await fetch("/logs/clear");
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
    const res  = await fetch("/config");
    const data = await res.json();

    if (!data.ok) return;

    const cfg = data.config;

    document.getElementById("rootPath").value          = cfg.RootPath || "";
    document.getElementById("repairedPath").value      = cfg.RepairedPath || "";
    document.getElementById("scanAllEpisodes").checked = cfg.ScanAllEpisodes;

    const modeRadio = document.querySelector(`input[name="mode"][value="${cfg.Mode}"]`);
    if (modeRadio) modeRadio.checked = true;
}

/* ------------------------[          Log pane controls         ]------------------------ */

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

/* ------------------------[        Event wiring: lifecycle     ]------------------------ */

window.addEventListener("DOMContentLoaded", loadConfig);

document.querySelectorAll("input[name='mode']").forEach(radio => {
    radio.addEventListener("change", applyModeRules);
});

applyModeRules();

/* ------------------------[      Event wiring: log autoscroll  ]------------------------ */

logViewer.addEventListener("scroll", () => {
    const atBottom =
        logViewer.scrollTop + logViewer.clientHeight >= logViewer.scrollHeight - 5;

    logAutoScroll = atBottom;

    if (!atBottom) {
        resumeScrollBtn.classList.remove("hidden");
    } else {
        resumeScrollBtn.classList.add("hidden");
    }
});

resumeScrollBtn.addEventListener("click", () => {
    logAutoScroll = true;
    logViewer.scrollTop = logViewer.scrollHeight;
    resumeScrollBtn.classList.add("hidden");
});

/* ------------------------[      Event wiring: log buttons     ]------------------------ */

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

/* ------------------------[      Event wiring: splitter drag   ]------------------------ */

splitter.addEventListener("mousedown", e => {
    if (!logOpen) return;

    isResizing = true;
    startX     = e.clientX;
    startWidth = logPane.getBoundingClientRect().width;

    document.body.style.cursor = "col-resize";
    document.body.classList.add("no-select");
});

window.addEventListener("mousemove", e => {
    if (!isResizing) return;

    const dx       = e.clientX - startX;
    let newWidth   = startWidth + dx;
    const shell    = document.querySelector(".shell");
    const shellWidth = shell.getBoundingClientRect().width;
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

/* ------------------------[      Event wiring: main buttons    ]------------------------ */

document.getElementById("startBtn").addEventListener("click", async () => {
    const startBtn = document.getElementById("startBtn");
    startBtn.classList.add("running"); // turn Start button active color

    const root     = document.getElementById("rootPath").value.trim();
    const repaired = document.getElementById("repairedPath").value.trim();
    const mode     = document.querySelector("input[name='mode']:checked").value;
    const scanAll  = document.getElementById("scanAllEpisodes").checked;

    const result = await apiStart(root, repaired, mode, scanAll);
    console.log("Start:", result);
});

document.getElementById("cancelBtn").addEventListener("click", async () => {
    const startBtn = document.getElementById("startBtn");
    startBtn.classList.remove("running"); // restore default Start button color

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

/* ------------------------[          Polling: status badge     ]------------------------ */

setInterval(async () => {
    const status = await apiStatus();
    const badge  = document.getElementById("statusBadge");

    badge.textContent =
        status.status.charAt(0).toUpperCase() + status.status.slice(1);

    setUIRunningState(status.status === "running");
    applyModeRules();

    if (status.status === "running") {
        badge.classList.remove("idle");
        badge.classList.add("running");
    } else {
        badge.classList.remove("running");
        badge.classList.add("idle");

        const startBtn = document.getElementById("startBtn");
        startBtn.classList.remove("running");

        currentPhase       = "none";
        lastRepairStatus   = null;
        lastRepairUpdateAt = null;
    }
}, 1000);

/* ------------------------[          Polling: live console     ]------------------------ */

setInterval(async () => {
    const data = await apiStatusConsole();
    renderStatusBlock(data);
}, 250);

/* ------------------------[          Polling: live logs        ]------------------------ */

setInterval(async () => {
    if (!logOpen) return;

    if (activeLogMode === "human") {
        const data = await apiLoadHumanLog();
        renderLogFile(data.entries);
    }

    if (activeLogMode === "machine") {
        const data = await apiLoadMachineLog();
        renderLogFile(data.entries);
    }
}, 250);
