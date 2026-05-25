/* ------------------------[           DOM references           ]------------------------ */

const logPane         	= document.getElementById("logPane");
const splitter        	= document.getElementById("splitter");
const humanLogBtn     	= document.getElementById("humanLogBtn");
const machineLogBtn   	= document.getElementById("machineLogBtn");
const logViewer       	= document.getElementById("logViewer");
const resumeScrollBtn 	= document.getElementById("resumeScrollBtn");
const logSpacer  		= document.getElementById("logSpacer");
const logContent 		= document.getElementById("logContent");
const ESTIMATED_LINE_HEIGHT = 18;
const LINES_PER_ENTRY = 8;       
const ENTRY_HEIGHT = ESTIMATED_LINE_HEIGHT * LINES_PER_ENTRY;

/* ------------------------[          UI state tracking         ]------------------------ */

let logAutoScroll      	= true;
let logOpen            	= false;
let isResizing         	= false;
let startX             	= 0;
let startWidth         	= 0;

let activeLogMode      	= "live";
let isScrollFetching 	= false;

let lastRepairStatus   	= null;
let lastRepairUpdateAt 	= null;
let currentPhase       	= "none"; // "none" | "phase1" | "phase2" | "phase3"

let logFilterText = "";

let fullLogLength = 0;
let windowStart = 0;
let windowEnd = 200;

let resumeShouldBeVisible = false;

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
		document.getElementById("workerCount").disabled = true;
		document.getElementById("workerCount").closest(".toggle-row").classList.add("disabled-ui");
		document.getElementById("crfSlider").disabled = true;
        document.getElementById("crfSlider").closest(".toggle-row").classList.add("disabled-ui");
		document.getElementById("accurateMode").disabled = true;
        document.getElementById("scanAllEpisodes").disabled = true;
        document.querySelector("#accurateMode").closest(".toggle-row").classList.add("disabled-ui");
        document.querySelector("#scanAllEpisodes").closest(".toggle-row").classList.add("disabled-ui");		
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
		document.getElementById("workerCount").disabled = false;
		document.getElementById("workerCount").closest(".toggle-row").classList.remove("disabled-ui");
		document.getElementById("crfSlider").disabled = false;
        document.getElementById("crfSlider").closest(".toggle-row").classList.remove("disabled-ui");
		document.getElementById("accurateMode").disabled = false;
        document.getElementById("scanAllEpisodes").disabled = false;
        document.querySelector("#accurateMode").closest(".toggle-row").classList.remove("disabled-ui");
        document.querySelector("#scanAllEpisodes").closest(".toggle-row").classList.remove("disabled-ui");		
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
	const isSmartCompression = selectedMode === "SmartCompression";

	const lockRepaired = isScanOnly || isSmartCompression;

    repairedInput.disabled  = lockRepaired;
    browseRepaired.disabled = lockRepaired;

    repairedInput.classList.toggle("disabled-ui", lockRepaired);
    browseRepaired.classList.toggle("disabled-ui", lockRepaired);

	const scanToggleRow  = document.querySelector("#scanAllEpisodes").closest(".toggle-row");

    rootInput.disabled  = isRepairOnly;
    browseRoot.disabled = isRepairOnly;
    scanAll.disabled    = isRepairOnly;

    rootInput.classList.toggle("disabled-ui", isRepairOnly);
    browseRoot.classList.toggle("disabled-ui", isRepairOnly);
    scanAll.classList.toggle("disabled-ui", isRepairOnly);
    scanToggleRow.classList.toggle("disabled-ui", isRepairOnly);

	if (!isScanOnly && !isRepairOnly) {
        rootInput.disabled      = false;
        browseRoot.disabled     = false;
        repairedInput.disabled  = isSmartCompression;
        browseRepaired.disabled = isSmartCompression;
        scanAll.disabled        = false;

        rootInput.classList.remove("disabled-ui");
        browseRoot.classList.remove("disabled-ui");
        repairedInput.classList.toggle("disabled-ui", isSmartCompression);
        browseRepaired.classList.toggle("disabled-ui", isSmartCompression);
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

let currentEntries = [];

function renderLogFile(entries) {
    if (!entries || !Array.isArray(entries) || entries.length === 0) {
        logContent.textContent = "No logs found";
        return;
    }

    // Cache for re-renders when filter changes
    currentEntries = entries;

	// Apply filter across all fields
    if (logFilterText) {
        entries = entries.filter(e => {
            if (!e) return false;
            return Object.values(e).some(val => {
                if (val === null || val === undefined) return false;
                if (Array.isArray(val)) return val.some(v => String(v).toLowerCase().includes(logFilterText));
                return String(val).toLowerCase().includes(logFilterText);
            });
        });
        if (entries.length === 0) {
            logContent.textContent = "No entries match filter.";
            logSpacer.style.height = "0px";
            logContent.style.top   = "0px";
            return;
        }
        // Reset virtual scroll positioning so entries sit at the top naturally
        logSpacer.style.height = "0px";
        logContent.style.top   = "0px";
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
				const cleaned = value.filter(v => v !== null && typeof v === "object" ? Object.keys(v).length > 0 : v !== null && v !== undefined && v !== "");
				formattedValue = cleaned.length === 0 ? "null" : `[ ${cleaned.map(v => JSON.stringify(v)).join(", ")} ]`;
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
            if (!e || Object.keys(e).length === 0) continue;
            text += JSON.stringify(e) + "\n\n";
        }
        logContent.textContent = text;

        if (logAutoScroll) {
            logViewer.scrollTop = logViewer.scrollHeight;
        }
        return;
    }

    if (activeLogMode === "human") {
        let text = "";

        const globalLongestKey = entries.reduce((max, e) => {
            if (!e || Object.keys(e).length === 0) return max;
            return Object.keys(e).reduce((m, k) => k === "AddedAt" ? m : Math.max(m, k.length), max);
        }, 0);

        for (const e of entries) {
            if (!e || Object.keys(e).length === 0) continue;
            let block = formatEntry(e);

            block = block.replace(/^{\s*|\s*}$/g, "");
            block = block.replace(/\\\\/g, "\\");
            block = block.replace(/"/g, "");

            block = block
                .split("\n")
                .map(line => {
                    const match = line.match(/^\s*(\S+)\s+:\s+(.*)/);
                    if (!match) return line;
                    const key = match[1].padEnd(globalLongestKey, " ");
                    return `    ${key}  :  ${match[2]}`;
                })
                .join("\n");

            text += block.trimEnd() + "\n\n";
        }

        logContent.textContent = text;

        if (logAutoScroll) {
            logViewer.scrollTop = logViewer.scrollHeight;
        }
        return;
    }	
}

/* ------------------------[        Phase 3 console rendering   ]------------------------ */

function getWorkerDesc(n) {
    n = parseInt(n) || 4;
    if (n <= 3) return "Less CPU intensive — slower processing";
    if (n === 4) return "Recommended — balance of speed and CPU resources";
    return "More CPU intensive — faster processing";
}

function getCompressWorkerDesc(n) {
    n = parseInt(n) || 2;
    if (n === 1) return "Less CPU intensive — slower processing";
    if (n === 2) return "Recommended — balance of speed and CPU resources";
    return "More CPU intensive — faster processing";
}

function renderCompressConsole(s) {
    const consoleEl = document.getElementById("consoleOutput");
    const workers   = s.WorkerFolders || [];
    const pct       = s.TotalItems > 0 ? Math.round((s.ItemIndex / s.TotalItems) * 100) : 0;

    let workerLines = "";
		const workerDisplayCount = parseInt(document.getElementById("compressWorkerCount").value) || 2;
		for (let i = 0; i < workerDisplayCount; i++) {
        const w           = workers[i];
        const workerLabel = `Worker ${i + 1}`.padEnd(10, " ");
        if (!w || typeof w === "string") {
            workerLines += `${workerLabel} : ${w || "Waiting..."}\n\n`;
            continue;
        }
        let fileElapsed = "00:00:00";
        if (w.FileStart) {
            const sec = Math.floor((Date.now() - Date.parse(w.FileStart)) / 1000);
            const hh = String(Math.floor(sec / 3600)).padStart(2, "0");
            const mm = String(Math.floor((sec % 3600) / 60)).padStart(2, "0");
            const ss = String(sec % 60).padStart(2, "0");
            fileElapsed = `${hh}:${mm}:${ss}`;
        }
		const curMB = w.CurrentMB  || 0;
        const estMB = w.EstimatedMB || 0;
        const speed = w.SpeedMBs   || 0;

        function fmtSize(mb) {
            if (mb >= 1024) return (mb / 1024).toFixed(2) + "GB";
            return Math.round(mb) + "MB";
        }

        let progressStr;
        if (estMB > 0 && curMB <= estMB) {
            const pct = Math.round((curMB / estMB) * 100);
            progressStr = `~${pct}% (${fmtSize(curMB)} of ~${fmtSize(estMB)})`;
        } else if (estMB > 0 && curMB > estMB) {
            progressStr = `${fmtSize(curMB)} of ~${fmtSize(estMB)}`;
        } else {
            progressStr = `0MB of ~${fmtSize(estMB)}`;
        }
        const speedStr = speed > 0 ? `${speed}MB/s` : "0MB/s";

        workerLines += `${workerLabel} : ${w.Folder || "--"}\n`;
        workerLines += `${"  File".padEnd(10, " ")} : ${w.Episode || "--"}\n`;
        workerLines += `${"  Time".padEnd(10, " ")} : ${fileElapsed}\n`;
        workerLines += `${"  Progress".padEnd(10, " ")} : ${speedStr} · ${progressStr}\n\n`;
    }

    let block = "";
    block += "----------------------------------------\n";
    block += "Phase 3    : Compressing Files\n";
    block += `Mode       : Smart Compression\n`;
    block += `Elapsed    : ${s.Elapsed || "00:00:00"}\n`;
    block += `Compressed : ${s.ItemIndex} / ${s.TotalItems}\n`;
    block += `Completion : ${pct}%\n`;
    block += `CRF        : ${s.CRF}\n`;
    block += "----------------------------------------\n";
    block += workerLines;

    consoleEl.textContent = block;
}

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
	block += "----------------------------------------\n";
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

    if (s.Type === "RepairProgress" || s.Type === "CompressProgress") {
        currentPhase = "phase3";
    }

    if (currentPhase === "phase1") {
        consoleEl.textContent = s.Message;
        return;
    }

	if (currentPhase === "phase2" && s.Type === "ScanProgress") {
		const workers = s.WorkerFolders || [];
		let workerLines = "";
		const workerDisplayCount = parseInt(document.getElementById("workerCount").value) || 4;
		for (let i = 0; i < workerDisplayCount; i++) {
			const w       = workers[i];
			const workerLabel = `Worker ${i + 1}`.padEnd(10, " ");

			if (!w || typeof w === "string") {
				workerLines += `${workerLabel} : ${w || "Waiting..."}\n\n`;
				continue;
			}

			if (!w.Sample && w.File !== undefined) {
				workerLines += `${workerLabel} : ${w.Folder || "--"}\n`;
				workerLines += `${"  File".padEnd(10, " ")} : ${w.File || "--"}\n\n`;
				continue;
			}

			const sample = (w.Sample != null && w.TotalSamples != null) ? `${w.Sample}/${w.TotalSamples}` : "--";
			let sampleElapsed = "00:00:00";
			if (w.SampleStart) {
				const sec = Math.floor((Date.now() - Date.parse(w.SampleStart)) / 1000);
				const hh = String(Math.floor(sec / 3600)).padStart(2, "0");
				const mm = String(Math.floor((sec % 3600) / 60)).padStart(2, "0");
				const ss = String(sec % 60).padStart(2, "0");
				sampleElapsed = `${hh}:${mm}:${ss}`;
			}
			workerLines += `${workerLabel} : ${w.Folder || "--"}\n`;
			workerLines += `${"  File".padEnd(10, " ")} : ${w.Episode || "--"}\n`;
			workerLines += `${"  Sample".padEnd(10, " ")} : ${sample}\n`;
			workerLines += `${"  Time".padEnd(10, " ")} : ${sampleElapsed}\n\n`;
		}

		block += "----------------------------------------\n";
		const phase2Label = s.Mode === "SmartCompression" ? "Probing Compression" : "Scanning & Logging";
		block += `Phase 2    : ${phase2Label}\n`;
		const modeNames = { Full: "Scan & Repair", ScanOnly: "Scan", RepairOnly: "Repair", SmartCompression: "Smart Compression" };
		block += `Mode       : ${modeNames[s.Mode] || s.Mode}\n`;
		block += `Elapsed    : ${s.Elapsed}\n`;
		block += `Scanned    : ${s.Scanned}/${s.Total}\n`;
		block += `Completion : ${Math.round((s.Scanned / s.Total) * 100)}%\n`;
		block += "----------------------------------------\n";
		block += workerLines;
		consoleEl.textContent = block;
		return;
	}

    if (s.Type === "CompressProgress") {
        currentPhase = "phase3";
        renderCompressConsole(s);
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

async function apiStart(root, repaired, mode, scanAll, workers) {
    const url = `/start?root=${encodeURIComponent(root)}&repaired=${encodeURIComponent(
        repaired
    )}&mode=${encodeURIComponent(mode)}&scanAll=${scanAll}&workers=${workers || 4}`;
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
                fullLogLength  = 0;
                windowStart    = 0;
                windowEnd      = 200;
                currentEntries = [];
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

async function apiSaveConfig() {
    const root         = document.getElementById("rootPath").value.trim();
    const repaired     = document.getElementById("repairedPath").value.trim();
    const mode         = document.querySelector("input[name='mode']:checked").value;
    const scanAll      = document.getElementById("scanAllEpisodes").checked;
    const accurateMode = document.getElementById("accurateMode").checked;
    const crfValue     = parseInt(document.getElementById("crfSlider").value);
    const workers = parseInt(document.getElementById("workerCount").value) || 2;
    await fetch(`/config/save?root=${encodeURIComponent(root)}&repaired=${encodeURIComponent(repaired)}&mode=${encodeURIComponent(mode)}&scanAll=${scanAll}&accurateMode=${accurateMode}`);
}

async function loadConfig() {
    const res  = await fetch("/config");
    const data = await res.json();
    if (!data.ok) return;
    const cfg = data.config;

    document.getElementById("rootPath").value          = cfg.RootPath || "";
    document.getElementById("repairedPath").value      = cfg.RepairedPath || "";
    document.getElementById("scanAllEpisodes").checked = cfg.ScanAllEpisodes || false;
    document.getElementById("scanModeDesc").textContent = cfg.ScanAllEpisodes
        ? "Scans every episode - slower but more precise"
        : "Samples the first episode per season - fast results across large libraries";
    document.getElementById("accurateMode").checked    = cfg.AccurateMode || false;
	document.getElementById("crfSlider").value         = 22;
    document.getElementById("crfValue").textContent    = 22;
    document.getElementById("crfDesc").textContent     = "Recommended - ~97.5% quality retained";
    document.getElementById("workerCount").value       = 4;
    document.getElementById("workerValue").textContent = 4;
    document.getElementById("workerDesc").textContent  = getWorkerDesc(4);

    const modeRadio = document.querySelector(`input[name="mode"][value="${cfg.Mode}"]`);
    if (modeRadio) modeRadio.checked = true;

    const isSmartMode = cfg.Mode === "SmartCompression";
    document.getElementById("smartOptions").classList.toggle("hidden", !isSmartMode);
    document.getElementById("compressionOutputPath").value = cfg.CompressionOutputPath || "";

    const desc = document.getElementById("smartMethodDesc");
    desc.textContent = cfg.AccurateMode
        ? "Accuracy of space saved over speed"
        : "Quick results across your entire library";

    updateReviewButton();
}

async function apiLoadLogSlice(start, end) {
    const res = await fetch(`/logs/slice?start=${start}&end=${end}`);
    return res.json();
}

async function updateReviewButton() {
    const btn = document.getElementById("reviewBtn");
    const meta = await apiLoadLogSlice(0, 1);
    if (meta.total === 0) {
        btn.classList.add("disabled-ui");
        return;
    }
    const data = await apiLoadLogSlice(0, meta.total);
    const hasSmartProbe = data.entries.some(e => e && e.Type === "SmartProbe");
    btn.classList.toggle("disabled-ui", !hasSmartProbe);
}

function renderVirtualizedSlice(entries, anchorIndex) {
    if (!entries || entries.length === 0) return;

    renderLogFile(entries);

    const contentHeight = logContent.offsetHeight;
    const totalHeight = Math.ceil((fullLogLength / entries.length) * contentHeight);
    logSpacer.style.height = totalHeight + "px";

    const ratio = fullLogLength > 0 ? anchorIndex / fullLogLength : 0;
    const topOffset = Math.floor(ratio * totalHeight);
    logContent.style.top = topOffset + "px";
}

async function saveCompressionSelections() {
    const tbody = document.getElementById("compressionTreeBody");
    if (!tbody) return;
    const allRows = [...tbody.querySelectorAll("tr")];
    const selections = {};
    allRows.forEach(row => {
        const cb = row.querySelector(".tree-checkbox");
        if (row.dataset.path && cb) {
            selections[row.dataset.path] = cb.checked;
        }
    });

    // Keep window cache in sync
    window._compressionSelections = selections;

    await fetch("/compression/selections/save", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(selections)
    });
}

async function loadCompressionSelections() {
    try {
        const res = await fetch("/compression/selections");
        if (!res.ok) return {};
        return await res.json();
    } catch { return {}; }
}

function showError(message) {
    document.getElementById("errorMessage").textContent = message;
    document.getElementById("errorModal").classList.remove("hidden");
}

document.getElementById("errorOk").addEventListener("click", () => {
    document.getElementById("errorModal").classList.add("hidden");
});

/* ------------------------[          Log pane controls         ]------------------------ */

function openLogPane() {
    logOpen = true;
    logPane.style.width = "0";
    void logPane.offsetWidth;
    logPane.classList.add("open");
    logPane.style.width = "";
	
    if (resumeShouldBeVisible) {
        resumeScrollBtn.classList.remove("hidden");
    }
}

function closeLogPane() {
    logOpen = false;
	resumeShouldBeVisible = !resumeScrollBtn.classList.contains("hidden");
    logPane.classList.remove("open");
    logPane.style.width = "0px";
    activeLogMode = "live";
	resumeScrollBtn.classList.add("hidden");
}

function toggleLogPane() {
    if (logOpen) closeLogPane();
    else openLogPane();
}

/* ------------------------[        Event wiring: lifecycle     ]------------------------ */

window.addEventListener("DOMContentLoaded", loadConfig);

document.querySelectorAll("input[name='mode']").forEach(radio => {
    radio.addEventListener("change", () => {
        const isSmartMode = document.querySelector("input[name='mode']:checked")?.value === "SmartCompression";
        document.getElementById("smartOptions").classList.toggle("hidden", !isSmartMode);
        applyModeRules();
    });
});

applyModeRules();

/* ------------------------[      Event wiring: log autoscroll  ]------------------------ */

let scrollLockTimeout = null;
let scrollLocked = false;

logViewer.addEventListener("scroll", async () => {
    const atBottom =
        logViewer.scrollTop + logViewer.clientHeight >= logViewer.scrollHeight - 5;

    if (atBottom) {
        scrollLocked = false;
        logAutoScroll = true;
        resumeScrollBtn.classList.add("hidden");
        return;
    }

    if (logFilterText) return;

    // User scrolled up - lock the poller out
    logAutoScroll = false;
    scrollLocked = true;
    resumeScrollBtn.classList.remove("hidden");

    // Reset the cooldown every time they scroll
    if (scrollLockTimeout) clearTimeout(scrollLockTimeout);
    scrollLockTimeout = setTimeout(() => {
        scrollLocked = false;
    }, 1500);

    const ratio = logViewer.scrollTop / (logViewer.scrollHeight - logViewer.clientHeight);
    const centerIndex = Math.floor(ratio * fullLogLength);

    windowStart = Math.max(0, centerIndex - 100);
    windowEnd   = Math.min(fullLogLength, windowStart + 200);

    if (isScrollFetching) return;
    isScrollFetching = true;

    const data = await apiLoadLogSlice(windowStart, windowEnd);
    fullLogLength = data.total;
    renderVirtualizedSlice(data.entries, windowStart);

    isScrollFetching = false;
});

resumeScrollBtn.addEventListener("click", async () => {
    logAutoScroll = true;

    windowEnd = fullLogLength;
    windowStart = Math.max(0, fullLogLength - 200);

    const data = await apiLoadLogSlice(windowStart, windowEnd);
    renderVirtualizedSlice(data.entries, windowStart);

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

		// 1. Get the total number of log entries
		const meta = await apiLoadLogSlice(0, 99999999);
		fullLogLength = meta.total;

		// 2. Initialize the window to the last 200 entries
		windowEnd = fullLogLength;
		windowStart = Math.max(0, fullLogLength - 200);

		// 3. Load the initial slice
		const data = await apiLoadLogSlice(windowStart, windowEnd);
		renderVirtualizedSlice(data.entries, windowStart);
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

		const full = await apiLoadLogSlice(0, 1);
		fullLogLength = full.total;
		windowEnd = fullLogLength;
		windowStart = Math.max(0, fullLogLength - 200);

		const data = await apiLoadLogSlice(windowStart, windowEnd);
		renderVirtualizedSlice(data.entries, windowStart);
	} else {
        closeLogPane();
    }
});

document.getElementById("logFilterInput").addEventListener("input", async () => {
    logFilterText = document.getElementById("logFilterInput").value.trim().toLowerCase();

    if (logFilterText) {
        // Fetch the entire log so the filter isn't limited to the current window slice
        const meta = await apiLoadLogSlice(0, 1);
        fullLogLength = meta.total;
        const data = await apiLoadLogSlice(0, fullLogLength);
        currentEntries = data.entries;
        logSpacer.style.height = "0px";
        logContent.style.top   = "0px";
        renderLogFile(currentEntries);
    } else {
        // Restore normal windowed view at the bottom
        logAutoScroll = true;
        scrollLocked  = false;
        const meta = await apiLoadLogSlice(0, 1);
        fullLogLength = meta.total;
        windowEnd   = fullLogLength;
        windowStart = Math.max(0, fullLogLength - 200);
        const data  = await apiLoadLogSlice(windowStart, windowEnd);
        currentEntries = data.entries;
        renderLogFile(currentEntries);
        requestAnimationFrame(() => { logViewer.scrollTop = logViewer.scrollHeight; });
    }
});

document.getElementById("logFilterClear").addEventListener("click", () => {
    document.getElementById("logFilterInput").value = "";
    logFilterText = "";
    logAutoScroll = true;
    scrollLocked  = false;
    renderLogFile(currentEntries);
    requestAnimationFrame(() => { logViewer.scrollTop = logViewer.scrollHeight; });
});

/* ------------------------[      Event wiring: splitter drag   ]------------------------ */

splitter.addEventListener("mousedown", e => {
    if (!logOpen) return;

    isResizing = true;
    startX     = e.clientX;
    startWidth = logPane.getBoundingClientRect().width;

    logPane.classList.add("dragging");

    document.body.style.cursor = "col-resize";
    document.body.classList.add("no-select");
});

window.addEventListener("mousemove", e => {
    if (!isResizing) return;

    const dx = e.clientX - startX;
    let newWidth = startWidth + dx;

    const shell = document.querySelector(".shell");
    const shellRect = shell.getBoundingClientRect();

    const leftPane = document.querySelector(".left-pane");
    const leftRect = leftPane.getBoundingClientRect();

    const splitterWidth = splitter.getBoundingClientRect().width;

    // Dynamically read wrapper padding from CSS
    const wrapper = document.getElementById("logPaneWrapper");
    const style = getComputedStyle(wrapper);
    const padLeft  = parseFloat(style.paddingLeft);
    const padRight = parseFloat(style.paddingRight);
    const totalPadding = padLeft + padRight;

    // True max width
    const available =
        shellRect.width -
        leftRect.width -
        splitterWidth;

    const minWidth = 260;
    const maxWidth = available;

    newWidth = Math.max(minWidth, Math.min(newWidth, maxWidth));

    logPane.style.width = newWidth + "px";
});

window.addEventListener("mouseup", () => {
    if (!isResizing) return;
    isResizing = false;

    logPane.classList.remove("dragging");

    document.body.style.cursor = "default";
    document.body.classList.remove("no-select");
});

/* ------------------------[      Splitter double-click toggle  ]------------------------ */

splitter.addEventListener("dblclick", () => {
    if (!logOpen) return;
    const openWidthCSS = getComputedStyle(logPane).getPropertyValue("--open-width").trim();
    const wrapper = document.getElementById("logPaneWrapper");
    const wrapperWidth = wrapper.getBoundingClientRect().width;
    const minWidth = (parseFloat(openWidthCSS) / 100) * wrapperWidth;
    const paneWidth = logPane.getBoundingClientRect().width;
    const shell = document.querySelector(".shell");
    const shellRect = shell.getBoundingClientRect();
    const leftPane = document.querySelector(".left-pane");
    const leftRect = leftPane.getBoundingClientRect();
    const splitterWidth = splitter.getBoundingClientRect().width;

    const maxWidth =
        shellRect.width -
        leftRect.width -
        splitterWidth;

    if (paneWidth > maxWidth) {
        logPane.style.width = minWidth + "px";
        return;
    }

    if (paneWidth >= maxWidth * 0.98) {
        logPane.style.width = minWidth + "px";
        return;
    }

    logPane.style.width = maxWidth + "px";
});



/* ------------------------[      Event wiring: main buttons    ]------------------------ */

document.getElementById("startBtn").addEventListener("click", async () => {
	await apiSaveConfig();
    compressionModalDismissed = false;
    const startBtn = document.getElementById("startBtn");

    const root     = document.getElementById("rootPath").value.trim();
    const repaired = document.getElementById("repairedPath").value.trim();
    const mode     = document.querySelector("input[name='mode']:checked").value;
    const scanAll  = document.getElementById("scanAllEpisodes").checked;

    // Validate required fields based on mode
    if (mode !== "RepairOnly" && !root) {
        showError("Please select a Library Root before starting.");
        return;
    }

    if (mode !== "ScanOnly" && mode !== "SmartCompression" && !repaired) {
        showError("Please select a Repaired Output folder before starting.");
        return;
    }

    startBtn.classList.add("running");
    const workers = parseInt(document.getElementById("workerCount").value) || 4;
    const result = await apiStart(root, repaired, mode, scanAll, workers);
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
        apiSaveConfig();
    }
});

document.getElementById("browseRepaired").addEventListener("click", async () => {
    const result = await apiBrowseFolder();
    if (result.ok) {
        document.getElementById("repairedPath").value = result.path;
        apiSaveConfig();
    }
});

document.getElementById("rootPath").addEventListener("change", apiSaveConfig);

document.getElementById("repairedPath").addEventListener("change", apiSaveConfig);

document.getElementById("scanAllEpisodes").addEventListener("change", apiSaveConfig);

document.querySelectorAll("input[name='mode']").forEach(r => r.addEventListener("change", apiSaveConfig));

document.getElementById("accurateMode").addEventListener("change", () => {
    const desc     = document.getElementById("smartMethodDesc");
    const accurate = document.getElementById("accurateMode").checked;
    desc.textContent = accurate
		? "Prioritize accuracy in space savings over speed"
        : "Quick results across your entire library";
	apiSaveConfig();
});

document.getElementById("crfSlider").addEventListener("input", function () {
    const val = parseInt(this.value);
    document.getElementById("crfValue").textContent = val;
    const crfDescriptions = {
        18: "Near lossless - ~99.5% quality retained",
        19: "Excellent - ~99.0% quality retained",
        20: "Very high - ~98.5% quality retained",
        21: "High - ~98.0% quality retained",
        22: "Recommended - ~97.5% quality retained",
        23: "Good - ~96.5% quality retained",
        24: "Acceptable - ~95.0% quality retained",
        25: "Noticeable loss - ~93.0% quality retained",
        26: "Visible loss - ~90.0% quality retained",
        27: "Poor - ~86.0% quality retained",
        28: "Low quality - ~80.0% quality retained"
    };
    document.getElementById("crfDesc").textContent = crfDescriptions[val] || "Recommended - ~97.5% quality retained";
    apiSaveConfig();
});

document.getElementById("workerCount").addEventListener("input", function () {
    const val = parseInt(this.value) || 4;
    document.getElementById("workerValue").textContent = val;
    document.getElementById("workerDesc").textContent = getWorkerDesc(val);
    apiSaveConfig();
});

document.getElementById("compressWorkerCount").addEventListener("input", function () {
    const val = parseInt(this.value) || 2;
    document.getElementById("compressWorkerValue").textContent = val;
    document.getElementById("compressWorkerDesc").textContent = getCompressWorkerDesc(val);
});

document.getElementById("scanAllEpisodes").addEventListener("change", function () {
    document.getElementById("scanModeDesc").textContent = this.checked
        ? "Scans every episode - slower but more precise"
        : "Samples the first episode per season - fast results across large libraries";
    apiSaveConfig();
});

document.getElementById("clearLogsBtn").addEventListener("click", clearLogs);

/* ------------------------[      Compression Results Modal     ]------------------------ */

let compressionTreeData = null;
let compressionModalDismissed = false;

const expandedNodes = new Set();

function formatMB(mb) {
    if (!mb || isNaN(mb)) return "0 MB";
    if (mb >= 1024 * 1024) return (mb / (1024 * 1024)).toFixed(2) + " TB";
    if (mb >= 1024)        return (mb / 1024).toFixed(2) + " GB";
    return mb.toFixed(1) + " MB";
}


function buildTreeData(entries) {
    const root = { name: "All Media", children: {}, origMB: 0, estMB: 0, verdicts: [] };

    for (const e of entries) {
        if (e.Type !== "SmartProbe") continue;

        const parts      = e.Path.replace(/\\/g, "/").split("/");
        const fileName   = parts[parts.length - 1];
        const seasonDir  = parts[parts.length - 2];
        const showDir    = parts[parts.length - 3];

        const isCompress = e.Verdict === "Compress";
        root.origMB += e.OriginalMB || 0;
        root.estMB  += isCompress ? (e.EstimatedMB || e.OriginalMB) : (e.OriginalMB || 0);
        root.verdicts.push(e.Verdict || "Skip");

        if (!root.children[showDir]) {
            root.children[showDir] = { name: showDir, children: {}, origMB: 0, estMB: 0, verdicts: [], isShow: true };
        }
        const show = root.children[showDir];
        show.origMB += e.OriginalMB || 0;
        show.estMB  += isCompress ? (e.EstimatedMB || e.OriginalMB) : (e.OriginalMB || 0);
        show.verdicts.push(e.Verdict || "Skip");

        if (!show.children[seasonDir]) {
            show.children[seasonDir] = { name: seasonDir, children: {}, origMB: 0, estMB: 0, verdicts: [] };
        }
        const season = show.children[seasonDir];
        season.origMB += e.OriginalMB || 0;
        season.estMB  += isCompress ? (e.EstimatedMB || e.OriginalMB) : (e.OriginalMB || 0);
        season.verdicts.push(e.Verdict || "Skip");

        season.children[fileName] = {
            name:       fileName,
            children:   null,
            origMB:     e.OriginalMB || 0,
            estMB:      isCompress ? (e.EstimatedMB || e.OriginalMB) : (e.OriginalMB || 0),
            verdicts:   [e.Verdict || "Skip"],
            verdict:    e.Verdict || "Skip",
            skipReason: e.SkipReason || null,
            confidence: e.Confidence || null,
            savedPct:   e.SavedPct || 0,
            path:       e.Path
        };
    }

    function sortChildren(node) {
        if (!node.children) return;
        const sorted = {};
        Object.keys(node.children)
            .sort((a, b) => a.localeCompare(b, undefined, { numeric: true, sensitivity: "base" }))
            .forEach(key => {
                sorted[key] = node.children[key];
                sortChildren(node.children[key]);
            });
        node.children = sorted;
    }

    sortChildren(root);
    return root;
}

function verdictSummary(verdicts) {
    if (!verdicts || verdicts.length === 0) return { label: "Skip", cls: "verdict-skip" };
    const compressCount = verdicts.filter(v => v === "Compress").length;
    if (compressCount === verdicts.length) return { label: "Compress", cls: "verdict-compress" };
    if (compressCount === 0) return { label: "Ineligible", cls: "verdict-skip" };
    return { label: `${compressCount} / ${verdicts.length}`, cls: "verdict-compress" };
}

function savedClass(pct) {
    if (pct >= 20) return "saved-high";
    if (pct >= 5)  return "saved-mid";
    return "saved-low";
}

function renderTree(node, level, tbody, parentCheckbox) {
    const isLeaf   = node.children === null;
    const children = isLeaf ? [] : Object.values(node.children);

    const tr = document.createElement("tr");
    tr.className = `tree-tr level-${Math.min(level, 3)}`;

    // Dim skipped leaf rows
	if (isLeaf && node.verdict === "Skip") {
		tr.style.opacity = "0.45";
		tr.style.pointerEvents = "none";
	}

    // Name cell
    const tdName = document.createElement("td");
    tdName.className = "tree-td";

    const nameCell = document.createElement("div");
    nameCell.className = "tree-name-cell";

    const indent = document.createElement("span");
    indent.className = "tree-indent";
    indent.style.width = (level * 20) + "px";
    nameCell.appendChild(indent);

    const toggle = document.createElement("span");
    toggle.className = "tree-toggle";
    toggle.textContent = (!isLeaf && children.length > 0) ? "▶" : "";
    nameCell.appendChild(toggle);

    const cb = document.createElement("input");
    cb.type = "checkbox";
    cb.className = "tree-checkbox";
    cb.checked = isLeaf ? node.verdict === "Compress" : true;
    if (isLeaf && node.verdict === "Skip") {
        cb.disabled = true;
        cb.classList.add("checkbox-disabled");
    }
    nameCell.appendChild(cb);

    const name = document.createElement("span");
    name.className = "tree-name" + (isLeaf ? "" : " is-folder");
    name.textContent = node.name;
    name.title = node.name;
    nameCell.appendChild(name);

    tdName.appendChild(nameCell);
    tr.appendChild(tdName);

    // Size cell
    const tdSize = document.createElement("td");
    tdSize.className = "tree-td tree-td-size";
    if (isLeaf && node.verdict === "Skip") {
        tdSize.textContent = `${formatMB(node.origMB)} - Skip`;
    } else {
        const pct = isLeaf ? node.savedPct : (node.origMB > 0 ? ((node.origMB - node.estMB) / node.origMB * 100).toFixed(1) : 0);
        tdSize.innerHTML = `${formatMB(node.origMB)} &rarr; ${formatMB(node.estMB)}`;
        if (pct > 0) {
            const pctSpan = document.createElement("span");
            pctSpan.className = savedClass(parseFloat(pct));
            pctSpan.textContent = ` (${pct}%)`;
            tdSize.appendChild(pctSpan);
        }
    }
    tr.appendChild(tdSize);

    // Verdict cell
    const tdVerdict = document.createElement("td");
    tdVerdict.className = "tree-td tree-td-verdict";
    if (isLeaf) {
        const isCompress = node.verdict === "Compress";
        tdVerdict.className += " " + (isCompress ? "verdict-compress" : "verdict-skip");
        let label = isCompress ? "Compress" : "Skip";
        if (isCompress && node.confidence && node.confidence !== "N/A") {
            label += ` (${node.confidence})`;
        }
		if (!isCompress && node.skipReason) {
			const reasonMap = {
				AlreadyModernCodec:   "HEVC/AV1",
				DurationTooShort:     "Too Short",
				BitrateTooLow:        "Low Bitrate",
				SampleExceedsSource:  "Would Grow",
				SavingsBelowThreshold:"< 10% Saving",
				SampleEncodeFailed:   "Probe Failed"
			};
			label = reasonMap[node.skipReason] || "Ineligible";
		} else if (!isCompress) {
			label = "Ineligible";
		}
        tdVerdict.textContent = label;
    } else {
        const vs = verdictSummary(node.verdicts);
        tdVerdict.className += " " + vs.cls;
        tdVerdict.textContent = vs.label;
    }
    tr.appendChild(tdVerdict);

    if (node.path) tr.dataset.path = node.path;
    tbody.appendChild(tr);

    // Children
    if (!isLeaf && children.length > 0) {
        let expanded = false;

        for (const child of children) {
            renderTree(child, level + 1, tbody, cb);
        }

        const allRows = [...tbody.querySelectorAll("tr")];
        const idx = allRows.indexOf(tr);
        for (let i = idx + 1; i < allRows.length; i++) {
            const rowLevel = parseInt([...allRows[i].classList].find(c => c.startsWith("level-"))?.replace("level-", "") || "99");
            if (rowLevel <= level) break;
            allRows[i].style.display = "none";
        }

        toggle.textContent = "▶";
		const hasCompressible = children.some(function hasAny(c) {
			if (c.children === null) return c.verdict === "Compress";
			return Object.values(c.children).some(hasAny);
		});
		if (!hasCompressible) {
			tr.querySelector(".tree-checkbox").disabled = true;
			tr.querySelector(".tree-checkbox").classList.add("checkbox-disabled");
			tr.querySelector(".tree-checkbox").style.opacity = "0.3";
			name.style.opacity = "0.45";
			tdSize.style.opacity = "0.45";
			tdVerdict.style.opacity = "0.45";
			toggle.style.color = "var(--text)";
		}

        toggle.addEventListener("click", (e) => {
            e.stopPropagation();
            expanded = !expanded;
            toggle.textContent = expanded ? "▼" : "▶";
            const allRows = [...tbody.querySelectorAll("tr")];
            const idx = allRows.indexOf(tr);
            if (expanded) { expandedNodes.add(node.name); } else { expandedNodes.delete(node.name); }
            toggleChildren(tbody, idx, level, expanded);
        });

        tr.addEventListener("click", (e) => {
            if (e.target === cb || e.target === toggle) return;
            expanded = !expanded;
            toggle.textContent = expanded ? "▼" : "▶";
            const allRows = [...tbody.querySelectorAll("tr")];
            const idx = allRows.indexOf(tr);
            if (expanded) { expandedNodes.add(node.name); } else { expandedNodes.delete(node.name); }
            toggleChildren(tbody, idx, level, expanded);
        });

        // Three-state folder checkbox: smart (compress-only) -> none -> smart
        cb._folderState = "smart"; // "smart" | "none"
        cb.addEventListener("click", (e) => {
            e.stopPropagation();
            const allRows = [...tbody.querySelectorAll("tr")];
            const idx = allRows.indexOf(tr);
            if (cb._folderState === "smart") {
                // -> none
                cb._folderState = "none";
                setChildrenCheckedSmart(tbody, idx, level, false);
            } else {
                // -> smart
                cb._folderState = "smart";
                setChildrenCheckedSmart(tbody, idx, level, "smart");
            }
            updateCompressionSummary();
            saveCompressionSelections();
            syncParentCheckboxes(tbody);
        });
    }

    if (parentCheckbox) {
        cb.addEventListener("change", () => {
            updateCompressionSummary();
            saveCompressionSelections();
            syncParentCheckboxes(tbody);
        });
    }
}

function toggleChildren(tbody, parentIdx, parentLevel, show) {
    const allRows = [...tbody.querySelectorAll("tr")];
    for (let i = parentIdx + 1; i < allRows.length; i++) {
        const rowLevel = parseInt([...allRows[i].classList].find(c => c.startsWith("level-"))?.replace("level-", "") || "99");
        if (rowLevel <= parentLevel) break;

        if (rowLevel === parentLevel + 1) {
            allRows[i].style.display = show ? "" : "none";

            if (show && window._compressionSelections && allRows[i].dataset.path) {
                const cb = allRows[i].querySelector(".tree-checkbox");
                if (cb && window._compressionSelections.hasOwnProperty(allRows[i].dataset.path)) {
                    cb.checked = window._compressionSelections[allRows[i].dataset.path];
                }
            }

            // If this child was previously expanded, restore its children visibility
            if (show) {
                const childName = allRows[i].querySelector(".tree-name")?.textContent;
                const childToggle = allRows[i].querySelector(".tree-toggle");
                if (childName && expandedNodes.has(childName) && childToggle) {
                    const childIdx = allRows.indexOf(allRows[i]);
                    toggleChildren(tbody, childIdx, rowLevel, true);
                    childToggle.textContent = "▼";
                }
            }
        } else if (!show) {
            allRows[i].style.display = "none";
        }
    }
    if (show) syncParentCheckboxes(tbody);
}

// Sets children checked state - "smart" mode checks only Compress verdicts, skips disabled
function setChildrenCheckedSmart(tbody, parentIdx, parentLevel, mode) {
    const allRows = [...tbody.querySelectorAll("tr")];
    for (let i = parentIdx + 1; i < allRows.length; i++) {
        const rowLevel = parseInt([...allRows[i].classList].find(c => c.startsWith("level-"))?.replace("level-", "") || "0");
        if (rowLevel <= parentLevel) break;
        const cb = allRows[i].querySelector(".tree-checkbox");
        if (!cb || cb.disabled) continue;
        if (mode === "smart") {
            // Only check leaf rows with Compress verdict; folder rows handled by syncParentCheckboxes
            if (allRows[i].dataset.path) {
                cb.checked = allRows[i].style.opacity !== "0.45";
            }
        } else {
            cb.checked = false;
        }
    }
}

function setChildrenChecked(tbody, parentIdx, parentLevel, checked) {
    const allRows = [...tbody.querySelectorAll("tr")];
    for (let i = parentIdx + 1; i < allRows.length; i++) {
        const rowLevel = [...allRows[i].classList]
            .find(c => c.startsWith("level-"))?.replace("level-", "");
        if (parseInt(rowLevel) <= parentLevel) break;
        const cb = allRows[i].querySelector(".tree-checkbox");
        if (cb) cb.checked = checked;
    }
}

function updateCompressionSummary() {
    const tbody = document.getElementById("compressionTreeBody");
    if (!tbody) return;
    const allRows = [...tbody.querySelectorAll("tr")];

    const leafRowsForSize = allRows.filter(row => {
        const cb = row.querySelector(".tree-checkbox");
        return cb && cb.checked && row.dataset.path;
    });

    let origMB = 0, estMB = 0;
    const folders = new Set();

    for (const row of leafRowsForSize) {
        const sizeText = row.querySelector(".tree-td-size")?.textContent || "";

        const parseMBfromText = t => {
            t = t.trim();
            const n = parseFloat(t);
            if (t.includes("TB")) return n * 1024 * 1024;
            if (t.includes("GB")) return n * 1024;
            return n;
        };

        const parts = sizeText.split("→").map(s => s.trim());
        if (parts.length === 2) {
            origMB += parseMBfromText(parts[0]);
            estMB  += parseMBfromText(parts[1].replace(/\(.*\)/, "").trim());
        } else {
            // Skip row - orig only
            origMB += parseMBfromText(sizeText.replace(/-.*/, "").trim());
            estMB  += parseMBfromText(sizeText.replace(/-.*/, "").trim());
        }

        const idx = allRows.indexOf(row);
        for (let i = idx - 1; i >= 0; i--) {
            const lvl = parseInt([...allRows[i].classList].find(c => c.startsWith("level-"))?.replace("level-", "") || "99");
            if (lvl === 2) {
                folders.add(allRows[i].querySelector(".tree-name")?.textContent);
                break;
            }
        }
    }

    const savedMB  = origMB - estMB;
    const savedPct = origMB > 0 ? ((savedMB / origMB) * 100).toFixed(1) : 0;

    document.getElementById("sumShows").textContent    = folders.size;
    document.getElementById("sumEpisodes").textContent = leafRowsForSize.length;
    document.getElementById("sumBefore").textContent   = formatMB(origMB);
    document.getElementById("sumAfter").textContent    = formatMB(estMB);
    document.getElementById("sumSaved").textContent    = `${formatMB(savedMB)} (${savedPct}%)`;
}

function syncParentCheckboxes(tbody) {
    const allRows = [...tbody.querySelectorAll("tr")];

    for (let i = allRows.length - 1; i >= 0; i--) {
        const row = allRows[i];
        if (row.dataset.path) continue; // skip leaf rows

        const level = parseInt([...row.classList].find(c => c.startsWith("level-"))?.replace("level-", "") || "0");

        // Find ALL descendant leaf rows
        const descLeaves = [];
        for (let j = i + 1; j < allRows.length; j++) {
            const childLevel = parseInt([...allRows[j].classList].find(c => c.startsWith("level-"))?.replace("level-", "") || "0");
            if (childLevel <= level) break;
            if (allRows[j].dataset.path) descLeaves.push(allRows[j]);
        }

        if (descLeaves.length === 0) continue;

        const cb = row.querySelector(".tree-checkbox");
        if (!cb) continue;

        const checkedCount = descLeaves.filter(r => r.querySelector(".tree-checkbox")?.checked).length;
        cb.checked = checkedCount === descLeaves.length;
        cb.indeterminate = checkedCount > 0 && checkedCount < descLeaves.length;
    }
}

function initColumnResize() {
    const th = document.querySelector(".tree-th-name");
    const col = document.getElementById("colName");
    const resizer = document.getElementById("nameResizer");
    if (!th || !resizer) return;

    let startX, startW;

    resizer.addEventListener("mousedown", e => {
        startX = e.clientX;
        startW = th.getBoundingClientRect().width;
        resizer.classList.add("resizing");
        document.body.classList.add("no-select");

        const onMove = e => {
            const wrapper = document.querySelector(".compression-tree-wrapper");
            const maxW = wrapper.getBoundingClientRect().width - 200 - 130 - 40;
            const newW = Math.max(120, Math.min(maxW, startW + (e.clientX - startX)));
            col.style.width = newW + "px";
        };

        const onUp = () => {
            resizer.classList.remove("resizing");
            document.body.classList.remove("no-select");
            window.removeEventListener("mousemove", onMove);
            window.removeEventListener("mouseup", onUp);
        };

        window.addEventListener("mousemove", onMove);
        window.addEventListener("mouseup", onUp);
        e.stopPropagation();
        e.preventDefault();
    });
}

async function showCompressionModal() {
	const modal   = document.getElementById("compressionModal");
    const tree    = document.getElementById("compressionTree");
    const summary = document.getElementById("compressionSummary");

	document.getElementById("compressWorkerCount").value = 2;
	document.getElementById("compressWorkerValue").textContent = 2;
	document.getElementById("compressWorkerDesc").textContent = getCompressWorkerDesc(2);
	
    if (!modal || !tree || !summary) {
        console.error("Compression modal elements not found", { modal, tree, summary });
        return;
    }
    // Fetch SmartProbe entries
    const meta = await apiLoadLogSlice(0, 999999);
    const data = await apiLoadLogSlice(0, meta.total);
    const entries = data.entries.filter(e => e.Type === "SmartProbe");

    if (entries.length === 0) return;

    const root = buildTreeData(entries);
	
	const savedSelections = await loadCompressionSelections();
	
	const tbody = document.getElementById("compressionTreeBody");
	expandedNodes.clear();
    tbody.innerHTML = "";
    renderTree(root, 0, tbody, null);

    // Expand root by default FIRST so rows are visible
    const firstToggle = tbody.querySelector(".tree-toggle");
    if (firstToggle) {
        firstToggle.click();
        const secondToggle = tbody.querySelectorAll(".tree-toggle")[1];
        if (secondToggle) secondToggle.click();
    }

    // Summary HTML (full totals as baseline)
    const folderCount = Object.values(root.children).reduce((total, topLevel) => {
        return total + Object.keys(topLevel.children).length;
    }, 0);
    const fileCount   = entries.filter(e => e.Type === "SmartProbe").length;
    const compressCount = entries.filter(e => e.Type === "SmartProbe" && e.Verdict === "Compress").length;
    const savedMB     = root.origMB - root.estMB;
    const savedPct    = root.origMB > 0 ? ((savedMB / root.origMB) * 100).toFixed(1) : 0;
    summary.innerHTML = `
        <span style="color:var(--text-muted); font-size:11px; text-transform:uppercase; letter-spacing:.05em; margin-bottom:4px; display:block;">Summary</span>
        <div class="summary-grid">
            <span class="summary-label">Number of Folders:</span>
            <span class="summary-value" id="sumShows">${folderCount}</span>
            <span class="summary-label">Number of Files:</span>
            <span class="summary-value" id="sumEpisodes">${fileCount}</span>
            <span class="summary-label">To Compress:</span>
            <span class="summary-value">${compressCount} / ${fileCount}</span>
            <span class="summary-label">Size Before:</span>
            <span class="summary-value" id="sumBefore">${formatMB(root.origMB)}</span>
            <span class="summary-label">Size After:</span>
            <span class="summary-value" id="sumAfter">${formatMB(root.estMB)}</span>
            <span class="summary-label">Total Saved:</span>
            <span class="summary-value summary-saved" id="sumSaved">${formatMB(savedMB)} (${savedPct}%)</span>
        </div>
    `;

	// Store selections globally so toggleChildren can reapply them
    window._compressionSelections = savedSelections;

    if (Object.keys(savedSelections).length > 0) {
        const allRows = [...tbody.querySelectorAll("tr")];
        allRows.forEach(row => {
            const cb = row.querySelector(".tree-checkbox");
            if (!cb || !row.dataset.path) return;
            if (savedSelections.hasOwnProperty(row.dataset.path)) {
                cb.checked = savedSelections[row.dataset.path];
            }
        });
        updateCompressionSummary();
		syncParentCheckboxes(tbody);
    }

	const savedOutput = await fetch("/config").then(r => r.json());
    if (savedOutput.ok && savedOutput.config.CompressionOutputPath) {
        document.getElementById("compressionOutputPath").value = savedOutput.config.CompressionOutputPath;
    }
	
    modal.classList.remove("hidden");
    initColumnResize();
}

document.getElementById("compressionClose").addEventListener("click", () => {
    document.getElementById("compressionModal").classList.add("hidden");
    compressionModalDismissed = true;
});

document.getElementById("compressionBrowse").addEventListener("click", async () => {
    const result = await apiBrowseFolder();
    if (result.ok) {
        document.getElementById("compressionOutputPath").value = result.path;
    }
});

document.getElementById("compressionStart").addEventListener("click", async () => {
    const outputPath = document.getElementById("compressionOutputPath").value.trim();
	if (!outputPath) {
        showError("Please select an Output Location before compressing.");
        return;
    }

    // Collect checked leaf paths from tree
    const tbody = document.getElementById("compressionTreeBody");
    const allRows = [...tbody.querySelectorAll("tr")];
    const selectedPaths = allRows
        .filter(row => {
            const cb = row.querySelector(".tree-checkbox");
            const level = parseInt([...row.classList].find(c => c.startsWith("level-"))?.replace("level-", "") || "0");
            return cb && cb.checked && level === 3;
        })
        .map(row => row.dataset.path)
        .filter(Boolean);

    if (selectedPaths.length === 0) {
        alert("No files selected for compression.");
        return;
    }

    // Check available disk space
    const estMBText = document.getElementById("sumAfter").textContent;
    const parseSize = t => {
        const n = parseFloat(t);
        if (t.includes("TB")) return n * 1024 * 1024;
        if (t.includes("GB")) return n * 1024;
        return n;
    };
    const neededMB = parseSize(estMBText);
    const spaceRes = await fetch(`/disk-space?path=${encodeURIComponent(outputPath)}`);
    const spaceData = await spaceRes.json();
    if (spaceData.ok && spaceData.freeMB < neededMB) {
        showError(`Not enough disk space.\nNeeded: ${formatMB(neededMB)}\nAvailable: ${formatMB(spaceData.freeMB)}`);
        return;
    }

    // Send to server
	const res = await fetch("/compress/start", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
		body: JSON.stringify({
			outputPath,
			paths: selectedPaths,
			crf: parseInt(document.getElementById("crfSlider").value) || 22,
			sourceRoot: document.getElementById("rootPath").value.trim(),
			workers: parseInt(document.getElementById("compressWorkerCount").value) || 2
		})
    });
    const result = await res.json();
    if (!result.ok) {
        showError("Failed to start compression: " + (result.error || "Unknown error"));
        return;
    }

    document.getElementById("compressionModal").classList.add("hidden");
    compressionModalDismissed = true;
});

document.getElementById("reviewBtn").addEventListener("click", () => {
    if (document.getElementById("reviewBtn").classList.contains("disabled-ui")) return;
    compressionModalDismissed = false;
    showCompressionModal();
});

/* ------------------------[          Polling: status badge     ]------------------------ */

setInterval(async () => {
    const status = await apiStatus();
    const badge  = document.getElementById("statusBadge");

    badge.textContent =
        status.status.charAt(0).toUpperCase() + status.status.slice(1);

    setUIRunningState(status.status === "running");
    applyModeRules();

	if (status.status === "completed" &&
            document.querySelector("input[name='mode']:checked")?.value === "SmartCompression" &&
            !compressionModalDismissed &&
            document.getElementById("compressionModal").classList.contains("hidden")) {
            showCompressionModal();
        }
		updateReviewButton();
		
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
    if (isScrollFetching) return;
    if (scrollLocked) return; 
	if (logFilterText) return;

    const selection = window.getSelection();
    if (selection && selection.toString().length > 0) return;

    const shouldAutoScroll = logAutoScroll;

    if (shouldAutoScroll) {
        const meta = await apiLoadLogSlice(0, 1);
        fullLogLength = meta.total;
        windowEnd   = fullLogLength;
        windowStart = Math.max(0, fullLogLength - 200);
    }

	const data = await apiLoadLogSlice(windowStart, windowEnd);
		if (data.total > 0) {
			fullLogLength = data.total;
			renderVirtualizedSlice(data.entries, windowStart);
		} else if (fullLogLength === 0) {
			logContent.textContent = "No logs found";
			logSpacer.style.height = "0px";
			logContent.style.top   = "0px";
		}

    if (shouldAutoScroll) {
        requestAnimationFrame(() => {
            logViewer.scrollTop = logViewer.scrollHeight;
        });
    }

}, 250);