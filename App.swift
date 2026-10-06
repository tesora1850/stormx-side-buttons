// 상단바 아이콘과 메뉴, 설정 창, 로그인 시 자동 실행, 보조키 배지

import AppKit
import SwiftUI
import ServiceManagement
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let badge = ModifierBadge()
    private var cancellables: Set<AnyCancellable> = []
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        let engine = Engine.shared
        engine.onStatusChange = { [weak self] in self?.updateStatusItem() }
        engine.onActivity = { _ in Battery.shared.noteActivity() }
        Battery.shared.onChange = { [weak self] in self?.updateStatusItem() }
        Modifiers.onChange = { [weak self] held in self?.badge.update(held) }
        onMouseMoved = { [weak self] p in self?.badge.follow(cgPoint: p) }
        BLEBattery.shared.onReading = { Battery.shared.bluetoothReading($0) }
        engine.start()

        Store.shared.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] s in
                if s.paused { Engine.shared.releaseAll("잠시 끄기") }
                self?.updateStatusItem(s)
                self?.updateDockPolicy(s)
                self?.settingsWindow?.title = tr("SideButtons 설정", "SideButtons Settings")
            }
            .store(in: &cancellables)

        setupLoginItemOnFirstRun()
        handleTerminationSignals()
        updateStatusItem()
    }

    /// 이미 켜져 있을 때 응용 프로그램 폴더에서 다시 실행하면 설정 창을 연다
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        Engine.shared.releaseAll("종료")
    }

    /// 종료 신호를 받아도 보조키를 풀고 끝냄
    private func handleTerminationSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            s.setEventHandler { Engine.shared.releaseAll("종료 신호"); exit(0) }
            s.resume()
            signalSources.append(s)
        }
    }

    // MARK: 상단바

    private func updateStatusItem(_ s: Settings = Store.shared.settings) {
        guard let button = statusItem?.button else { return }
        let symbol = s.paused ? "computermouse" : "computermouse.fill"
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "SideButtons")
        img?.isTemplate = true
        button.image = img
        button.imagePosition = .imageLeading
        button.title = s.showPercentInMenuBar ? " " + Battery.shared.shortText : ""
        button.appearsDisabled = s.paused
    }

    private var connectionText: String {
        let e = Engine.shared
        if e.connected.contains(.bluetooth) { return tr("연결: 블루투스", "Bluetooth") }
        if e.connected.contains(.receiver) {
            if let a = e.lastActivity, a.kind == .receiver, Date().timeIntervalSince(a.at) < 600 {
                return tr("연결: 수신기 (사용 중)", "Receiver (in use)")
            }
            return tr("연결: 수신기 (마우스 대기 중)", "Receiver (mouse idle)")
        }
        return tr("연결: 마우스 없음", "No mouse")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        Battery.shared.refreshBluetooth()
        menu.removeAllItems()
        let s = Store.shared.settings

        if !Engine.shared.hasPermissions {
            menu.addItem(item(tr("⚠️ 권한 필요 — 시스템 설정 열기", "⚠️ Permission needed — open System Settings"), #selector(openPrivacy)))
            menu.addItem(.separator())
        }
        menu.addItem(info(connectionText))
        menu.addItem(info(Battery.shared.menuText))
        if let hint = Battery.shared.hintText { menu.addItem(info(hint, small: true)) }
        if Battery.shared.livePercent == nil {
            menu.addItem(item(tr("충전했어요", "I charged it"), #selector(markCharged)))
        }
        menu.addItem(.separator())

        let pause = item(tr("잠시 끄기", "Pause"), #selector(togglePause))
        pause.state = s.paused ? .on : .off
        menu.addItem(pause)
        let login = item(tr("로그인 시 자동 실행", "Open at login"), #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        menu.addItem(item(tr("설정…", "Settings…"), #selector(openSettings), key: ","))
        menu.addItem(item(tr("SideButtons 종료", "Quit SideButtons"), #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func info(_ title: String, small: Bool = false) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        if small {
            i.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        }
        return i
    }

    // MARK: 메뉴 동작

    @objc private func togglePause() { Store.shared.settings.paused.toggle() }

    @objc private func markCharged() { Battery.shared.markCharged() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            log("로그인 항목 변경 실패: \(error)")
            let alert = NSAlert()
            alert.messageText = tr("로그인 시 자동 실행을 바꾸지 못했어요", "Couldn't change Open at login")
            alert.informativeText = tr("시스템 설정 → 일반 → 로그인 항목에서 SideButtons를 직접 켜고 꺼주세요.\n\n(\(error.localizedDescription))", "Please turn SideButtons on or off in System Settings → General → Login Items.\n\n(\(error.localizedDescription))")
            alert.runModal()
        }
    }

    private func setupLoginItemOnFirstRun() {
        let key = "didSetupLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        do {
            try SMAppService.mainApp.register()
            log("로그인 항목 등록")
        } catch {
            log("로그인 항목 등록 실패: \(error)")
        }
    }

    @objc private func openPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = tr("SideButtons 설정", "SideButtons Settings")
            w.contentView = FirstMouseHostingView(rootView: SettingsView())
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            settingsWindow = w
        }
        // 설정 창이 열려 있는 동안은 Dock과 ⌘Tab에 보이게
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { self.updateDockPolicy() }
    }

    /// 평소엔 상단바 전용(Dock·⌘Tab에 안 보임). 설정에서 '항상 Dock에 표시'를 켜면 계속 보인다.
    private func updateDockPolicy(_ s: Settings = Store.shared.settings) {
        let windowOpen = settingsWindow?.isVisible ?? false
        let want: NSApplication.ActivationPolicy = (s.showInDock || windowOpen) ? .regular : .accessory
        if NSApp.activationPolicy() != want { NSApp.setActivationPolicy(want) }
    }

    @objc private func quit() {
        Engine.shared.releaseAll("종료")
        NSApp.terminate(nil)
    }
}

// MARK: - 보조키 배지 (커서 옆에 ⌘ 같은 작은 표시)

final class ModifierBadge {
    private lazy var panel: NSPanel = {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 40, height: 22),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.animationBehavior = .none
        let bg = NSView()
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        bg.layer?.cornerRadius = 6
        label.font = .systemFont(ofSize: 13, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
        ])
        p.contentView = bg
        return p
    }()
    private let label = NSTextField(labelWithString: "")

    func update(_ held: CGEventFlags) {
        guard Store.shared.settings.indicator == .cursorBadge, !held.isEmpty else {
            panel.orderOut(nil)
            return
        }
        label.stringValue = Modifiers.symbols(held)
        let width = CGFloat(18 + 14 * label.stringValue.count)
        panel.setContentSize(NSSize(width: width, height: 22))
        follow()
        panel.orderFrontRegardless()
    }

    func follow() {
        guard panel.isVisible else { return }
        place(at: NSEvent.mouseLocation)
    }

    /// 이벤트 탭이 받은 커서 위치로 바로 옮김 (NSEvent.mouseLocation 보다 한 박자 빠르다)
    func follow(cgPoint p: CGPoint) {
        guard panel.isVisible, let h = NSScreen.screens.first?.frame.height else { return }
        place(at: NSPoint(x: p.x, y: h - p.y))   // CG 좌표(위가 0) → 화면 좌표(아래가 0)
    }

    private func place(at p: NSPoint) {
        panel.setFrameOrigin(NSPoint(x: p.x + 14, y: p.y - 34))
    }
}

/// 창이 뒤에 있을 때 첫 클릭이 창 활성화로만 쓰이고 버려지지 않게
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
