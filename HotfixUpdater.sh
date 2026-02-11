#!/bin/sh
# Name: Update Hotfix
# Author: KindleTweaks
# DontUseFBInk

REPO_API="https://api.github.com/repos/KindleModding/Hotfix/releases/latest"
BASE_DIR="/mnt/us/documents/HotfixUpdater"
DOWNLOAD_BIN="$BASE_DIR/Update.bin"
TMP_DIR="$BASE_DIR/TMP"
KT_HF="$BASE_DIR/KTHF"
KT_PW2="$BASE_DIR/KTPW2"
BIN_NAME="Update_hotfix_universal.bin"

alert() {
    TITLE="$1"
    TEXT="$2"
    TITLE_ESC=$(printf '%s' "$TITLE" | sed 's/"/\\"/g')
    TEXT_ESC=$(printf '%s' "$TEXT" | sed 's/"/\\"/g')
    JSON='{ "clientParams":{ "alertId":"appAlert1", "show":true, "customStrings":[ { "matchStr":"alertTitle", "replaceStr":"'"$TITLE_ESC"'" }, { "matchStr":"alertText", "replaceStr":"'"$TEXT_ESC"'" } ] } }'

    lipc-set-prop com.lab126.pillow pillowAlert "$JSON"
}

detect_device() {
    if [ -e /lib/ld-linux-armhf.so.3 ]; then
        echo "HF"
    else
        echo "PW2"
    fi
}

get_kindletool() {
    DEVICE="$(detect_device)"
    if [ "$DEVICE" = "HF" ]; then
        echo "$KT_HF"
    else
        echo "$KT_PW2"
    fi
}

cleanup_tmp() {
    if [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR" >/dev/null 2>&1
    fi
}

normalize_version() {
    echo "$1" | tr -d '\r\n ' | sed 's/^v//'
}

version_gt() {
    awk -v v1="$1" -v v2="$2" '
    BEGIN {
        split(v1, a, ".");
        split(v2, b, ".");
        for (i = 1; i <= 3; i++) {
            if (a[i] + 0 > b[i] + 0) exit 0;
            if (a[i] + 0 < b[i] + 0) exit 1;
        }
        exit 1;
    }'
}

extract_and_run() {
    KT_BIN="$(get_kindletool)"
    if [ ! -x "$KT_BIN" ]; then
        alert "HotfixUpdater - Attention" "KindleTool not found or not executable!"
        return 1
    fi

    alert "HotfixUpdater - Info" "Using KindleTool: $KT_BIN"
    cleanup_tmp
    mkdir -p "$TMP_DIR" >/dev/null 2>&1

    alert "HotfixUpdater - Info" "Extracting update..."
    if ! "$KT_BIN" extract "$DOWNLOAD_BIN" "$TMP_DIR" >/dev/null 2>&1; then
        alert "HotfixUpdater - Attention" "Extraction failed!"
        return 1
    fi

    alert "HotfixUpdater - Info" "Remounting root RW..."
    if ! mount -o remount,rw / >/dev/null 2>&1; then
        alert "HotfixUpdater - Attention" "Failed to remount root RW!"
        return 1
    fi

    alert "HotfixUpdater - Info" "Running payload scripts..."
    cd "$TMP_DIR" || return 1

    for f in *.sh; do
        [ -f "$f" ] || continue

        alert "HotfixUpdater - Info" "Running $f"
        if ! sh "$f" >/dev/null 2>&1; then
            alert "HotfixUpdater - Attention" "Script failed: $f"
            mount -o remount,ro / >/dev/null 2>&1
            return 1
        fi
    done
    alert "HotfixUpdater - Info" "Remounting root RO..."
    mount -o remount,ro / >/dev/null 2>&1

    cleanup_tmp
    alert "HotfixUpdater - Success" "Update applied successfully."
    return 0
}

alert "HotfixUpdater - Info" "Checking hotfix version..."

CURRENT_VERSION=$(grep '^HOTFIX_VERSION=' /var/local/kmc/hotfix/libhotfixutils | cut -d'=' -f2 | tr -d '"')
if [ -z "$CURRENT_VERSION" ]; then
    alert "HotfixUpdater - Attention" "Cannot detect version!"
    exit 1
fi

alert "HotfixUpdater - Info" "Installed version: v$CURRENT_VERSION!"

RELEASE_JSON="$(curl -fsL "$REPO_API")"
if [ $? -ne 0 ] || [ -z "$RELEASE_JSON" ]; then
    alert "HotfixUpdater - Attention" "Failed to fetch release info!"
    exit 1
fi

LATEST_VERSION_RAW="$(echo "$RELEASE_JSON" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')"
LATEST_VERSION="$(normalize_version "$LATEST_VERSION_RAW")"
if [ -z "$LATEST_VERSION" ]; then
    alert "HotfixUpdater - Attention" "Failed to parse latest version!"
    exit 1
fi

alert "HotfixUpdater - Info" "Latest version: v$LATEST_VERSION!"
if [ "$LATEST_VERSION" = "$CURRENT_VERSION" ]; then
    alert "HotfixUpdater - Success" "You are on the latest version."
    exit 0
fi

if version_gt "$LATEST_VERSION" "$CURRENT_VERSION"; then
    alert "HotfixUpdater - Info" "Update available!"

    DOWNLOAD_URL="$(echo "$RELEASE_JSON" | grep '"browser_download_url"' | grep "$BIN_NAME" | sed -E 's/.*"([^"]+)".*/\1/')"
    if [ -z "$DOWNLOAD_URL" ]; then
        alert "HotfixUpdater - Attention" "Failed to find $BIN_NAME in release!"
        exit 1
    fi

    alert "HotfixUpdater - Info" "Downloading update...\n$DOWNLOAD_URL"
    mkdir -p "$BASE_DIR" >/dev/null 2>&1
    if ! curl -sSfL "$DOWNLOAD_URL" -o "$DOWNLOAD_BIN"; then
        alert "HotfixUpdater - Attention" "Download failed!"
        exit 1
    fi

    alert "HotfixUpdater - Success" "Download complete: $DOWNLOAD_BIN"
    alert "HotfixUpdater - Info" "The Hotfix will install & initialise in 10s.\nWait until GUI restart."
    sleep 10

    if ! extract_and_run; then
        alert "HotfixUpdater - Attention" "Update installation failed!"
        exit 1
    fi

    alert "HotfixUpdater - Info" "Running Hotfix..."
    /bin/sh /var/local/kmc/hotfix/run_hotfix.sh >/dev/null 2>&1

    alert "HotfixUpdater - Success" "Hotfix installed!"
    rm -f "$DOWNLOAD_BIN" >/dev/null 2>&1
    exit 0
else
    alert "HotfixUpdater - Success" "You are on the latest version."
    exit 0
fi
