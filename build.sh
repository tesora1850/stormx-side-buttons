#!/bin/bash
# SideButtons 빌드 → /Applications 설치 → 실행.
# 같은 개발자 인증서로 서명하므로 다시 빌드해도 맥 권한이 유지된다.
# 로그인 시 자동 실행은 앱이 직접 등록한다 (시스템 설정 → 일반 → 로그인 항목).
set -euo pipefail
cd "$(dirname "$0")"

APP=/Applications/SideButtons.app
# 서명 인증서: SIGN_IDENTITY 로 지정하거나, 없으면 이 맥의 첫 Apple Development 인증서, 그것도 없으면 임시 서명(-).
# 임시 서명은 다시 빌드할 때마다 입력 모니터링·손쉬운 사용 권한을 다시 켜야 한다.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')}"
IDENTITY="${IDENTITY:--}"

rm -rf build/SideButtons.app && mkdir -p build/SideButtons.app/Contents/MacOS
swiftc -O -swift-version 5 Lang.swift Config.swift Engine.swift Battery.swift BLEBattery.swift SettingsView.swift App.swift main.swift \
    -o build/SideButtons.app/Contents/MacOS/SideButtons
cp Info.plist build/SideButtons.app/Contents/
mkdir -p build/SideButtons.app/Contents/Resources
cp AppIcon.icns build/SideButtons.app/Contents/Resources/
cp -R Resources/*.lproj build/SideButtons.app/Contents/Resources/   # 블루투스 권한 안내 문구 (한국어/영어)
codesign --force --sign "$IDENTITY" build/SideButtons.app

pkill -x SideButtons 2>/dev/null && sleep 1 || true
rm -rf "$APP" && cp -R build/SideButtons.app "$APP"
open "$APP"
echo "installed: $APP"
