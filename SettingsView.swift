// 설정 창 (SwiftUI)

import SwiftUI
import AppKit
import CoreGraphics

struct SettingsView: View {
    @ObservedObject var store = Store.shared
    /// 마지막으로 보던 탭 기억
    @AppStorage("settingsTab") private var tab = "buttons"

    var body: some View {
        TabView(selection: $tab) {
            ButtonsTab(store: store)
                .tabItem { Label(tr("버튼", "Buttons"), systemImage: "computermouse") }
                .tag("buttons")
            GeneralTab(store: store)
                .tabItem { Label(tr("일반", "General"), systemImage: "gearshape") }
                .tag("general")
        }
        .frame(width: 560, height: 640)
        .id(store.settings.language)   // 언어를 바꾸면 화면 전체를 새로 그린다
    }
}

// MARK: - 버튼 탭

struct ButtonsTab: View {
    @ObservedObject var store: Store
    /// nil = 기본(모든 앱), 아니면 앱 번들 ID
    @State private var selected: String?

    private var profile: Binding<Profile> {
        Binding(
            get: {
                if let id = selected, let o = store.settings.overrides.first(where: { $0.bundleID == id }) {
                    return o.profile
                }
                return store.settings.base
            },
            set: { new in
                if let id = selected, let i = store.settings.overrides.firstIndex(where: { $0.bundleID == id }) {
                    store.settings.overrides[i].profile = new
                } else {
                    store.settings.base = new
                }
            })
    }

    private var selectedIndex: Int? {
        selected.flatMap { id in store.settings.overrides.firstIndex { $0.bundleID == id } }
    }

    var body: some View {
        Form {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 6) {
                        AppChip(name: tr("기본", "Default"), icon: nil, selected: selected == nil, enabled: true) { selected = nil }
                        ForEach(store.settings.overrides) { o in
                            AppChip(name: o.name, icon: appIcon(o.bundleID), selected: selected == o.bundleID,
                                    enabled: o.enabled) { selected = o.bundleID }
                        }
                        AddAppMenu { id, name in
                            if !store.settings.overrides.contains(where: { $0.bundleID == id }) {
                                store.settings.overrides.append(AppOverride(bundleID: id, name: name, profile: store.settings.base))
                            }
                            selected = id
                        }
                    }
                    .padding(.vertical, 2)
                }

                if let i = selectedIndex {
                    HStack {
                        Toggle(tr("\(store.settings.overrides[i].name) 전용 설정 사용", "Use settings for \(store.settings.overrides[i].name)"), isOn: $store.settings.overrides[i].enabled)
                        Spacer()
                        Button(role: .destructive) {
                            store.settings.overrides.remove(at: i)
                            selected = nil
                        } label: { Label(tr("삭제", "Delete"), systemImage: "trash") }
                    }
                    Text(store.settings.overrides[i].enabled
                         ? tr("이 앱이 맨 앞에 있을 때 아래 설정이 적용돼요.", "These settings apply while this app is in front.")
                         : tr("꺼져 있어서 이 앱에서도 '기본' 설정이 적용돼요.", "Turned off, so the Default settings apply in this app too."))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(tr("앱별 설정이 없거나 꺼져 있는 모든 앱에 적용돼요. 위 + 버튼으로 앱을 추가하면 그 앱에서만 다르게 쓸 수 있어요.", "Applies to every app without its own settings. Add an app with + to set it up differently."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            ButtonSection(title: tr("엄지 버튼 (위)", "Thumb button (upper)"), config: profile.buttons[0])
            ButtonSection(title: tr("아래 버튼", "Lower button"), config: profile.buttons[1])
        }
        .formStyle(.grouped)
    }
}

/// 앱 아이콘 칩 (누르면 그 앱 설정으로)
struct AppChip: View {
    let name: String
    let icon: NSImage?
    let selected: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Group {
                    if let icon {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: "square.grid.2x2").font(.system(size: 20)).foregroundStyle(Color.accentColor)
                    }
                }
                .frame(width: 36, height: 36)
                .opacity(enabled ? 1 : 0.35)
                Text(name).font(.caption2).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(enabled ? Color.primary : Color.secondary)
            }
            .frame(width: 64)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.22) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(enabled ? name : tr("\(name) (꺼짐)", "\(name) (off)"))
    }
}

func appIcon(_ bundleID: String) -> NSImage? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path)
}

struct ButtonSection: View {
    let title: String
    @Binding var config: ButtonConfig

    var body: some View {
        Section(title) {
            LabeledContent(tr("누르고 있기", "Hold")) { ModifierToggles(value: $config.hold) }
            LabeledContent(tr("톡", "Tap")) { ActionPicker(action: $config.tap) }
            LabeledContent(tr("톡 + 누르고 있기", "Tap + hold")) { ModifierToggles(value: $config.hold2) }
            LabeledContent(tr("톡톡", "Double tap")) { ActionPicker(action: $config.tap2) }
            if config.usesDouble && config.tap != .none {
                Text(tr("톡톡 계열을 쓰면 '톡'은 톡톡 간격만큼 늦게 실행돼요.", "With double-tap actions set, 'Tap' fires after the double-tap interval."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// ⌃ ⌥ ⇧ ⌘ 켜고 끄기
struct ModifierToggles: View {
    @Binding var value: UInt64
    private let items: [(CGEventFlags, String, String)] = [
        (.maskControl, "⌃", "Control"), (.maskAlternate, "⌥", "Option"),
        (.maskShift, "⇧", "Shift"), (.maskCommand, "⌘", "Command"),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.1) { flag, symbol, name in
                let on = value & flag.rawValue != 0
                Button {
                    value ^= flag.rawValue
                } label: {
                    // 배경과 클릭 영역을 버튼 안에 둬야 네모 어디를 눌러도 한 번에 눌린다
                    Text(symbol).font(.system(size: 15, weight: .semibold))
                        .frame(width: 30, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.accentColor : Color.secondary.opacity(0.15)))
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(name)
            }
        }
    }
}

/// 톡 / 톡톡에 넣을 기능 고르기 + 단축키 녹화
struct ActionPicker: View {
    @Binding var action: TapAction
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            if recording {
                Text(tr("키 조합을 누르세요… (esc 취소)", "Press a key combo… (esc to cancel)"))
                    .foregroundStyle(Color.accentColor)
            }
            Menu(action.title) {
                Button(tr("없음", "None")) { action = .none }
                Divider()
                ForEach(Preset.allCases, id: \.self) { p in
                    Button("\(p.title)  \(p.combo.display)") { action = .preset(p) }
                }
                Divider()
                Button(tr("단축키 녹화…", "Record shortcut…")) { startRecording() }
            }
            .fixedSize()
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        stopRecording()
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = e.modifierFlags.intersection([.command, .option, .shift, .control])
            if e.keyCode == 0x35 && mods.isEmpty {   // esc
                stopRecording()
                return nil
            }
            action = .custom(KeyCombo(keyCode: e.keyCode, modifiers: cgFlags(mods).rawValue,
                                      display: Modifiers.symbols(cgFlags(mods)) + keyName(e)))
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        recording = false
    }
}

func cgFlags(_ m: NSEvent.ModifierFlags) -> CGEventFlags {
    var f: CGEventFlags = []
    if m.contains(.command) { f.insert(.maskCommand) }
    if m.contains(.option) { f.insert(.maskAlternate) }
    if m.contains(.shift) { f.insert(.maskShift) }
    if m.contains(.control) { f.insert(.maskControl) }
    return f
}

func keyName(_ e: NSEvent) -> String {
    let special: [UInt16: String] = [
        0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x75: "⌦", 0x35: "esc",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑", 0x73: "Home", 0x77: "End", 0x74: "PgUp", 0x79: "PgDn",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    ]
    if let s = special[e.keyCode] { return s }
    return (e.charactersIgnoringModifiers ?? "?").uppercased()
}

/// 앱별 설정에 앱 추가: 실행 중인 앱 목록 + 찾아보기
struct AddAppMenu: View {
    let onAdd: (String, String) -> Void

    var body: some View {
        Menu {
            let apps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
                .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
            Section(tr("실행 중인 앱", "Running apps")) {
                ForEach(apps, id: \.processIdentifier) { app in
                    Button(app.localizedName ?? app.bundleIdentifier!) {
                        onAdd(app.bundleIdentifier!, app.localizedName ?? app.bundleIdentifier!)
                    }
                }
            }
            Divider()
            Button(tr("찾아보기…", "Browse…")) { browse() }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 18, weight: .medium)).frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3])))
                Text(tr("앱 추가", "Add app")).font(.caption2)
            }
            .frame(width: 64)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .padding(.vertical, 6)
        .fixedSize()
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        onAdd(id, name)
    }
}

// MARK: - 일반 탭

struct GeneralTab: View {
    @ObservedObject var store: Store
    @State private var batteryText = Battery.shared.menuText

    var body: some View {
        Form {
            Section(tr("톡톡", "Double tap")) {
                LabeledContent(tr("톡톡 간격", "Double-tap interval")) {
                    HStack {
                        Slider(value: Binding(get: { Double(store.settings.doubleWindowMs) },
                                              set: { store.settings.doubleWindowMs = Int($0) }),
                               in: 150...500, step: 10)
                            .frame(width: 220)
                        Text("\(store.settings.doubleWindowMs)ms").monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                }
                Text(tr("두 번째 톡을 이 시간 안에 눌러야 톡톡으로 인식돼요. 길게 할수록 톡톡이 쉬워지지만 '톡' 반응이 그만큼 늦어져요.", "The second tap must come within this time to count as a double tap. Longer is easier, but 'Tap' responds that much later."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(tr("언어", "Language")) {
                Picker(tr("화면 언어", "Interface language"), selection: $store.settings.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }

            Section(tr("표시", "Display")) {
                Toggle(tr("상단바에 배터리 % 표시", "Show battery % in the menu bar"), isOn: $store.settings.showPercentInMenuBar)
                Toggle(tr("Dock과 ⌘Tab에 항상 표시", "Always show in Dock and ⌘Tab"), isOn: $store.settings.showInDock)
                Text(tr("꺼져 있어도 설정 창이 열려 있는 동안에는 보여요.", "Even when off, it shows while the settings window is open."))
                    .font(.caption).foregroundStyle(.secondary)
                Picker(tr("보조키 누르고 있을 때", "While a modifier is held"), selection: $store.settings.indicator) {
                    ForEach(ModifierIndicator.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }

            Section(tr("배터리", "Battery")) {
                LabeledContent(tr("지금", "Now")) { Text(batteryText) }
                Toggle(tr("배터리 낮음 알림", "Low battery alert"), isOn: $store.settings.lowBatteryAlert)
                Stepper(tr("알림 기준: \(store.settings.lowBatteryThreshold)% 이하", "Alert at \(store.settings.lowBatteryThreshold)% or below"),
                        value: $store.settings.lowBatteryThreshold, in: 5...50, step: 5)
                Stepper(tr("완충 시 예상 사용 시간: \(Int(store.settings.fullChargeHours))시간", "Expected use per full charge: \(Int(store.settings.fullChargeHours)) h"),
                        value: $store.settings.fullChargeHours, in: 10...200, step: 5)
                if let learned = Battery.shared.state.learnedDrainPerHour {
                    Text(String(format: tr("블루투스 실측으로 학습한 값: 완충 시 약 %.0f시간 (이 값을 우선 사용해요)", "Learned from Bluetooth readings: about %.0f h per charge (used first)"), 100 / learned))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(tr("수신기 모드에서는 마우스를 실제로 쓴 시간으로 잔량을 추정해요. 블루투스로 연결할 때마다 실제 잔량으로 자동 보정돼요.", "In receiver mode the battery is estimated from actual usage time. It is corrected automatically each time you connect via Bluetooth."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(tr("충전했어요 (추정 다시 시작)", "I charged it (restart estimate)")) {
                    Battery.shared.markCharged()
                    batteryText = Battery.shared.menuText
                }
            }

            Section(tr("문제 해결", "Troubleshooting")) {
                Toggle(tr("진단 기록 남기기 (버튼 누를 때마다 기록)", "Diagnostic log (records every button press)"), isOn: $store.settings.diagnosticLog)
                Button(tr("기록 파일 보기", "Show log file")) { NSWorkspace.shared.open(logURL) }
                LabeledContent(tr("권한", "Permissions")) {
                    Text(Engine.shared.hasPermissions ? tr("정상", "OK") : tr("입력 모니터링 / 손쉬운 사용 권한 필요", "Input Monitoring / Accessibility permission needed"))
                        .foregroundStyle(Engine.shared.hasPermissions ? Color.secondary : Color.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { batteryText = Battery.shared.menuText }
    }
}
