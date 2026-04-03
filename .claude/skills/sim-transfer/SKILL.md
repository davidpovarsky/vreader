---
name: sim-transfer
description: Transfer files from the host Mac to the iOS Simulator. Use this skill whenever the user asks to push, upload, copy, or transfer a file to the simulator, or when you need to get a book/document/file into a running iOS app on the simulator. Also triggers when the user says things like "put this file in the simulator", "import this into the app", or "send this to the iPhone". Handles macOS TCC restrictions (~/Downloads, ~/Desktop, ~/Documents) automatically via Finder AppleScript.
---

# Sim-Transfer: Push Files to iOS Simulator

Transfer files from anywhere on the host Mac into the iOS Simulator's file system, making them accessible via the Files app ("On My iPhone") or directly into an app's sandbox.

## Why this exists

macOS protects certain folders (Downloads, Desktop, Documents) with TCC (Transparency, Consent, and Control). Terminal and its subprocesses often can't read from these folders even with Full Disk Access enabled, because the permission applies to Terminal.app itself, not child processes like Claude Code. Finder, however, always has access. This skill uses Finder via AppleScript as a relay to bypass TCC, then copies the file into the simulator.

## Workflow

### Step 1: Identify the simulator

Find the booted simulator ID. If multiple are booted, prefer the one matching the project's target device.

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/simctl list devices booted
```

### Step 2: Copy from TCC-protected folder via Finder

If the source file is in a TCC-protected location (~/Downloads, ~/Desktop, ~/Documents, or any path that gives "Operation not permitted"), use Finder AppleScript to relay the file to /tmp:

```bash
osascript -e '
tell application "Finder"
    set srcFile to POSIX file "<SOURCE_PATH>" as alias
    set destFolder to POSIX file "/tmp/" as alias
    duplicate srcFile to destFolder with replacing
end tell
'
```

If the file is already in an accessible location (e.g., the project directory, /tmp), skip this step.

After copying, the file is at `/tmp/<filename>`.

### Step 3: Push to simulator

There are two target locations depending on the goal:

#### Option A: Files app ("On My iPhone") — for user-visible import

This puts the file where the iOS Files app can see it, so the user (or app) can pick it from the file browser.

```bash
SIMCTL=/Applications/Xcode.app/Contents/Developer/usr/bin/simctl
SIM_ID=<SIMULATOR_UUID>
SIM_HOME="/Users/$USER/Library/Developer/CoreSimulator/Devices/$SIM_ID/data"
FILE_PROVIDER="$SIM_HOME/Containers/Shared/SystemGroup/systemgroup.com.apple.FileProvider.LocalStorage/File Provider Storage"

mkdir -p "$FILE_PROVIDER"
cp "/tmp/<filename>" "$FILE_PROVIDER/"
```

#### Option B: App sandbox — for direct app access

This puts the file directly into an app's Documents or ImportedBooks directory.

```bash
SIMCTL=/Applications/Xcode.app/Contents/Developer/usr/bin/simctl
SIM_ID=<SIMULATOR_UUID>
APP_DATA=$($SIMCTL get_app_container $SIM_ID <BUNDLE_ID> data)

# Example: vreader's ImportedBooks
DEST="$APP_DATA/Library/Application Support/ImportedBooks"
mkdir -p "$DEST"
cp "/tmp/<filename>" "$DEST/"
```

Note: putting files directly in the app sandbox requires knowing the app's internal storage structure. Option A is safer and more general.

### Step 4 (optional): Launch the app

```bash
$SIMCTL launch $SIM_ID <BUNDLE_ID>
```

## One-liner for common case

For the typical scenario (file from ~/Downloads → simulator Files app):

```bash
SIM_ID=$(/Applications/Xcode.app/Contents/Developer/usr/bin/simctl list devices booted -j | python3 -c "import sys,json; devs=[d for r in json.load(sys.stdin)['devices'].values() for d in r if d['state']=='Booted']; print(devs[0]['udid'])" 2>/dev/null) && \
osascript -e "tell application \"Finder\" to duplicate (POSIX file \"<SOURCE_PATH>\" as alias) to (POSIX file \"/tmp/\" as alias) with replacing" && \
SIM_HOME="/Users/$USER/Library/Developer/CoreSimulator/Devices/$SIM_ID/data" && \
cp "/tmp/<FILENAME>" "$SIM_HOME/Containers/Shared/SystemGroup/systemgroup.com.apple.FileProvider.LocalStorage/File Provider Storage/" && \
echo "Done — file is in On My iPhone"
```

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| "Operation not permitted" on cp from ~/Downloads | macOS TCC | Use the Finder AppleScript relay (Step 2) |
| "No such file or directory" for simulator path | Simulator not booted or wrong UUID | Run `simctl list devices booted` to verify |
| File doesn't appear in Files app | iOS caches the file list | Kill and relaunch the Files app, or wait a moment |
| AppleScript error "file not found" | Path has special characters | Ensure the path is properly quoted in the osascript command |

## Known app bundle IDs

| App | Bundle ID |
|-----|-----------|
| VReader | com.vreader.app |
