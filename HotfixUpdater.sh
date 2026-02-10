#!/bin/sh
# Name: Update Hotfix
# Author: KindleTweaks

VERSION_FILE="/mnt/us/documents/Run Hotfix.run_hotfix"
REPO_API="https://api.github.com/repos/KindleModding/Hotfix/releases/latest"

BASE_DIR="/mnt/us/documents/HotfixUpdater"
DOWNLOAD_BIN="$BASE_DIR/Update.bin"
TMP_DIR="$BASE_DIR/TMP"

KT_HF="$BASE_DIR/KTHF"
KT_PW2="$BASE_DIR/KTPW2"

BIN_NAME="Update_hotfix_universal.bin"

timed_exit() {
    CODE="${1:-1}"
    echo "[!] Closing In 10s..."
    sleep 10
    exit "$CODE"
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

rw_root() {
    mount -o remount,rw / >/dev/null 2>&1
}

ro_root() {
    mount -o remount,ro / >/dev/null 2>&1
}

cleanup_tmp() {
    if [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR" >/dev/null 2>&1
    fi
}

extract_and_run() {
    KT_BIN="$(get_kindletool)"
    if [ ! -x "$KT_BIN" ]; then
        echo "[!] KindleTool Not Found Or Not Executable!"
        return 1
    fi
    echo "[*] Using KindleTool: $KT_BIN"
    cleanup_tmp
    mkdir -p "$TMP_DIR" >/dev/null 2>&1
    echo "[*] Extracting Update..."
    if ! "$KT_BIN" extract "$DOWNLOAD_BIN" "$TMP_DIR" >/dev/null 2>&1; then
        echo "[!] Extraction Failed!"
        return 1
    fi
    echo "[*] Remounting Root RW..."
    if ! rw_root; then
        echo "[!] Failed To Remount Root RW!"
        return 1
    fi
    echo "[*] Running Payload Scripts..."
    cd "$TMP_DIR" || return 1
    for f in *.sh; do
        [ -f "$f" ] || continue
        echo "[*] Running $f"
        if ! sh "$f" >/dev/null 2>&1; then
            echo "[!] Script Failed: $f"
            ro_root
            return 1
        fi
    done
    echo "[*] Remounting Root RO..."
    ro_root
    cleanup_tmp
    echo "[@] Update Applied Successfully."
    return 0
}

echo "[*] Checking Hotfix Version..."

if [ ! -f "$VERSION_FILE" ]; then
    echo "[!] Version File Not Found: $VERSION_FILE!"
    timed_exit
fi

CURRENT_VERSION=$(grep '^HOTFIX_VERSION=' /var/local/kmc/hotfix/libhotfixutils | cut -d'=' -f2 | tr -d '"')

if [ -z "$CURRENT_VERSION" ]; then
    echo "[!] Version File Is Empty!"
    timed_exit
fi

echo "[*] Installed Version: v$CURRENT_VERSION!"

RELEASE_JSON="$(curl -fsL "$REPO_API")"

if [ $? -ne 0 ] || [ -z "$RELEASE_JSON" ]; then
    echo "[!] Failed To Fetch Release Info!"
    timed_exit
fi

LATEST_VERSION_RAW="$(echo "$RELEASE_JSON" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')"
LATEST_VERSION="$(normalize_version "$LATEST_VERSION_RAW")"

if [ -z "$LATEST_VERSION" ]; then
    echo "[!] Failed To Parse Latest Version!"
    timed_exit
fi

echo "[*] Latest Version: v$LATEST_VERSION!"

version_gt() {
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ] && [ "$1" != "$2" ]
}

if [ "$LATEST_VERSION" = "$CURRENT_VERSION" ]; then
    echo "[@] You Are On The Latest Version."
    timed_exit 0
fi

if version_gt "$LATEST_VERSION" "$CURRENT_VERSION"; then
    echo "[*] Update Available!"
    DOWNLOAD_URL="$(echo "$RELEASE_JSON" | grep '"browser_download_url"' | grep "$BIN_NAME" | sed -E 's/.*"([^"]+)".*/\1/')"
    if [ -z "$DOWNLOAD_URL" ]; then
        echo "[!] Failed To Find $BIN_NAME In Release!"
        timed_exit
    fi
    echo "[*] Downloading Update..."
    echo "[*] $DOWNLOAD_URL"
    mkdir -p "$BASE_DIR" >/dev/null 2>&1
    if ! curl -sSfL "$DOWNLOAD_URL" -o "$DOWNLOAD_BIN"; then
        echo "[!] Download Failed!"
        timed_exit
    fi
    echo "[@] Download Complete: $DOWNLOAD_BIN"

    echo "[!!!] The Hotfix Will Install & Initialise In 10s. Wait Until GUI Restart." # Lots Of FBINK Drawing Happens Now, Give The User Feedback.
    sleep 10

    if ! extract_and_run; then
        echo "[!] Update Installation Failed!"
        timed_exit
    fi
    echo "[@] Running Hotfix..."
    /bin/sh /var/local/kmc/hotfix/run_hotfix.sh >/dev/null 2>&1
    echo "[@] Hotfix Installed!"
    rm -f $DOWNLOAD_BIN >/dev/null 2>&1
    timed_exit 0
else
    echo "[@] You Are On The Latest Version."
    timed_exit 0
fi
