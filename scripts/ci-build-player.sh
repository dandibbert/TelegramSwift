#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer
xcodebuild -version
# Read-only checkout; public submodules must not require the owner's SSH key.
git config --global url.https://github.com/.insteadOf git@github.com:
git config --global url.https://gitlab.com/.insteadOf git@gitlab.com:
git submodule sync --recursive
git -c protocol.version=2 submodule update --init --recursive --depth 1 --jobs 4 2>&1 | tee build/logs/submodules.log
brew install ninja autoconf automake libtool yasm nasm pkg-config meson
python3 -m venv "${RUNNER_TEMP:-/tmp}/player-build-tools"
"${RUNNER_TEMP:-/tmp}/player-build-tools/bin/pip" install 'cmake==3.31.6'
export PATH="${RUNNER_TEMP:-/tmp}/player-build-tools/bin:$PATH"
# The macOS project expects FFmpeg 7.1, absent from its pinned iOS submodule.
# Fetch the exact official release commit, not a moving latest version.
ffsrc=submodules/telegram-ios/submodules/ffmpeg/Sources/FFMpeg/ffmpeg-7.1
if [[ ! -f "$ffsrc/configure" ]]; then
  git init "$ffsrc"
  git -C "$ffsrc" remote add origin https://github.com/FFmpeg/FFmpeg.git
  git -C "$ffsrc" fetch --depth 1 origin b08d7969c550a804a59511c7b83f2dd8cc0499b8
  git -C "$ffsrc" checkout --detach FETCH_HEAD
fi
test "$(git -C "$ffsrc" rev-parse HEAD)" = b08d7969c550a804a59511c7b83f2dd8cc0499b8
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
# No official update feed or App Store sandbox for this ad-hoc personal build.
printf '\nSFEED_URL =\nSANDBOX_YES = NO\nAPPCENTER_SECRET =\n' >> Telegram-Mac/Release.xcconfig
printf 'no\n' > scripts/rebuild
bash scripts/configure_frameworks.sh 2>&1 | tee build/logs/frameworks.log
xcodebuild build -workspace Telegram-Mac.xcworkspace -scheme Telegram \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData -jobs 3 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee build/logs/application.log
# Never upload a stock build with the upstream test API ID.
test -f packages/EnhancedMediaPlayer/Package.swift
grep -q 'ensurePersonalCredentials' packages/ApiCredentials/Sources/ApiCredentials/Config.swift
app=build/DerivedData/Build/Products/Release/Telegram.app
test -d "$app"
mkdir -p build/output
cp -R "$app" 'build/output/Telegram Player.app'
plist='build/output/Telegram Player.app/Contents/Info.plist'
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Telegram Player' "$plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Telegram Player' "$plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" = io.github.dandibbert.TelegramPlayer
codesign --force --deep --sign - 'build/output/Telegram Player.app'
codesign --verify --deep --strict 'build/output/Telegram Player.app'
cp docs/ENHANCED_PLAYER.md build/output/README.md
cat > build/output/BUILD.txt <<INFO
Commit: $(git rev-parse HEAD)
Xcode: $(xcodebuild -version | tr '\n' ' ')
Signing: ad-hoc personal build, not notarized
Credentials: first-launch dialog; API hash stays in the local Keychain
INFO
ditto -c -k --sequesterRsrc --keepParent 'build/output/Telegram Player.app' 'build/Telegram-Player-macOS.zip'
shasum -a 256 build/Telegram-Player-macOS.zip | tee build/Telegram-Player-macOS.sha256
