---
name: sim-transfer
description: Transfer files from the host Mac to the iOS Simulator. Use this skill whenever the user asks to push, upload, copy, or transfer a file to the simulator, or when you need to get a book/document/file into a running iOS app on the simulator. Also triggers when the user says things like "put this file in the simulator", "import this into the app", or "send this to the iPhone". Handles macOS TCC restrictions (~/Downloads, ~/Desktop, ~/Documents) automatically via Finder AppleScript.
---

# Sim-Transfer: Push Files to iOS Simulator

Transfer files from anywhere on the host Mac into the iOS Simulator. Two distinct outcomes:

- **Files picker visible** — file appears in "On My iPhone" via `simctl openurl` + Save to Files dialog (semi-automated: user confirms save in simulator UI)
- **Direct app access** — file goes into the app's sandbox (fully automated, but not visible in the Files picker)

## Why this exists

macOS protects certain folders (Downloads, Desktop, Documents) with TCC. Terminal subprocesses (including Claude Code) can't read from these folders. Finder always has access, so this skill uses Finder via AppleScript as a relay.

## Workflow

### Step 1: Identify the simulator

```bash
SIMCTL=/Applications/Xcode.app/Contents/Developer/usr/bin/simctl
SIM_ID=$($SIMCTL list devices booted -j | python3 -c "import sys,json; devs=[d for r in json.load(sys.stdin)['devices'].values() for d in r if d['state']=='Booted']; print(devs[0]['udid'])")
```

### Step 2: Copy from TCC-protected folder via Finder

If the source file is in ~/Downloads, ~/Desktop, ~/Documents, or any path that gives "Operation not permitted":

```bash
osascript -e '
tell application "Finder"
    set srcFile to POSIX file "<SOURCE_PATH>" as alias
    set destFolder to POSIX file "/tmp/" as alias
    duplicate srcFile to destFolder with replacing
end tell
'
```

If the file is already accessible (project directory, /tmp), skip this step.

### Step 3: Transfer to simulator

#### Option A: Files picker visible (recommended for user-driven import)

Uses `simctl openurl` to trigger the iOS "Save to Files" dialog. After the user confirms, the file appears under "On My iPhone" and is selectable from any app's file picker.

```bash
SIMCTL=/Applications/Xcode.app/Contents/Developer/usr/bin/simctl
SIM_ID=<SIMULATOR_UUID>
$SIMCTL openurl "$SIM_ID" "file:///tmp/<filename>"
```

Then use computer use to tap "Save" in the simulator's Save to Files dialog.

**Note:** File URLs with spaces or non-ASCII characters may need percent-encoding. Use Python: `python3 -c "import urllib.parse; print(urllib.parse.quote('/tmp/file name.epub', safe='/'))"`.

#### Option B: App Inbox + openurl (recommended for targeting a specific app)

Copy to the app's Documents/Inbox, then trigger iOS file handling:

```bash
SIMCTL=/Applications/Xcode.app/Contents/Developer/usr/bin/simctl
SIM_ID=<SIMULATOR_UUID>
APP_DATA=$($SIMCTL get_app_container "$SIM_ID" <BUNDLE_ID> data)
INBOX="$APP_DATA/Documents/Inbox"
mkdir -p "$INBOX"
cp "/tmp/<filename>" "$INBOX/"
$SIMCTL openurl "$SIM_ID" "file://$INBOX/<filename>"
```

#### Option C: Direct app sandbox (fully automated, no picker visibility)

For testing only — puts files directly into app storage. Not visible in the Files picker.

```bash
SIMCTL=/Applications/Xcode.app/Contents/Developer/usr/bin/simctl
SIM_ID=<SIMULATOR_UUID>
APP_DATA=$($SIMCTL get_app_container "$SIM_ID" <BUNDLE_ID> data)

# Example: vreader's ImportedBooks
DEST="$APP_DATA/Library/Application Support/ImportedBooks"
mkdir -p "$DEST"
cp "/tmp/<filename>" "$DEST/"
```

**Warning:** This requires knowing the app's internal storage structure and won't trigger the app's import pipeline.

### Step 4 (optional): Launch the app

```bash
SIMCTL=/Applications/Xcode.app/Contents/Developer/usr/bin/simctl
$SIMCTL launch "$SIM_ID" <BUNDLE_ID>
```

## One-liner for common case

File from ~/Downloads → simulator Files picker:

```bash
SIMCTL=/Applications/Xcode.app/Contents/Developer/usr/bin/simctl
SIM_ID=$($SIMCTL list devices booted -j | python3 -c "import sys,json; devs=[d for r in json.load(sys.stdin)['devices'].values() for d in r if d['state']=='Booted']; print(devs[0]['udid'])")
osascript -e "tell application \"Finder\" to duplicate (POSIX file \"<SOURCE_PATH>\" as alias) to (POSIX file \"/tmp/\" as alias) with replacing"
$SIMCTL openurl "$SIM_ID" "file:///tmp/<FILENAME>"
echo "Tap Save in the simulator to complete"
```

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| "Operation not permitted" on cp from ~/Downloads | macOS TCC | Use Finder AppleScript relay (Step 2) |
| "No such file or directory" for simulator path | Simulator not booted or wrong UUID | Run `simctl list devices booted` |
| File doesn't appear in Files picker after File Provider Storage copy | File Provider Storage is unreliable for picker visibility | Use `simctl openurl` (Option A) instead |
| `openurl` rejects the URL | Spaces/CJK in filename | Percent-encode the file path |
| AppleScript error "file not found" | Special characters in path | Ensure path is properly quoted |

## Deprecated: File Provider Storage

Copying files into `systemgroup.com.apple.FileProvider.LocalStorage/File Provider Storage` does NOT reliably surface them in the iOS Files picker. Do not use this for automated import flows.

## Known app bundle IDs

| App | Bundle ID |
|-----|-----------|
| VReader | com.vreader.app |
