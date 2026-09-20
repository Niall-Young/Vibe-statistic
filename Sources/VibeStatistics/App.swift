import AppKit
import SwiftUI
import SwiftData

@main enum VibeStatisticsApp {
    static func main() {
        // One-time migration from the development identity, whose menu-bar entry
        // may have been attributed to its launching IDE by macOS Tahoe.
        let defaults = UserDefaults.standard
        if Bundle.main.bundleIdentifier == "com.niallyoung.vibestatistics",
           !defaults.bool(forKey: "migratedDevelopmentIdentity") {
            let legacy = defaults.persistentDomain(forName: "com.vibestatistics.app") ?? [:]
            for (key, value) in legacy where !key.hasPrefix("NSStatusItem") && key != "statusDiagnosticsPath" {
                if defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
            }
            defaults.set(true, forKey: "migratedDevelopmentIdentity")
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var popover = NSPopover()
    var window: NSWindow!
    var store: UsageStore!
    var verifyMode: Bool { CommandLine.arguments.contains("--verify-ui") }
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let support = URL.applicationSupportDirectory.appending(path: "VibeStatistics")
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let configuration = ModelConfiguration(url: support.appending(path: "usage.store"))
            let container = try ModelContainer(for: StoredSnapshot.self, configurations: configuration)
            let helper = Bundle.main.resourceURL!.appending(path: "Helpers/bridge.py")
            guard FileManager.default.fileExists(atPath: helper.path) else { throw CocoaError(.fileNoSuchFile) }
            store = UsageStore(container: container, provider: CLIProvider(helper: helper))
        } catch {
            let alert = NSAlert(); alert.messageText = "Vibe Statistics 无法启动"
            alert.informativeText = "无法打开本地数据库或辅助程序。请使用 scripts/build.sh 重新构建完整 .app。"
            alert.runModal(); NSApp.terminate(nil); return
        }
        (AppTheme(rawValue: UserDefaults.standard.string(forKey: "appTheme") ?? "system") ?? .system).apply()
        if CommandLine.arguments.contains("--dark-preview") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        setupMainMenu()
        // Preserve the user's placement across launches. This does not override
        // macOS Control Center's separate per-application visibility setting.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "VibeStatisticsUsage"
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "Agent 用量")
            button.image?.isTemplate = true
            button.setAccessibilityLabel("Vibe Statistics · Agent 用量")
            button.action = #selector(togglePopover); button.target = self
            button.toolTip = "Vibe Statistics · Agent 用量"
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuView(store: store, openWindow: { [weak self] in self?.showWindow() }))
        popover.contentSize = NSSize(width: 370, height: 630)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 810), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Vibe Statistics"; window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(rootView: MainView(store: store))
        window.minSize = NSSize(width: 820, height: 650); window.center(); if !verifyMode { window.setFrameAutosaveName("MainWindow") }
        window.isReleasedWhenClosed = false; window.delegate = self
        store.start()
        if let path = ProcessInfo.processInfo.environment["VIBE_STATUS_DIAGNOSTICS"] ?? UserDefaults.standard.string(forKey: "statusDiagnosticsPath") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                let button = statusItem.button
                let report: [String: Any] = [
                    "visible": statusItem.isVisible,
                    "length": statusItem.length,
                    "image": button?.image != nil,
                    "imageSize": NSStringFromSize(button?.image?.size ?? .zero),
                    "buttonFrame": NSStringFromRect(button?.frame ?? .zero),
                    "windowFrame": NSStringFromRect(button?.window?.frame ?? .zero),
                    "windowVisible": button?.window?.isVisible ?? false,
                    "screens": NSScreen.screens.map { NSStringFromRect($0.frame) }
                ]
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: URL(fileURLWithPath: path))
                }
            }
        }
        if verifyMode {
            window.orderBack(nil)
            Task { await verifyUI() }
        } else if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            showWindow(); UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
    }
    func setupMainMenu() {
        let menu = NSMenu(); let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 Vibe Statistics", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let summary = appMenu.addItem(withTitle: "显示额度摘要", action: #selector(togglePopover), keyEquivalent: "u"); summary.target = self
        let open = appMenu.addItem(withTitle: "打开主窗口", action: #selector(showWindow), keyEquivalent: "o"); open.target = self
        let settings = appMenu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ","); settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Vibe Statistics", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); editItem.title = "编辑"; let edit = NSMenu(title: "编辑"); editItem.submenu = edit; menu.addItem(editItem)
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let windowItem = NSMenuItem(); windowItem.title = "窗口"
        let windowMenu = NSMenu(title: "窗口"); windowItem.submenu = windowMenu; menu.addItem(windowItem)
        windowMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = menu
    }
    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = statusItem.button {
            store.panelOpened(); popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    @objc func showWindow() {
        popover.performClose(nil); NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); store.panelOpened()
    }
    @objc func showSettings() { store.selection = "settings"; showWindow() }
    func windowWillClose(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if !flag && !popover.isShown { showWindow() }; return true }
    func applicationWillTerminate(_ notification: Notification) { store?.pause(); ProcessRegistry.shared.cancelAll() }

    // Machine-readable geometry and integration verification; visual QA uses the real native window.
    func verifyUI() async {
        let deadline = Date().addingTimeInterval(85)
        while store.active && Date() < deadline { try? await Task.sleep(for: .milliseconds(300)) }
        let directory = ProcessInfo.processInfo.environment["VIBE_VERIFY_DIR"] ?? NSTemporaryDirectory() + "vibe-verification"
        let dir = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func capture(_ view: NSView, _ name: String) {
            view.layoutSubtreeIfNeeded()
            let report: [String: Any] = ["view": name, "width": view.bounds.width, "height": view.bounds.height, "appearance": view.effectiveAppearance.name.rawValue, "note": "Geometry only; use native UI inspection for visual verification."]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]) { try? data.write(to: dir.appending(path: name + ".json")) }
        }
        for (name, appearance) in [("overview-light", NSAppearance.Name.aqua), ("overview-dark", NSAppearance.Name.darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            try? await Task.sleep(for: .seconds(1)); capture(window.contentView!, name)
        }
        window.appearance = NSAppearance(named: .aqua)
        window.setContentSize(NSSize(width: 820, height: 660)); try? await Task.sleep(for: .seconds(1)); capture(window.contentView!, "overview-narrow")
        window.setContentSize(NSSize(width: 1080, height: 810))
        store.selection = "antigravity"; try? await Task.sleep(for: .seconds(1)); capture(window.contentView!, "detail")
        store.selection = "settings"; try? await Task.sleep(for: .seconds(1)); capture(window.contentView!, "settings")
        let menuHost = NSHostingView(rootView: MenuView(store: store, openWindow: {})); menuHost.frame = NSRect(x: 0, y: 0, width: 370, height: 630)
        let panel = NSPanel(contentRect: menuHost.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.contentView = menuHost; panel.orderBack(nil)
        try? await Task.sleep(for: .seconds(1)); capture(menuHost, "menu")
        panel.close()
        let summary: [String: Any] = ["connected": store.connected, "providers": Agent.allCases.map { agent in ["name": agent.rawValue, "metrics": store.snapshots[agent]?.metrics?.count ?? 0, "status": store.errors[agent]?.errorCode ?? "ok"] as [String: Any] }, "storageError": store.storageError ?? "none"]
        if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: dir.appending(path: "verification.json")) }
        NSApp.terminate(nil)
    }
}
