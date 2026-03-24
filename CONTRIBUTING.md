# Contributing to Media Integrity Pipeline
Thank you for your interest in contributing to Media Integrity Pipeline. This project is designed to be modular, maintainable, and predictable. To keep the codebase clean and consistent, please follow the guidelines below.

## How to Contribute
### 1. Reporting Issues
If you find a bug or have a feature request, please open an issue and include:
- A clear description of the problem
- Steps to reproduce (if applicable)
- Relevant log output (redact personal paths if needed)
- Your environment (Windows version, PowerShell version)

## Code Contributions
### 2. Fork and Branch
Please do not commit directly to main. Use the following workflow:
1. Fork the repository
2. Create a new branch from main:
   git checkout -b feature/your-feature-name
3. Make your changes
4. Submit a pull request

Branch names should be descriptive and use the format:
- feature/... for new features
- fix/... for bug fixes
- refactor/... for structural improvements
- docs/... for documentation updates

## Coding Standards
### 3. PowerShell Style
Please follow these conventions:
- Use clear, descriptive function names
- Keep modules focused on a single responsibility
- Avoid hard-coded paths
- Use the existing logging module for all output
- Maintain consistent indentation and formatting
- Prefer pipeline-safe, restart-safe logic when possible

If you modify or add a module, ensure it aligns with the existing structure:
Modules/
  UnifiedMedia.Common.psm1
  UnifiedMedia.Config.psm1
  UnifiedMedia.Logging.psm1
  UnifiedMedia.Scan.psm1
  UnifiedMedia.Repair.psm1
  UnifiedMedia.Quality.psm1

## Commit Messages
### 4. Commit Message Format
Use clear, concise commit messages. Recommended format:
<type>: <short description>
Optional longer explanation.

Types include:
- add: new features
- fix: bug fixes
- update: improvements
- refactor: structural changes
- docs: documentation updates

Examples:
fix: correct quality threshold comparison logic
add: parallel scanning prototype
refactor: unify logging across modules

## Pull Requests
### 5. Pull Request Requirements
Before submitting a PR:
- Ensure your branch is up to date with main
- Test your changes with a real library or sample files
- Confirm logs are generated correctly
- Ensure the GUI (if affected) loads without errors
- Include a summary of what the PR changes and why

## Configuration and Defaults
### 6. Config Files
The default config.json is intentionally included in the repo. Do not commit machine-specific or user-specific config files.

If you need local overrides, create your own file such as:
config.local.json
and do not commit it.

## Logging
### 7. Logging Expectations
All modules should use the unified logging system. Do not write raw output directly to the console unless necessary.

Logs should remain:
- Ordered
- Timestamped
- Human-readable
- Machine-parsable (JSON log)

## Thank You
Your contributions help improve the reliability and capability of this project. Whether you’re fixing a bug, improving documentation, or adding a new feature, your help is appreciated.
