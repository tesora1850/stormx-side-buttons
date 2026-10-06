# SideButtons

**English summary** — A small macOS menu bar app that makes the side buttons work on the
Xenics STORMX vertical mouse (VM1BT) and other mice with the same chip (USB vendor `0x248a`).
These mice declare only 3 buttons in their HID report descriptor but actually send 5 button bits,
so macOS (and tools built on top of it, like LinearMouse or Karabiner-Elements) drops the side buttons.
SideButtons reads the raw HID input reports directly and maps each side button to
hold-a-modifier / tap / tap-then-hold / double-tap actions, with per-app profiles and battery
reading (Bluetooth) or usage-based estimation (USB receiver). No network access, no keystroke logging.
Build with `./build.sh` (macOS 13+, Xcode command line tools). The UI is available in English and Korean.

---

맥에서 안 되는 **제닉스 STORMX 버티컬 마우스(VM1BT)의 옆 버튼**을 살려주는 상단바 앱.

## 왜 맥에서 옆 버튼이 안 되나

이 마우스는 수신기(USB `0x248a:0x8566`)와 블루투스(`BT5.0 Mouse`, `0x248a:0x8266`) 모두
HID 디스크립터에 **버튼이 3개**라고 적어 두고, 실제로는 버튼 비트를 5칸 보낸다.
옆 버튼은 4번째·5번째 칸(`0x08`, `0x10`)에 실려 오는데, 맥은 선언되지 않은 칸을 버린다.
그래서 LinearMouse, Karabiner-Elements, BetterTouchTool처럼 맥의 해석을 거치는 도구로는 고칠 수 없다.

SideButtons는 `IOHIDDeviceRegisterInputReportCallback`으로 **원본 리포트를 직접 읽어서** 4·5번 칸을 찾는다.

## 기능

- 옆 버튼마다 4가지 동작: **누르고 있기 / 톡 / 톡 + 누르고 있기 / 톡톡**
  - 누르고 있기: ⌘ ⌥ ⇧ ⌃ 보조키 조합. 누르고 있는 동안 키보드, 클릭, 드래그, 휠에 모두 붙는다.
    로직 프로에서 ⌥+휠(세로 확대), ⌥⌘+휠(가로 확대) 같은 동작을 마우스로 쓸 수 있다.
  - 톡 / 톡톡: 목록(뒤로/앞으로, 실행 취소, Mission Control 등)에서 고르거나 단축키를 녹화한다.
  - 짧은 톡에서는 보조키를 실제로 누르지 않는다. 그래서 "⌥ 두 번" 같은 단축키가 오작동하지 않는다.
- 앱별 설정 (예: 로직에서만 다르게). 앱마다 켜고 끌 수 있다.
- 상단바: 연결 모드(수신기/블루투스), 배터리, 잠시 끄기, 로그인 시 자동 실행
- 배터리
  - 블루투스: 마우스에 표준 Battery Service(0x180F)로 직접 물어본다.
  - 수신기: 배터리를 읽을 방법이 없어서, 마지막 실측값에서 **실제로 마우스를 쓴 시간**만큼 빼서 추정한다.
    블루투스로 연결할 때마다 소모 속도를 학습해서 보정한다.
  - 기준 % 이하가 되면 알림을 보낸다.
- 보조키를 누르고 있을 때 커서 옆에 배지 표시 (선택)
- 화면 언어: 한국어 / English (기본은 맥 시스템 언어를 따름)

DPI 버튼은 마우스 안에서만 처리되고 컴퓨터로 신호를 보내지 않아서 바꿀 수 없다.

## 설치

macOS 13 이상, Xcode 명령줄 도구가 필요하다.

```bash
./build.sh
```

`/Applications/SideButtons.app`에 설치하고 실행한다. 처음 실행하면 아래 권한을 켜야 한다.

- 시스템 설정 → 개인정보 보호 및 보안 → **입력 모니터링**: 마우스 원본 신호 읽기
- 같은 곳 → **손쉬운 사용**: 단축키와 보조키 보내기
- 블루투스, 알림: 배터리 읽기와 알림 (물어볼 때 허용)

서명은 이 맥에 있는 첫 번째 Apple Development 인증서를 쓴다(`SIGN_IDENTITY`로 지정 가능).
인증서가 없으면 임시 서명을 하는데, 이 경우 다시 빌드할 때마다 권한을 다시 켜야 한다.

설정 창은 상단바 메뉴의 "설정…"이나, 응용 프로그램 폴더에서 SideButtons를 다시 실행하면 열린다.

## 개인정보와 보안

이 앱은 키보드·마우스 입력을 볼 수 있는 권한을 받기 때문에, 무엇을 하고 무엇을 하지 않는지 밝혀 둔다.

- **인터넷 통신을 하지 않는다.** 네트워크 코드가 없고, 어떤 데이터도 밖으로 보내지 않는다.
- **키보드로 입력한 내용을 읽거나 저장하지 않는다.** 이벤트 탭은 모든 입력을 지나가게 하지만,
  하는 일은 옆 버튼을 누르고 있을 때 보조키(⌘⌥⇧⌃)를 덧붙이는 것과 "다른 입력이 있었는지"(예/아니요)를 보는 것뿐이다.
- 원본 HID 신호는 **이 마우스(벤더 0x248a, 마우스 용도)만** 읽는다. 다른 키보드·마우스는 읽지 않는다.
- 블루투스는 이름이 `BT5.0 Mouse`인 기기의 표준 배터리 값만 읽는다. 다른 기기에는 연결하지 않는다.
- 외부 라이브러리를 쓰지 않는다. Apple 기본 프레임워크만 쓴다.
- 처음 실행할 때 **로그인 항목에 자동 등록**된다. 상단바 메뉴 "로그인 시 자동 실행"이나
  시스템 설정 → 일반 → 로그인 항목에서 끌 수 있다.

| 권한 | 쓰는 이유 |
|---|---|
| 입력 모니터링 | 이 마우스의 원본 신호 읽기 |
| 손쉬운 사용 | 단축키 보내기, 누르고 있는 동안 다른 입력에 보조키 덧붙이기 |
| 블루투스 | 블루투스 모드에서 배터리 잔량 읽기 |
| 알림 | 배터리 낮음 알림 |

저장하는 파일 (모두 이 맥 안에만 있다):
- `~/Library/Application Support/SideButtons/config.json`: 설정 (앱별 설정에 넣은 앱의 번들 ID 포함)
- `~/Library/Application Support/SideButtons/battery.json`: 배터리 추정용 숫자
- `~/Library/Logs/SideButtons.log`: 시작, 장치 연결, 오류. 진단 기록을 켜면 마우스 버튼 신호도 남는다.
  키보드 입력은 남기지 않는다. 1MB가 넘으면 `.old`로 옮기고 새로 시작한다.

## 파일

| 파일 | 내용 |
|---|---|
| `Engine.swift` | 원본 리포트 읽기, 제스처 판단, 보조키/단축키 보내기, 이벤트 탭 |
| `Battery.swift` | 배터리 추정, 학습, 알림 |
| `BLEBattery.swift` | 블루투스 배터리 읽기 |
| `Config.swift` | 설정 데이터와 저장 (`~/Library/Application Support/SideButtons/`) |
| `App.swift` | 상단바 메뉴, 설정 창, 로그인 항목, Dock 표시, 커서 배지 |
| `SettingsView.swift` | 설정 창 (SwiftUI) |
| `Lang.swift` | 화면 언어 (한국어/영어) |
| `Resources/*.lproj` | 블루투스 권한 안내 문구 번역 |
| `tools/make_icon.swift` | 앱 아이콘 생성 |

기록 파일: `~/Library/Logs/SideButtons.log` (설정 → 일반 → 진단 기록을 켜면 버튼 신호까지 남는다)

## 라이선스

MIT. [LICENSE](LICENSE) 참고.
