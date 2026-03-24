# Media Integrity Pipeline
Automated scanning, repairing, and quality-checking for movie and TV libraries.

Media Integrity Pipeline is a full media-maintenance system that scans movie and TV libraries, detects corruption, repairs damaged files, evaluates quality, and automatically replaces bad sources. It includes a clean GUI, flexible configuration, detailed logs, and modular workflows for scanning, repairing, and validating entire libraries.

---

## Features

### Smart Library Scanning
- Detects corrupted or partially unreadable media files  
- Identifies broken containers, codec issues, and structural problems  
- Restart-safe logic for large libraries  

### Automated Repair Tools
- Attempts repair using multiple strategies  
- Rebuilds containers, fixes metadata, and restores playable structure  
- Logs every action in both human-readable and machine-readable formats  

### Quality Analysis and Replacement Logic
- Evaluates video and audio quality against configurable thresholds  
- Compares repaired files to originals  
- Automatically replaces damaged sources when quality criteria are met  

### GUI and Configuration System
- Clean, modern interface for running scans and repairs  
- Configurable paths, thresholds, and workflow modes  
- No command-line knowledge required  

### Modular Workflows
Run any stage independently or as a full pipeline:
- Scan Only  
- Repair Only  
- Quality Check Only  
- Full Pipeline (Scan → Repair → QC → Replace)

### Detailed Logging
- Human-readable log for quick review  
- Structured JSON log for automation or dashboards  
- Timestamped, ordered, and restart-safe  

---

## How It Works

1. **Scan Phase**  
   The system crawls your library and identifies damaged or questionable files.

2. **Repair Phase**  
   Repair tools attempt to fix issues using container rebuilds, stream extraction, or metadata correction.

3. **Quality Check Phase**  
   The repaired file is analyzed and compared to the original using configurable thresholds.

4. **Replacement Phase**  
   If the repaired file meets or exceeds your quality requirements, it replaces the original automatically.

---

## Installation and Requirements

- Windows (PowerShell-based pipeline)  
- FFmpeg or other repair backends (optional depending on workflow)  
- .NET / WPF for the GUI  

Clone the repository:
git clone https://github.com/yourname/media-integrity-pipeline


---

## Usage

### 1. Configure Settings
Use the GUI or edit the configuration file to set:
- Library paths  
- Quality thresholds  
- Replacement rules  
- Logging preferences  
- Workflow mode  

### 2. Choose a Workflow
From the GUI:
- Scan  
- Repair  
- Quality Check  
- Full Pipeline  

### 3. Review Logs
Check the human-readable log for quick insights or the JSON log for automation and long-term tracking.

---

## Logging

Two log types are generated:

**Readable Log**  
- Designed for human review  
- Shows each step in order  
- Easy to skim  

**Structured JSON Log**  
- Ideal for dashboards, automation, or audits  
- Never overwrites previous entries  
- Suitable for long-term tracking  

---

## Roadmap

- Parallel scanning  
- Plugin system for custom repair modules  
- Cloud-based metadata validation  
- Optional CLI mode  
- Cross-platform support  

---

## Contributing

Contributions, bug reports, and feature requests are welcome.  
Please open an issue or submit a pull request.
