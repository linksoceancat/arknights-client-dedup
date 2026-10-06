# Arknights Official / Bilibili Client Dedup Tool

[中文](README.md) | **English**

A one-click tool that makes the two PC clients of *Arknights* — the **Official** (Hypergryph) client and the **Bilibili** client — share the identical files on disk. No second download, no switching, no impact on normal play, saving roughly half the disk space.

## How it works

Conventionally the Official and Bilibili clients are two separate installs (20+ GB each). However, their **game assets are byte-for-byte identical**; the real difference is a thin "login channel" layer (channel SDK, executables, channel config, etc.).

This tool:

1. Auto-detects both install locations;
2. Compares same-path files between the two clients using MD5;
3. For files whose contents are **exactly identical**, it deletes the Bilibili copy and replaces it with a **NTFS hardlink** pointing to the Official file (content unchanged, transparent to the program);
4. Files whose contents **differ** (`Arknights.exe`, `GameAssembly.dll`, channel SDK, etc.) and Bilibili-only files are kept as independent copies.

Result: both clients stay intact and can be launched normally; actual disk usage drops from `≈53 GB` to `≈27 GB`.

## Requirements

- Windows 10 / 11
- PowerShell 5.1 (bundled with Windows)
- The Official and Bilibili clients on the **same disk partition** (hardlinks require it)
- NTFS file system

## Usage

### Option 1: Single-file build (easiest, recommended)
Download **`ArknightsDedup-standalone.bat`** from [Releases](https://github.com/linksoceancat/arknights-client-dedup/releases/latest) and double-click it.
The whole tool is in that one file; on first run it self-extracts `ArknightsDedup.ps1` next to itself and starts. Then use the menu.

> If Windows shows a SmartScreen/script warning, choose "Run anyway" (the script is unsigned, which is normal).

### Option 2: Full build
1. Clone this repository (or download and extract the zip from Releases).
2. Double-click **`Start.bat`**.
3. Use the menu:
   - `[1] Analyze & dedup`
   - `[2] Status`
   - `[3] Rollback`
   - `[4] Re-detect / set client paths`

Or run from the command line:

```powershell
powershell -ExecutionPolicy Bypass -File .\ArknightsDedup.ps1 -Action Dedup
powershell -ExecutionPolicy Bypass -File .\ArknightsDedup.ps1 -Action Status
powershell -ExecutionPolicy Bypass -File .\ArknightsDedup.ps1 -Action Rollback
```

On first run, if auto-detection fails, it will ask for the two **game root folders** (the folders containing `Arknights.exe`) and save them to `config.json`.

## Layout

```
ArknightsDedup.ps1   Main program (menu + dedup/rollback/status)
Start.bat            One-click launcher
build-standalone.ps1 Packaging: embeds the main program into a single-file .bat (outputs to dist/)
config.json          Client paths (created on first run)
data/
  manifest.csv       Comparison result (whether same-path files are identical)
  rollback.csv       List of files that can be rolled back
  run.log            Run log
```

## After a game update

A major update replaces files; replaced hardlinks **break automatically**, becoming independent copies again and increasing usage (safe). After updating and bringing both clients to the same version, run `[1] Analyze & dedup` again to relink the new identical files.

> Do not run this tool while a client is patching. Close all games and launchers first.

## Rollback

Menu `[3] Rollback` restores all hardlinks as independent Bilibili copies (content unchanged, just no longer shared). It relies on `data/rollback.csv`.

## Notes

- The tool only **reads file contents** for comparison and then creates hardlinks; it never modifies game content.
- Because only identical content is linked, content-based anti-cheat is unaffected.
- Prefer running only one client at a time (with hardlinks, an in-place write to a shared file could theoretically affect the other — extremely unlikely).
- **Players with only one client installed (Official or Bilibili) don't need this tool**: there is no second client to share files with, so there is no duplication to remove. The tool targets the case where both are installed.
- Evaluate the risks and comply with the relevant terms of service yourself.

## Channel switch tool (one client, two servers — high risk)

This repo also ships **`ArknightsChannelSwitch.ps1`**: keep **one game body** and switch between Official / Bilibili login by replacing the login-channel layer (saving the second 26 GB body).

- Entry: `Start-ChannelSwitch.bat` (or `ArknightsChannelSwitch-*.bat` in Releases)
- First run: menu `[1]` builds channel packs (compares the two clients and packs the differing channel files into `E:\AK-Channel\official` and `bilibili`)
- Then: `[2]`/`[3]` one-click switch Official/Bilibili, `[4]` launch the game
- Prerequisite: you must first obtain the other server's channel pack (~500–700 MB, extracted from an installed client or copied from elsewhere)

> ⚠ **High risk**: this modifies client files (including exe/assembly), is not officially supported, may violate the ToS, may trip anti-cheat, and may break after major updates. Use at your own risk.

## License

[MIT](LICENSE)

## Disclaimer

This is a third-party open-source tool, not affiliated with Hypergryph or Bilibili. Use at your own risk.
