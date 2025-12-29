# Repository Guidelines

## Project Structure & Module Organization
Launcher sources (`iOS-VCAM-Launcher.ps1`, `.bat`, `.exe`) and build scripts (e.g., `compile-v4.1.ps1`) live at the root. Streaming binaries, nginx console, and static assets stay under `objs/`. Active SRS profiles are in `config/active`; archived variants stay in `config/archived` for reference. iOS tooling and packaged debs sit inside `ios/`, while regression docs and helper automation live under `misc/` (see `misc/test-scripts/` for validation helpers). The Flask authentication stub for the iOS app is `server.py`.

## Build, Test, and Development Commands
`pwsh -ExecutionPolicy Bypass -File .\compile-v4.1.ps1` rebuilds the launcher EXE with the correct ps2exe parameters and icon. Use `./iOS-VCAM-Launcher.bat` (or the generated `.exe`) for manual smoke runs and to surface the RTMP URL shown to end users. Launch the auth stub locally with `python server.py --host 0.0.0.0` when testing mobile pairing flows.

## Coding Style & Naming Conventions
PowerShell scripts follow Verb-Noun naming, 4-space indentation, and comment-based help blocks as demonstrated in `compile-v4.1.ps1`; log status with `Write-Host` using the existing emoji vocabulary for consistency. Python utilities (`server.py`, `ios/*.py`) use `snake_case` identifiers, f-strings for logging, and should remain Black-compatible (88-char lines) with explicit `if __name__ == "__main__":` guards. Configuration files keep lowercase names with underscores and the `srs_iphone_*` prefix to denote profile intent; mirror that pattern when adding new presets.

## Testing Guidelines
Run `pwsh -ExecutionPolicy Bypass -File misc/test-scripts/quick-test.ps1` before opening a PR to ensure the launcher process stays alive. `misc/test-scripts/test-launcher.ps1` performs structural verification of the EXE, configs, and binaries—attach its summary to review threads. For packaging changes, execute `python ios/validate_deb.py ios/modified_debs/<file>.deb` to confirm ar member order and control metadata. Manual RTMP verification (connect an iOS client to `rtmp://<host>:1935/live/srs`) remains the acceptance gate for streaming fixes.

## Commit & Pull Request Guidelines
Follow the imperative, present-tense style seen in `git log` (`Fix Flask server to use port 80`, `Enable de-branded iosvcam_base.deb support`). Reference tickets or incidents in the body, and note any configs or binaries that must be regenerated. Pull requests should summarize affected paths, list the launcher/test commands you executed, and capture screenshots or logs when UI output changes (launcher banner, RTMP hints). Flag any required configuration updates so Ops can refresh `config/active` on distribution builds.

## Security & Configuration Tips
Avoid checking in personal IPs or credentials; use `ios/ios_deb_ip_changer_final.py` to localize `.deb` packages instead. Keep new configs in `config/archived` until the team blesses them, then promote copies into `config/active`. Verify that ports 80, 1935, and 8080 are available before demos to prevent SRS start-up failures.
