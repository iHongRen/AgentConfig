#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT="${PROJECT:-${REPO_ROOT}/AgentConfig/AgentConfig.xcodeproj}"
SCHEME="${SCHEME:-AgentConfig}"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="${APP_NAME:-AgentConfig}"
VOLUME_NAME="${VOLUME_NAME:-AgentConfig}"
DMG_NAME="${DMG_NAME:-${APP_NAME}.dmg}"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/dist}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${REPO_ROOT}/.build/dmg-derived-data}"
STAGING_DIR="${REPO_ROOT}/.build/dmg-staging"

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"

XCODEBUILD_SETTINGS=(
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_IDENTITY=""
)

if [[ -n "${VERSION:-}" ]]; then
  XCODEBUILD_SETTINGS+=(MARKETING_VERSION="${VERSION}")
fi

if [[ -n "${BUILD_NUMBER:-}" ]]; then
  XCODEBUILD_SETTINGS+=(CURRENT_PROJECT_VERSION="${BUILD_NUMBER}")
fi

echo "==> Building ${APP_NAME}.app (${CONFIGURATION})"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  "${XCODEBUILD_SETTINGS[@]}" \
  build

if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: built app was not found at ${APP_PATH}" >&2
  exit 1
fi

echo "==> Staging DMG contents"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}" "${OUTPUT_DIR}"
cp -R "${APP_PATH}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "==> Creating ${DMG_PATH}"
rm -f "${DMG_PATH}"
hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo "==> Done"
echo "${DMG_PATH}"
