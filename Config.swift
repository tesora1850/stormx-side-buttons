// 설정 데이터와 저장. ~/Library/Application Support/SideButtons/config.json

import Foundation
import CoreGraphics

/// 녹화한 단축키 하나
struct KeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt64      // CGEventFlags.rawValue 중 ⌘⌥⇧⌃ 부분
    var display: String        // 화면 표시용 (예: "⌘⇧Z")
}

/// 톡 / 톡톡에 넣을 수 있는 기능
enum TapAction: Codable, Equatable, Hashable {
    case none
    case preset(Preset)
    case custom(KeyCombo)

    var title: String {
        switch self {
        case .none: return tr("없음", "None")
        case .preset(let p): return p.title
        case .custom(let c): return c.display
        }
    }

    var combo: KeyCombo? {
        switch self {
        case .none: return nil
        case .preset(let p): return p.combo
        case .custom(let c): return c
        }
    }
}

enum Preset: String, Codable, CaseIterable, Hashable {
    case back, forward, undo, redo, copy, paste, cut, missionControl, appWindows, desktopLeft, desktopRight

    var title: String {
        switch self {
        case .back: return tr("뒤로 가기", "Back")
        case .forward: return tr("앞으로 가기", "Forward")
        case .undo: return tr("실행 취소", "Undo")
        case .redo: return tr("다시 실행", "Redo")
        case .copy: return tr("복사", "Copy")
        case .paste: return tr("붙여넣기", "Paste")
        case .cut: return tr("잘라내기", "Cut")
        case .missionControl: return "Mission Control"
        case .appWindows: return tr("앱 윈도우 보기", "App windows")
        case .desktopLeft: return tr("왼쪽 데스크톱으로", "Desktop left")
        case .desktopRight: return tr("오른쪽 데스크톱으로", "Desktop right")
        }
    }

    var combo: KeyCombo {
        let cmd = CGEventFlags.maskCommand.rawValue
        let shift = CGEventFlags.maskShift.rawValue
        let ctrl = CGEventFlags.maskControl.rawValue
        switch self {
        case .back: return KeyCombo(keyCode: 0x21, modifiers: cmd, display: "⌘[")
        case .forward: return KeyCombo(keyCode: 0x1E, modifiers: cmd, display: "⌘]")
        case .undo: return KeyCombo(keyCode: 0x06, modifiers: cmd, display: "⌘Z")
        case .redo: return KeyCombo(keyCode: 0x06, modifiers: cmd | shift, display: "⇧⌘Z")
        case .copy: return KeyCombo(keyCode: 0x08, modifiers: cmd, display: "⌘C")
        case .paste: return KeyCombo(keyCode: 0x09, modifiers: cmd, display: "⌘V")
        case .cut: return KeyCombo(keyCode: 0x07, modifiers: cmd, display: "⌘X")
        case .missionControl: return KeyCombo(keyCode: 0x7E, modifiers: ctrl, display: "⌃↑")
        case .appWindows: return KeyCombo(keyCode: 0x7D, modifiers: ctrl, display: "⌃↓")
        case .desktopLeft: return KeyCombo(keyCode: 0x7B, modifiers: ctrl, display: "⌃←")
        case .desktopRight: return KeyCombo(keyCode: 0x7C, modifiers: ctrl, display: "⌃→")
        }
    }
}

/// 옆 버튼 하나의 4가지 동작
struct ButtonConfig: Codable, Equatable {
    var hold: UInt64 = 0           // 누르고 있기 → 보조키 (CGEventFlags raw)
    var tap: TapAction = .none     // 톡
    var hold2: UInt64 = 0          // 톡 + 누르고 있기 → 보조키
    var tap2: TapAction = .none    // 톡톡

    var usesDouble: Bool { hold2 != 0 || tap2 != .none }
}

/// 버튼 2개 묶음. buttons[0] = 엄지(위, 4번 칸), buttons[1] = 아래(5번 칸)
struct Profile: Codable, Equatable {
    var buttons: [ButtonConfig]

    static let `default` = Profile(buttons: [
        ButtonConfig(hold: CGEventFlags.maskCommand.rawValue, tap: .preset(.back),
                     hold2: CGEventFlags.maskAlternate.rawValue, tap2: .preset(.forward)),
        ButtonConfig(hold: CGEventFlags.maskShift.rawValue, tap: .preset(.forward)),
    ])
}

struct AppOverride: Codable, Equatable, Identifiable {
    var bundleID: String
    var name: String
    var profile: Profile
    var enabled = true
    var id: String { bundleID }

    init(bundleID: String, name: String, profile: Profile) {
        self.bundleID = bundleID
        self.name = name
        self.profile = profile
    }

    // 예전 설정 파일(enabled 없음)도 읽히게
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        name = try c.decode(String.self, forKey: .name)
        profile = try c.decode(Profile.self, forKey: .profile)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

enum ModifierIndicator: String, Codable, CaseIterable {
    case none, cursorBadge
    var title: String { self == .none ? tr("표시 안 함", "Don't show") : tr("커서 옆에 작은 배지", "Small badge next to the cursor") }
}

struct Settings: Codable, Equatable {
    var base = Profile.default
    var overrides: [AppOverride] = []
    var doubleWindowMs: Int = 250
    var paused = false
    var showPercentInMenuBar = false
    var indicator = ModifierIndicator.none
    var lowBatteryAlert = true
    var lowBatteryThreshold = 20
    /// 완충 시 예상 사용 시간 (마우스를 실제로 움직인 시간 기준). 블루투스 실측으로 자동 보정된다.
    var fullChargeHours: Double = 40
    var diagnosticLog = false
    var showInDock = false
    var language = AppLanguage.system

    init() {}

    // 항목이 빠진 예전 설정 파일도 읽히게: 없는 항목만 기본값으로 채운다
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        base = try c.decodeIfPresent(Profile.self, forKey: .base) ?? d.base
        overrides = try c.decodeIfPresent([AppOverride].self, forKey: .overrides) ?? d.overrides
        doubleWindowMs = try c.decodeIfPresent(Int.self, forKey: .doubleWindowMs) ?? d.doubleWindowMs
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? d.paused
        showPercentInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showPercentInMenuBar) ?? d.showPercentInMenuBar
        indicator = try c.decodeIfPresent(ModifierIndicator.self, forKey: .indicator) ?? d.indicator
        lowBatteryAlert = try c.decodeIfPresent(Bool.self, forKey: .lowBatteryAlert) ?? d.lowBatteryAlert
        lowBatteryThreshold = try c.decodeIfPresent(Int.self, forKey: .lowBatteryThreshold) ?? d.lowBatteryThreshold
        fullChargeHours = try c.decodeIfPresent(Double.self, forKey: .fullChargeHours) ?? d.fullChargeHours
        diagnosticLog = try c.decodeIfPresent(Bool.self, forKey: .diagnosticLog) ?? d.diagnosticLog
        showInDock = try c.decodeIfPresent(Bool.self, forKey: .showInDock) ?? d.showInDock
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? d.language
    }

    func profile(for bundleID: String?) -> Profile {
        guard let id = bundleID, let o = overrides.first(where: { $0.bundleID == id && $0.enabled }) else { return base }
        return o.profile
    }
}

/// 설정 저장소. 바뀌면 바로 파일에 저장하고 알린다.
final class Store: ObservableObject {
    static let shared = Store()
    static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/SideButtons")
    private let url = Store.dir.appendingPathComponent("config.json")

    @Published var settings: Settings {
        didSet { if settings != oldValue { save() } }
    }

    private init() {
        try? FileManager.default.createDirectory(at: Store.dir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: url) {
            do {
                settings = try JSONDecoder().decode(Settings.self, from: data)
            } catch {
                // 읽지 못한 파일은 덮어쓰기 전에 따로 보관
                try? data.write(to: Store.dir.appendingPathComponent("config.broken-\(Int(Date().timeIntervalSince1970)).json"))
                log("설정 파일 읽기 실패, 기본값 사용: \(error)")
                settings = Settings()
            }
        } else {
            settings = Settings()
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(settings) { try? data.write(to: url, options: .atomic) }
    }
}

// MARK: - 기록 파일

let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/SideButtons.log")

/// 항상 남기는 중요한 기록 (시작, 장치 연결, 오류)
func log(_ s: String) {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    let line = "[\(f.string(from: Date()))] \(s)\n"
    // 1MB가 넘으면 예전 기록은 .old 로 옮기고 새로 시작
    if let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path))?[.size] as? Int, size > 1_000_000 {
        let old = logURL.appendingPathExtension("old")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: logURL, to: old)
    }
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile()
        h.write(line.data(using: .utf8)!)
        try? h.close()
    } else {
        try? line.write(to: logURL, atomically: true, encoding: .utf8)
    }
}

/// 진단 모드일 때만 남기는 자세한 기록 (버튼 누를 때마다)
func debugLog(_ s: @autoclosure () -> String) {
    if Store.shared.settings.diagnosticLog { log(s()) }
}
