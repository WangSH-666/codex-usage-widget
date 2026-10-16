import AppKit
import SwiftUI
import Combine
import UsageCore

final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let preferences = Preferences()
    private let store = UsageStore()
    private var panel: WidgetPanel!
    private var statusItem: NSStatusItem!
    private var subscriptions = Set<AnyCancellable>()
    private var wakeObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var showing = true
    private var editingSecondaryColor = false
    private let showNotification = Notification.Name("local.codexusage.show")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let identifier = Bundle.main.bundleIdentifier ?? "local.codexusage.widget"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            DistributedNotificationCenter.default().postNotificationName(showNotification, object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        makePanel()
        makeStatusItem()
        applyPreferences()
        preferences.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.applyPreferences() }
        }.store(in: &subscriptions)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(show), name: showNotification, object: nil)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.store.refresh() }
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restoreVisiblePosition() }
        }
        store.interval = preferences.interval
        store.start()
        show()
        if CommandLine.arguments.contains("--ui-check") { runUICheck() }
    }

    private func makePanel() {
        let size = preferences.panelSize
        panel = WidgetPanel(contentRect: NSRect(origin: preferences.restoreOrigin(size: size), size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Codex 用量"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // A native overlay owns dragging; don't depend on SwiftUI's background hit test.
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: WidgetView(store: store, preferences: preferences,
                                                               showMenu: { [weak self] event in self?.openWidgetMenu(with: event) }))
        panel.setAccessibilityLabel("Codex 用量桌面小组件")
    }

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "Codex 用量")
        statusItem.button?.toolTip = "Codex 用量 · 点击管理桌面小组件"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        let main = NSMenu()
        let app = NSMenuItem()
        app.submenu = buildMenu()
        app.submenu?.delegate = self
        main.addItem(app)
        NSApp.mainMenu = main
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let fresh = buildMenu()
        for item in fresh.items { fresh.removeItem(item); menu.addItem(item) }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "Codex 用量")
        let heading = NSMenuItem(title: "Codex 用量  2.0.6", action: nil, keyEquivalent: "")
        heading.isEnabled = false; menu.addItem(heading)
        menu.addItem(item(showing ? "隐藏小组件" : "显示小组件", action: #selector(toggleVisibility), key: "w"))
        menu.addItem(item("立即刷新", action: #selector(refresh), key: "r"))
        menu.addItem(.separator())
        let layout = NSMenu(title: "显示内容")
        for (value, label) in [("quota", "仅剩余额度"), ("tokens", "Token ＋ 剩余额度")] {
            let entry = item(label, action: #selector(setLayout(_:)))
            entry.representedObject = value
            entry.keyEquivalent = value == "quota" ? "1" : "2"
            entry.state = preferences.layout == value ? .on : .off
            layout.addItem(entry)
        }
        menu.addItem(submenu("显示内容", menu: layout))
        let top = item("始终置顶", action: #selector(toggleTopmost))
        top.state = preferences.topmost ? .on : .off
        menu.addItem(top)
        let appearance = NSMenu(title: "外观")
        for (value, label) in [("system", "跟随系统"), ("light", "浅色"), ("dark", "深色")] {
            let entry = item(label, action: #selector(setAppearance(_:)))
            entry.representedObject = value
            entry.state = preferences.appearance == value ? .on : .off
            appearance.addItem(entry)
        }
        menu.addItem(submenu("外观", menu: appearance))
        let colors = NSMenu(title: "圆环颜色")
        for (index, title, color) in [(0, "5小时…", preferences.primaryRingColor), (1, "1周…", preferences.secondaryRingColor)] {
            let entry = item(title, action: #selector(chooseRingColor(_:)))
            entry.tag = index
            entry.image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                color.setStroke()
                let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3))
                circle.lineWidth = 3
                circle.stroke()
                return true
            }
            colors.addItem(entry)
        }
        colors.addItem(.separator())
        colors.addItem(item("恢复默认配色", action: #selector(resetRingColors)))
        colors.addItem(NSMenuItem(title: "≤20% 时显示橙色提醒", action: nil, keyEquivalent: ""))
        menu.addItem(submenu("圆环颜色", menu: colors))
        let frequency = NSMenu(title: "刷新频率")
        for seconds in [10, 30, 60] {
            let entry = item("\(seconds) 秒", action: #selector(setInterval(_:)))
            entry.tag = seconds
            entry.state = preferences.interval == seconds ? .on : .off
            frequency.addItem(entry)
        }
        menu.addItem(submenu("本机统计刷新频率", menu: frequency))
        let opacity = NSMenu(title: "背景不透明度")
        let sliderItem = NSMenuItem()
        sliderItem.view = OpacityMenuView(value: preferences.opacity) { [weak self] value in
            self?.preferences.opacity = value
        }
        opacity.addItem(sliderItem)
        opacity.addItem(.separator())
        for value in [100, 90, 75, 50, 25, 0] {
            let entry = item("\(value)%", action: #selector(setOpacity(_:)))
            entry.tag = value
            entry.state = Int((preferences.opacity * 100).rounded()) == value ? .on : .off
            opacity.addItem(entry)
        }
        menu.addItem(submenu("背景不透明度", menu: opacity))
        menu.addItem(.separator())
        menu.addItem(item("状态与说明…", action: #selector(showDetails)))
        menu.addItem(.separator())
        menu.addItem(item("退出 Codex 用量", action: #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }
    private func submenu(_ title: String, menu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.submenu = menu
        return entry
    }
    private func openWidgetMenu(with event: NSEvent) {
        // Keep the original right-mouse event; changing key-window focus cancels menu tracking.
        NSMenu.popUpContextMenu(buildMenu(), with: event, for: panel.contentView!)
    }
    private func applyPreferences() {
        guard panel != nil else { return }
        let size = preferences.panelSize
        if panel.frame.size != size {
            let oldFrame = panel.frame
            panel.setFrame(NSRect(x: oldFrame.minX, y: oldFrame.maxY - size.height,
                                  width: size.width, height: size.height), display: true)
            restoreVisiblePosition()
        }
        panel.level = preferences.topmost ? .floating : .normal
        panel.alphaValue = 1
        panel.appearance = preferences.appearance == "system" ? nil : NSAppearance(named: preferences.appearance == "dark" ? .darkAqua : .aqua)
        store.interval = preferences.interval
    }
    @objc func show() {
        showing = true
        restoreVisiblePosition()
        panel.orderFrontRegardless()
    }
    @objc private func hide() { showing = false; panel.orderOut(nil) }
    @objc private func toggleVisibility() { showing ? hide() : show() }
    @objc private func refresh() { store.refresh() }
    @objc private func toggleTopmost() { preferences.topmost.toggle() }
    @objc private func setAppearance(_ sender: NSMenuItem) { preferences.appearance = sender.representedObject as? String ?? "system" }
    @objc private func setLayout(_ sender: NSMenuItem) { preferences.layout = sender.representedObject as? String ?? "quota" }
    @objc private func setInterval(_ sender: NSMenuItem) { preferences.interval = sender.tag; store.interval = sender.tag; store.refresh() }
    @objc private func setOpacity(_ sender: NSMenuItem) { preferences.opacity = Double(sender.tag) / 100 }
    @objc private func chooseRingColor(_ sender: NSMenuItem) {
        editingSecondaryColor = sender.tag == 1
        let picker = NSColorPanel.shared
        picker.setTarget(nil)
        picker.title = editingSecondaryColor ? "1周圆环颜色" : "5小时圆环颜色"
        picker.showsAlpha = false
        picker.isContinuous = true
        picker.color = editingSecondaryColor ? preferences.secondaryRingColor : preferences.primaryRingColor
        picker.setTarget(self)
        picker.setAction(#selector(changeRingColor(_:)))
        NSApp.activate(ignoringOtherApps: true)
        picker.makeKeyAndOrderFront(nil)
    }
    @objc private func changeRingColor(_ sender: NSColorPanel) {
        guard let hex = Preferences.hex(from: sender.color) else { return }
        if editingSecondaryColor { preferences.secondaryColorHex = hex }
        else { preferences.primaryColorHex = hex }
    }
    @objc private func resetRingColors() {
        NSColorPanel.shared.orderOut(nil)
        preferences.resetRingColors()
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showDetails() {
        let alert = NSAlert()
        alert.messageText = "Codex 用量"
        let quotaState = store.accountError ?? (store.quotaIsStale ? "额度快照等待更新" : store.quota != nil ? "已连接当前登录账户" : "正在同步")
        let lastRead = store.stats?.scannedAt.formatted(date: .omitted, time: .standard) ?? "尚未完成"
        let quotaRead = store.quota?.fetchedAt.formatted(date: .omitted, time: .standard) ?? "尚未完成"
        alert.informativeText = "账户额度：\(quotaState)\n额度更新：\(quotaRead)\n本机统计：\(store.scanError ?? "正常")\n统计更新：\(lastRead)\n可见会话：\(store.stats?.sessionCount ?? 0) 个\n待确认运行状态：\(store.stats?.uncertainCount ?? 0) 个\n\n过去24小时仅统计本机日志；账户额度覆盖当前账户。M = 百万 tokens。超过15分钟无活动的任务不计入已确认运行数。\n\n只读统计，不调用模型，不读取或保存登录凭据。账户额度每30秒同步，失败10秒后重试。\n\n版本 2.0.6 · 独立桌面卡片"
        alert.addButton(withTitle: "完成")
        alert.addButton(withTitle: "立即刷新")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { store.refresh() }
    }

    func windowDidMove(_ notification: Notification) {
        preferences.saveOrigin(panel.frame.origin)
        recordDragDiagnostic("windowDidMove", window: panel)
    }
    private func restoreVisiblePosition() {
        guard !NSScreen.screens.contains(where: { $0.visibleFrame.contains(panel.frame) }) else { return }
        panel.setFrameOrigin(preferences.restoreOrigin(size: panel.frame.size))
    }
    func applicationWillTerminate(_ notification: Notification) {
        if panel != nil { preferences.saveOrigin(panel.frame.origin) }
        DistributedNotificationCenter.default().removeObserver(self)
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return false
    }

    // Test the actual AppKit window and production view, without screen-recording permission.
    private func runUICheck() {
        Task { @MainActor [self] in
            try? await Task.sleep(for: .seconds(4))
            var checks: [String: Bool] = [:]
            checks["panelSize"] = panel.frame.size == preferences.panelSize
            checks["matchesSystemBatteryCard"] = preferences.cardSize == NSSize(width: 344, height: 164)
            checks["matchesSystemBatteryWindow"] = panel.frame.size == NSSize(width: 360, height: 180)
            checks["noDockIcon"] = NSApp.activationPolicy() == .accessory
            checks["menuBar"] = statusItem.button != nil
            checks["menuActions"] = buildMenu().items.filter { $0.action != nil }.allSatisfy { $0.target != nil }
            hide(); checks["hide"] = !panel.isVisible
            _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
            checks["showOnReopen"] = panel.isVisible
            checks["visibleOnConnectedScreen"] = NSScreen.screens.contains { $0.visibleFrame.contains(panel.frame) }
            let oldTheme = preferences.appearance
            let oldTop = preferences.topmost
            let oldLayout = preferences.layout
            let oldOpacity = preferences.opacity
            let oldPrimaryColor = preferences.primaryColorHex
            let oldSecondaryColor = preferences.secondaryColorHex
            preferences.topmost = true; applyPreferences()
            checks["topmost"] = panel.level == .floating
            preferences.topmost = oldTop
            let output = CommandLine.arguments.drop(while: { $0 != "--ui-check" }).dropFirst().first ?? "/tmp/codex-usage-ui"
            try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
            // Exercise actual view rendering at both opacity endpoints. Foreground must survive 0%.
            preferences.layout = "quota"
            preferences.appearance = "light"
            for percent in [0, 50, 100] {
                preferences.opacity = Double(percent) / 100
                applyPreferences()
                checks["windowOpaqueAt\(percent)"] = panel.alphaValue == 1
                try? await Task.sleep(for: .milliseconds(600))
                if let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    let path = URL(fileURLWithPath: output).appendingPathComponent("background-\(percent).png")
                    if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: path) }
                    checks["background\(percent)Rendered"] = FileManager.default.fileExists(atPath: path.path)
                }
            }
            let suite = "local.codexusage.opacity-check.\(UUID().uuidString)"
            let testDefaults = UserDefaults(suiteName: suite)!
            let isolated = Preferences(defaults: testDefaults)
            checks["defaultBackgroundOpacity"] = isolated.opacity == 1
            isolated.opacity = 0
            checks["zeroOpacityPersists"] = Preferences(defaults: testDefaults).opacity == 0
            isolated.opacity = 0.37
            checks["customOpacityPersists"] = Preferences(defaults: testDefaults).opacity == 0.37
            isolated.primaryColorHex = "00B894"
            isolated.secondaryColorHex = "F06595"
            let reloaded = Preferences(defaults: testDefaults)
            checks["independentColorsPersist"] = reloaded.primaryColorHex == "00B894" && reloaded.secondaryColorHex == "F06595"
            checks["colorRoundTrip"] = Preferences.hex(from: reloaded.primaryRingColor) == "00B894"
            testDefaults.set("invalid", forKey: "primaryRingColor")
            checks["invalidColorFallsBack"] = Preferences(defaults: testDefaults).primaryColorHex == Preferences.defaultPrimaryColor
            isolated.resetRingColors()
            checks["resetColorsPersist"] = Preferences(defaults: testDefaults).primaryColorHex == Preferences.defaultPrimaryColor && Preferences(defaults: testDefaults).secondaryColorHex == Preferences.defaultSecondaryColor
            testDefaults.removePersistentDomain(forName: suite)
            preferences.opacity = oldOpacity
            for layout in ["quota", "tokens"] {
                preferences.layout = layout; applyPreferences()
                checks["\(layout)LayoutSize"] = panel.frame.size == preferences.panelSize
                for theme in ["light", "dark"] {
                    preferences.appearance = theme; applyPreferences()
                    // Let SwiftUI commit geometry and appearance before capturing its real view.
                    try? await Task.sleep(for: .milliseconds(600))
                    panel.contentView?.layoutSubtreeIfNeeded()
                    if let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        let filename = layout == "quota" ? "\(theme).png" : "tokens-\(theme).png"
                        let path = URL(fileURLWithPath: output).appendingPathComponent(filename)
                        if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: path) }
                        checks["\(layout)-\(theme)Rendered"] = FileManager.default.fileExists(atPath: path.path)
                    }
                }
            }
            preferences.layout = "quota"; preferences.appearance = "light"
            preferences.primaryColorHex = "00B894"; preferences.secondaryColorHex = "F06595"
            applyPreferences()
            try? await Task.sleep(for: .milliseconds(600))
            if let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let path = URL(fileURLWithPath: output).appendingPathComponent("custom-colors.png")
                if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: path) }
                checks["customColorsRendered"] = FileManager.default.fileExists(atPath: path.path)
            }
            preferences.primaryColorHex = oldPrimaryColor; preferences.secondaryColorHex = oldSecondaryColor
            preferences.appearance = oldTheme; preferences.layout = oldLayout; preferences.opacity = oldOpacity; applyPreferences()
            let data = try! JSONSerialization.data(withJSONObject: checks, options: [.prettyPrinted, .sortedKeys])
            try? data.write(to: URL(fileURLWithPath: output).appendingPathComponent("checks.json"))
            NSApp.terminate(nil)
        }
    }
}
