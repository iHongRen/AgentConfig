#!/usr/bin/env sh

set -eu

REPO_OWNER="${REPO_OWNER:-iHongRen}"
REPO_NAME="${REPO_NAME:-AgentConfig}"
APP_NAME="${APP_NAME:-AgentConfig}"
DMG_NAME="${DMG_NAME:-AgentConfig.dmg}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
DMG_URL="${DMG_URL:-https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/latest/download/${DMG_NAME}}"

need_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: required command not found: %s\n' "$1" >&2
    exit 1
  fi
}

need_command curl
need_command hdiutil
need_command open
need_command xattr

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agentconfig-install.XXXXXX")"
DMG_PATH="${TMP_DIR}/${DMG_NAME}"
MOUNT_DIR="${TMP_DIR}/mount"
TARGET_APP="${INSTALL_DIR}/${APP_NAME}.app"
MOUNTED=0

cleanup() {
  if [ "${MOUNTED}" -eq 1 ]; then
    hdiutil detach "${MOUNT_DIR}" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "${TMP_DIR}"
}

trap cleanup EXIT INT TERM

printf 'Downloading %s...\n' "${DMG_URL}"
curl -fL --progress-bar "${DMG_URL}" -o "${DMG_PATH}"

mkdir -p "${MOUNT_DIR}"
printf 'Mounting %s...\n' "${DMG_NAME}"
hdiutil attach "${DMG_PATH}" \
  -nobrowse \
  -readonly \
  -noverify \
  -mountpoint "${MOUNT_DIR}" \
  -quiet
MOUNTED=1

SOURCE_APP="${MOUNT_DIR}/${APP_NAME}.app"
if [ ! -d "${SOURCE_APP}" ]; then
  printf 'error: %s was not found in the DMG\n' "${APP_NAME}.app" >&2
  exit 1
fi

printf 'Installing to %s...\n' "${TARGET_APP}"
mkdir -p "${INSTALL_DIR}"
rm -rf "${TARGET_APP}"
cp -R "${SOURCE_APP}" "${TARGET_APP}"

printf 'Removing macOS quarantine attributes...\n'
xattr -dr com.apple.quarantine "${TARGET_APP}" >/dev/null 2>&1 || true

printf 'Installed %s successfully.\n' "${TARGET_APP}"
printf 'Opening %s...\n' "${APP_NAME}.app"
open "${TARGET_APP}"
