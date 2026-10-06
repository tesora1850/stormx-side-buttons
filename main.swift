// SideButtons — STORMX 버티컬 마우스 옆 버튼을 맥에서 쓰게 해주는 상단바 앱.
// 구성: Engine(버튼 신호·제스처) / Battery(배터리) / Config(설정 저장) / App(상단바·메뉴) / SettingsView(설정 창)

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
