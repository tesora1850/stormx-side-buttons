// 배터리: 블루투스일 때는 마우스에 직접 물어본 실제 잔량을 쓰고, 수신기일 때는 사용 시간으로 추정한다.
//
// 수신기(0x8566)는 표준 배터리 정보가 없고, 제조사 전용 리포트 5번은 명령 없이 읽으면 의미 없는 값만 나온다.
// 그래서 "마지막으로 확인한 잔량 - 그 뒤 실제로 마우스를 쓴 시간 × 시간당 소모율"로 추정한다.
// 시간당 소모율은 처음엔 설정의 '완충 시 예상 사용 시간'으로 정하고, 블루투스 실측이 들어올 때마다 학습한다.

import Foundation
import UserNotifications

struct BatteryState: Codable {
    var knownPercent: Double?
    var knownAt: Date?
    var knownFromCharge = false
    var activeSecondsSinceKnown: Double = 0
    var learnedDrainPerHour: Double?
    var alertedThisCycle = false
}

final class Battery {
    static let shared = Battery()
    private let url = Store.dir.appendingPathComponent("battery.json")
    private(set) var state = BatteryState()
    /// 블루투스로 지금 읽은 값 (블루투스 연결 중일 때만)
    private(set) var livePercent: Int?
    private var lastTick: Date?
    var onChange: (() -> Void)?

    private init() {
        if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(BatteryState.self, from: d) {
            state = s
        }
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.periodic() }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
            log("알림 권한: \(ok)")
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(state) { try? d.write(to: url, options: .atomic) }
    }

    // MARK: 사용 시간 쌓기

    /// 마우스 신호가 올 때마다. 1분 넘게 쉬었다가 다시 쓰면 쉰 시간은 빼고 센다.
    func noteActivity() {
        let now = Date()
        if let last = lastTick {
            let gap = now.timeIntervalSince(last)
            if gap < 60 { state.activeSecondsSinceKnown += gap }
        }
        lastTick = now
    }

    private func periodic() {
        refreshBluetooth()
        save()
        checkAlert()
        onChange?()
    }

    // MARK: 계산

    var drainPerHour: Double {
        state.learnedDrainPerHour ?? 100 / max(Store.shared.settings.fullChargeHours, 1)
    }

    var activeHours: Double { state.activeSecondsSinceKnown / 3600 }

    var estimatedPercent: Double? {
        guard let p = state.knownPercent else { return nil }
        return max(0, p - drainPerHour * activeHours)
    }

    /// 상단바 옆 숫자
    var shortText: String {
        if let live = livePercent { return "\(live)%" }
        if let e = estimatedPercent { return "~\(Int(e.rounded()))%" }
        return "?"
    }

    /// 메뉴에 보이는 설명
    var menuText: String {
        if let live = livePercent { return tr("배터리 \(live)% (블루투스 실측)", "Battery \(live)% (Bluetooth)") }
        guard let e = estimatedPercent else { return tr("배터리: 아직 모름", "Battery: unknown yet") }
        let h = activeHours < 1 ? tr("1시간 미만", "under 1 h") : tr("\(Int(activeHours))시간", "\(Int(activeHours)) h")
        let since = state.knownFromCharge ? tr("충전 후", "since charge") : tr("마지막 확인 후", "since last reading")
        return tr("배터리 약 \(Int(e.rounded()))% (추정 · \(since) \(h) 사용)", "Battery ~\(Int(e.rounded()))% (estimate · \(h) of use \(since))")
    }

    var hintText: String? {
        if livePercent != nil { return nil }
        if state.knownPercent == nil { return tr("블루투스로 한 번 연결하거나 '충전했어요'를 눌러주세요", "Connect once via Bluetooth or press 'I charged it'") }
        return nil
    }

    // MARK: 블루투스 실측 (BLEBattery 가 마우스에 직접 물어본 값)

    /// 블루투스 배터리 다시 읽기 요청
    func refreshBluetooth() {
        BLEBattery.shared.refresh()
    }

    /// 블루투스에서 값이 들어왔을 때 (nil = 블루투스 끊김)
    func bluetoothReading(_ reading: Int?) {
        let changed = reading != livePercent
        livePercent = reading
        if changed { onChange?() }
        guard let r = reading else { return }
        let rp = Double(r)
        if let p0 = state.knownPercent {
            let h = activeHours
            let drop = p0 - rp
            if h >= 1, drop >= 3 {
                let rate = drop / h
                state.learnedDrainPerHour = state.learnedDrainPerHour.map { 0.5 * $0 + 0.5 * rate } ?? rate
                log(String(format: "배터리 학습: %.0f%% → %.0f%% (%.1f시간) → 시간당 %.2f%%", p0, rp, h,
                           state.learnedDrainPerHour!))
            } else if abs(drop) < 3 && h < 1 {
                return  // 변화가 작으면 기준점을 유지해서 학습 구간을 길게 가져간다
            }
        }
        if rp > Double(Store.shared.settings.lowBatteryThreshold) { state.alertedThisCycle = false }
        state.knownPercent = rp
        state.knownAt = Date()
        state.knownFromCharge = false
        state.activeSecondsSinceKnown = 0
        save()
        checkAlert()
    }

    // MARK: 충전 / 알림

    func markCharged() {
        state.knownPercent = 100
        state.knownAt = Date()
        state.knownFromCharge = true
        state.activeSecondsSinceKnown = 0
        state.alertedThisCycle = false
        save()
        log("충전했어요 → 추정 초기화")
        onChange?()
    }

    func checkAlert() {
        let s = Store.shared.settings
        guard s.lowBatteryAlert, !state.alertedThisCycle else { return }
        let threshold = Double(s.lowBatteryThreshold)
        if let live = livePercent {
            guard Double(live) <= threshold else { return }
            notify(tr("마우스 배터리 \(live)%", "Mouse battery \(live)%"), tr("배터리가 얼마 안 남았어요. 충전해 주세요.", "Battery is low. Please charge your mouse."))
        } else if let e = estimatedPercent {
            guard e <= threshold else { return }
            let h = Int(activeHours.rounded())
            notify(tr("마우스 배터리가 거의 바닥났을 수 있어요", "Your mouse battery may be almost empty"),
                   tr("수신기로 약 \(h)시간 썼어요 (추정 \(Int(e.rounded()))%). 충전했다면 메뉴에서 '충전했어요'를 눌러주세요. "
                   + "정확한 잔량은 블루투스로 잠깐 바꾸면 확인할 수 있어요.",
                   "You've used it about \(h) h on the receiver (estimated \(Int(e.rounded()))%). If you charged it, choose 'I charged it' in the menu. "
                   + "Switch to Bluetooth briefly to see the exact level."))
        } else {
            return
        }
        state.alertedThisCycle = true
        save()
    }

    private func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        log("알림: \(title)")
    }
}
