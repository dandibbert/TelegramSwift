#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
if [[ -d /Applications/Xcode_16.4.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer
fi
xcodebuild -version
# Upstream uses SSH submodule URLs; CI must not need the owner's SSH key.
git config --global url.https://github.com/.insteadOf git@github.com:
git config --global url.https://gitlab.com/.insteadOf git@gitlab.com:
git submodule sync --recursive
git -c protocol.version=2 submodule update --init --recursive --depth 1 --jobs 4 2>&1 | tee build/logs/submodules.log
brew install ninja autoconf automake libtool yasm nasm pkg-config meson
python3 -m venv "${RUNNER_TEMP:-/tmp}/player-build-tools"
"${RUNNER_TEMP:-/tmp}/player-build-tools/bin/pip" install 'cmake==3.31.6'
export PATH="${RUNNER_TEMP:-/tmp}/player-build-tools/bin:$PATH"
# Applies to nested xcodebuild calls as well as the application itself.
export XCODE_XCCONFIG_FILE="${RUNNER_TEMP:-/tmp}/player-unsigned.xcconfig"
cat > "$XCODE_XCCONFIG_FILE" <<'CONFIG'
CODE_SIGNING_ALLOWED = NO
CODE_SIGNING_REQUIRED = NO
CODE_SIGN_IDENTITY =
DEVELOPMENT_TEAM =
ENABLE_USER_SCRIPT_SANDBOXING = NO
COMPILER_INDEX_STORE_ENABLE = NO
CONFIG
cp configurations/Stable.xcconfig Telegram-Mac/Release.xcconfig
printf 'no\n' > scripts/rebuild
bash scripts/configure_frameworks.sh 2>&1 | tee build/logs/frameworks.log
xcodebuild build -workspace Telegram-Mac.xcworkspace -scheme Telegram \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData -jobs 3 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee build/logs/application.log
# Only package a feature build, never a stock client with the upstream test API ID.
if [[ -d packages/EnhancedMediaPlayer ]]; then
  app=build/DerivedData/Build/Products/Release/Telegram.app
  test -d "$app"
  mkdir -p build/output
  cp -R "$app" 'build/output/Telegram Player.app'
  codesign --force --deep --sign - 'build/output/Telegram Player.app'
  codesign --verify --deep --strict 'build/output/Telegram Player.app'
  ditto -c -k --sequesterRsrc --keepParent 'build/output/Telegram Player.app' 'build/Telegram-Player-macOS.zip'
fi
