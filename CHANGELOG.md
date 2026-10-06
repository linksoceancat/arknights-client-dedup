# Changelog

All notable changes to this project are documented in this file.
本项目的所有重要变更都记录在此文件。

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] - 2026-10-07

### Added
- Channel switch: "Import channel pack" — a machine that never installed Bilibili can now import an `AK-Channel` pack folder (copied from another machine) and switch servers without downloading the Bilibili client.

## [1.1.1] - 2026-10-07

### Fixed
- Channel switch now prunes empty directories left behind after removing the other channel's files (e.g. empty `BLPlatform64`).
- Bilibili client detection now checks an actual file (`BLPlatform64\PCGamePlatform.exe`) instead of the directory.

## [1.1.0] - 2026-10-07

### Added
- New tool `ArknightsChannelSwitch.ps1` (+ `Start-ChannelSwitch.bat`, single-file builds) to keep one game body and switch between Official/Bilibili login by swapping the channel layer.

## [1.0.4] - 2026-10-07

### Changed
- Friendlier error when only one client (Official or Bilibili) is installed, explaining that dedup needs both.

## [1.0.3] - 2026-10-07

### Added
- `ArknightsDedup-silent.bat`: single-file one-click silent dedup (double-click runs dedup directly, no menu).

### Changed
- `build-standalone.ps1` now also emits the silent build.

## [1.0.2] - 2026-10-07

### Added
- Single-file build `ArknightsDedup-standalone.bat` (self-extracting) — download one file and double-click.
- `build-standalone.ps1` to generate the single-file build.

## [1.0.1] - 2026-10-07

### Added
- English README (`README.en.md`) with a language switch link in the main README.
- Version number displayed in the menu and status screen.
- This CHANGELOG.

### Changed
- Documentation polish.

## [1.0.0] - 2026-10-07

### Added
- Initial release.
- One-click dedup of the Arknights Official and Bilibili PC clients via NTFS hardlinks.
- Auto-detection of client install locations (channel distinguished by `hgsdk.dll` / `BLPlatform64`).
- MD5 byte-for-byte comparison before linking; identical files only.
- Menu: analyze & dedup / status / rollback / re-detect paths.
- CLI actions: `Dedup`, `Status`, `Rollback`.
- Idempotent runs and bracket-safe hardlink creation via `mklink`.
