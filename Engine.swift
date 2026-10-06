// 버튼 엔진: 마우스 원본 신호 읽기 → 옆 버튼 제스처 판단 → 보조키/단축키 보내기
//
// 왜 원본 신호를 읽나: 이 마우스(수신기 0x248a:0x8566, 블루투스 0x248a:0x8266)는 HID 디스크립터에
// "버튼 1~3"만 선언하고 실제로는 버튼 비트를 5칸 보낸다. 맥은 선언 안 된 4·5번 칸(0x08, 0x10)을
// 버리므로, IOHIDDeviceRegisterInputReportCallback 으로 원본 리포트를 직접 읽는다.

import AppKit
import IOKit.hid
import CoreGraphics

let mouseVendorID = 0x248a
let receiverProductID = 0x8566
let bluetoothProductID = 0x8266

enum ConnectionKind: String { case receiver = "수신기", bluetooth = "블루투스" }

// MARK: - 키 보내기

let eventSource = CGEventSource(stateID: .privateState)
/// 우리가 보낸 이벤트 표시 (이벤트 탭에서 구분용)
let ourMarker: Int64 = 0x51DEB7

func postOurs(_ e: CGEvent?) {
    e?.setIntegerValueField(.eventSourceUserData, value: ourMarker)
    e?.post(tap: .cghidEventTap)
}

func pressShortcut(_ c: KeyCombo) {
    let flags = CGEventFlags(rawValue: c.modifiers).union(Modifiers.held)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: eventSource, virtualKey: c.keyCode, keyDown: down)
        e?.flags = Modifiers.withDeviceBits(flags)
        postOurs(e)
    }
}

// MARK: - 보조키 누르고 있기

enum Modifiers {
    /// 옆 버튼으로 지금 누르고 있는 보조키 합
    static var held: CGEventFlags = []
    /// 실제 키보드로 누르고 있는 보조키. 맥에 물어보면 우리가 보낸 가짜 키까지 섞여 나와서 이벤트 탭에서 직접 추적한다.
    static var physical: CGEventFlags = []
    static let mask: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift, .maskControl]
    static let all: [CGEventFlags] = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
    static var onChange: ((CGEventFlags) -> Void)?

    static func keyCode(for flag: CGEventFlags) -> CGKeyCode {
        switch flag {
        case .maskCommand: return 0x37
        case .maskAlternate: return 0x3A
        case .maskShift: return 0x38
        default: return 0x3B // control
        }
    }

    static func symbols(_ f: CGEventFlags) -> String {
        (f.contains(.maskControl) ? "⌃" : "") + (f.contains(.maskAlternate) ? "⌥" : "")
            + (f.contains(.maskShift) ? "⇧" : "") + (f.contains(.maskCommand) ? "⌘" : "")
    }

    /// 왼쪽 키 구분 비트 (NX_DEVICEL*KEYMASK). 이게 있어야 앱들이 진짜 키보드 보조키처럼 인식한다.
    static func withDeviceBits(_ f: CGEventFlags) -> CGEventFlags {
        var raw = f.rawValue
        if f.contains(.maskControl) { raw |= 0x01 }
        if f.contains(.maskShift) { raw |= 0x02 }
        if f.contains(.maskCommand) { raw |= 0x08 }
        if f.contains(.maskAlternate) { raw |= 0x20 }
        return CGEventFlags(rawValue: raw)
    }

    /// 시스템(다른 앱들)에 실제로 "눌렀다"고 알린 보조키
    static var announced: CGEventFlags = []
    private static var pendingAnnounce: DispatchWorkItem?

    /// 옆 버튼 보조키 변경.
    /// 누를 때는 바로 알리지 않는다: 이벤트 탭이 클릭·휠·키에는 즉시 보조키를 붙이므로 동작은 같고,
    /// 짧은 톡에서 ⌥ 같은 보조키가 혼자 눌렸다 떼지는 일(예: Claude의 "⌥ 두 번" 단축키 오작동)을 막는다.
    /// 0.3초 넘게 누르고 있거나 그 사이 다른 입력이 오면 그때 알린다 (로직의 ⌘ 커서 모양용).
    static func set(_ newHeld: CGEventFlags) {
        held = newHeld
        let removed = announced.subtracting(newHeld)
        if !removed.isEmpty { announce(announced.intersection(newHeld)) }
        if newHeld.isSubset(of: announced) {
            pendingAnnounce?.cancel(); pendingAnnounce = nil
            return
        }
        pendingAnnounce?.cancel()
        let work = DispatchWorkItem { announce(held) }
        pendingAnnounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + tapMaxDuration, execute: work)
    }

    /// 다른 입력이 들어왔을 때 (이벤트 탭에서) — 아직 안 알린 보조키를 바로 알린다
    static func announceNowIfNeeded() {
        guard held != announced else { return }
        pendingAnnounce?.cancel(); pendingAnnounce = nil
        DispatchQueue.main.async { announce(held) }
    }

    private static func announce(_ target: CGEventFlags) {
        let old = announced
        announced = target
        for flag in all where old.contains(flag) != target.contains(flag) {
            let e = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode(for: flag),
                            keyDown: target.contains(flag))
            e?.type = .flagsChanged
            e?.flags = withDeviceBits(target.union(physical))
            postOurs(e)
        }
        if old != target { onChange?(target) }
    }
}

// MARK: - 이벤트 탭: 다른 키보드·마우스 이벤트에 눌린 보조키를 덧붙임

var eventTap: CFMachPort?
var activityWhileHeld = false
/// 커서가 움직일 때 불림 (보조키 배지가 커서를 따라가게)
var onMouseMoved: ((CGPoint) -> Void)?

let tapTypes: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
                               .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
                               .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                               .scrollWheel, .mouseMoved]

let tapCallback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = eventTap { CGEvent.tapEnable(tap: t, enable: true) }
        log("event tap re-enabled")
        return Unmanaged.passUnretained(event)
    }
    guard event.getIntegerValueField(.eventSourceUserData) != ourMarker else {
        return Unmanaged.passUnretained(event)
    }
    switch type {
    case .flagsChanged: Modifiers.physical = event.flags.intersection(Modifiers.mask)
    case .keyUp: break
    case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
        if !Modifiers.held.isEmpty { onMouseMoved?(event.location) }
        if type != .mouseMoved { activityWhileHeld = true }
    default: activityWhileHeld = true
    }
    if !Modifiers.held.isEmpty {
        if type != .mouseMoved && type != .keyUp && type != .flagsChanged { Modifiers.announceNowIfNeeded() }
        // 커서 이동에도 붙여야 로직 같은 앱이 ⌘ 커서 모양을 유지한다
        event.flags = event.flags.union(Modifiers.withDeviceBits(Modifiers.held))
    }
    return Unmanaged.passUnretained(event)
}

// MARK: - 옆 버튼 제스처
//
// 버튼 하나에 4가지: 누르고 있기(hold) / 톡(tap) / 톡+누르고 있기(hold2) / 톡톡(tap2)
// 누르고 있기는 누르는 순간 바로 걸고, 톡은 톡톡일 수 있으니 톡톡 간격만큼 기다린 뒤 실행.

enum Phase { case idle, firstDown, waitingSecond, secondDown }

final class SideButton {
    let mask: UInt8
    let index: Int
    var phase = Phase.idle
    var config = ButtonConfig()   // 첫 번째 누름 때 정해서 제스처가 끝날 때까지 유지
    var pressedAt = Date()
    var active: CGEventFlags = []
    var pending: DispatchWorkItem?
    init(mask: UInt8, index: Int) { self.mask = mask; self.index = index }
    var name: String { index == 0 ? "엄지(위)" : "아래" }
}

let tapMaxDuration: TimeInterval = 0.3

final class Engine {
    static let shared = Engine()

    let buttons = [SideButton(mask: 0x08, index: 0), SideButton(mask: 0x10, index: 1)]
    private var manager: IOHIDManager?
    private var deviceStates: [DeviceState] = []

    /// 지금 연결된 장치 종류
    private(set) var connected: Set<ConnectionKind> = []
    /// 마지막으로 신호가 들어온 장치와 시각
    private(set) var lastActivity: (kind: ConnectionKind, at: Date)?
    var onStatusChange: (() -> Void)?
    /// 마우스에서 신호가 올 때마다 (배터리 사용 시간 계산용)
    var onActivity: ((ConnectionKind) -> Void)?

    var paused: Bool { Store.shared.settings.paused }

    // MARK: 시작

    func start() {
        log("SideButtons start")
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            log("입력 모니터링 권한 없음 → 요청")
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        if !CGPreflightPostEventAccess() {
            log("손쉬운 사용 권한 없음 → 요청")
            CGRequestPostEventAccess()
        }
        installEventTap()
        openHID()
    }

    var hasPermissions: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted && CGPreflightPostEventAccess()
    }

    private func installEventTap() {
        let mask = tapTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: tapCallback, userInfo: nil) else {
            log("event tap 생성 실패 (손쉬운 사용 권한 확인)")
            return
        }
        eventTap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func openHID() {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = m
        IOHIDManagerSetDeviceMatching(m, [
            kIOHIDVendorIDKey: mouseVendorID,
            kIOHIDPrimaryUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDPrimaryUsageKey: kHIDUsage_GD_Mouse,
        ] as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(m, { _, _, _, device in
            Engine.shared.deviceAdded(device)
        }, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { _, _, _, device in
            Engine.shared.deviceRemoved(device)
        }, nil)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        log("HID open: \(r == kIOReturnSuccess ? "OK" : String(format: "0x%X", r))")
    }

    // MARK: 장치

    private func kind(of device: IOHIDDevice) -> ConnectionKind? {
        let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        switch pid {
        case receiverProductID: return .receiver
        case bluetoothProductID: return .bluetooth
        default:
            let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
            return transport.lowercased().contains("bluetooth") ? .bluetooth : .receiver
        }
    }

    private func deviceAdded(_ device: IOHIDDevice) {
        guard let k = kind(of: device) else { return }
        let st = DeviceState(kind: k, device: device)
        deviceStates.append(st)
        IOHIDDeviceRegisterInputReportCallback(device, st.buffer, 64, reportCallback,
                                               Unmanaged.passUnretained(st).toOpaque())
        connected.insert(k)
        log("장치 연결: \(k.rawValue)")
        if k == .bluetooth { BLEBattery.shared.start() }
        onStatusChange?()
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        // 맥에 등록해 둔 신호 받는 곳을 먼저 해제한 뒤에 메모리를 치운다 (해제된 메모리로 신호가 오지 않게)
        for st in deviceStates where st.device == device {
            IOHIDDeviceRegisterInputReportCallback(device, st.buffer, 64, nil, nil)
        }
        deviceStates.removeAll { $0.device == device }
        let hadBluetooth = connected.contains(.bluetooth)
        connected = Set(deviceStates.map(\.kind))
        if hadBluetooth && !connected.contains(.bluetooth) { BLEBattery.shared.stop() }
        log("장치 분리 (남은 장치: \(connected.map(\.rawValue)))")
        releaseAll("장치 분리")
        onStatusChange?()
    }

    // MARK: 리포트

    fileprivate func handle(_ st: DeviceState, report: UnsafeMutablePointer<UInt8>, length: Int, reportID: UInt32) {
        let off = (length > 0 && report[0] == UInt8(truncatingIfNeeded: reportID)) ? 1 : 0
        // 마우스 리포트만 (버튼1 + XY 4 + 휠1 + 가로휠1). 수신기의 시스템/미디어 리포트는 짧다.
        guard length - off >= 6 else { return }

        let wasActive = lastActivity?.kind
        lastActivity = (st.kind, Date())
        onActivity?(st.kind)
        if wasActive != st.kind { onStatusChange?() }

        let bits = report[off]
        guard bits != st.lastButtons else { return }
        let changed = bits ^ st.lastButtons
        st.lastButtons = bits
        debugLog("\(st.kind.rawValue) buttons=\(String(bits, radix: 2))")
        guard !paused else { return }
        for b in buttons where changed & b.mask != 0 {
            handleSideButton(b, down: bits & b.mask != 0)
        }
    }

    // MARK: 제스처

    private func recomputeHeld() {
        Modifiers.set(buttons.reduce(CGEventFlags()) { $0.union($1.active) })
    }

    private func handleSideButton(_ b: SideButton, down: Bool) {
        let now = Date()
        if down {
            activityWhileHeld = false
            if b.phase == .waitingSecond {
                b.pending?.cancel(); b.pending = nil
                b.phase = .secondDown
                b.active = CGEventFlags(rawValue: b.config.hold2 != 0 ? b.config.hold2 : b.config.hold)
            } else {
                let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                b.config = Store.shared.settings.profile(for: front).buttons[b.index]
                b.phase = .firstDown
                b.active = CGEventFlags(rawValue: b.config.hold)
            }
            b.pressedAt = now
            recomputeHeld()
            debugLog("  \(b.name) down (\(b.phase)) → \(Modifiers.symbols(Modifiers.held))")
            return
        }

        let dur = now.timeIntervalSince(b.pressedAt)
        let short = dur < tapMaxDuration && !activityWhileHeld
        b.active = []
        recomputeHeld()
        debugLog(String(format: "  %@ up after %.0fms short=%@", b.name, dur * 1000, "\(short)"))

        switch b.phase {
        case .firstDown where short && b.config.usesDouble:
            b.phase = .waitingSecond
            let work = DispatchWorkItem { [weak b] in
                guard let b else { return }
                b.phase = .idle; b.pending = nil
                if let c = b.config.tap.combo { debugLog("  \(b.name) → 톡 \(c.display)"); pressShortcut(c) }
            }
            b.pending = work
            let window = Double(Store.shared.settings.doubleWindowMs) / 1000
            DispatchQueue.main.asyncAfter(deadline: .now() + window, execute: work)
        case .firstDown where short:
            b.phase = .idle
            if let c = b.config.tap.combo { debugLog("  \(b.name) → 톡 \(c.display)"); pressShortcut(c) }
        case .secondDown where short:
            b.phase = .idle
            if let c = b.config.tap2.combo { debugLog("  \(b.name) → 톡톡 \(c.display)"); pressShortcut(c) }
        default:
            b.phase = .idle
        }
    }

    /// 눌려 있던 보조키를 모두 뗌 (⌘이 눌린 채 멈추는 사고 방지)
    func releaseAll(_ why: String) {
        for b in buttons { b.pending?.cancel(); b.pending = nil; b.phase = .idle; b.active = [] }
        guard !Modifiers.held.isEmpty else { return }
        recomputeHeld()
        log("보조키 모두 해제 (\(why))")
    }
}

final class DeviceState {
    let kind: ConnectionKind
    let device: IOHIDDevice
    var lastButtons: UInt8 = 0
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    init(kind: ConnectionKind, device: IOHIDDevice) { self.kind = kind; self.device = device }
    deinit { buffer.deallocate() }
}

private let reportCallback: IOHIDReportCallback = { context, _, _, _, reportID, report, length in
    let st = Unmanaged<DeviceState>.fromOpaque(context!).takeUnretainedValue()
    Engine.shared.handle(st, report: report, length: length, reportID: reportID)
}
