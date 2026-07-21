import AppKit
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static var shared: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        shared = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private var statusItem: NSStatusItem!
    private var stateMenuItem: NSMenuItem!
    private var axMenuItem: NSMenuItem!
    private let hotkey = HotkeyController()
    private let controller = DictationController()
    private var hotkeyActive = false
    private var currentHotkey = Hotkey.saved
    private var currentMode = ActivationMode.saved
    private var sessionLocked = false
    private var permissionPollTimer: Timer?
    private var modelMenuItem: NSMenuItem!
    private var polishMenuItem: NSMenuItem!
    private var modelStatus = "Model: loading…"
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var recentMenu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        controller.onStateChange = { [weak self] state in self?.render(state: state) }
        controller.onModelStatus = { [weak self] status in self?.modelStatus = status }
        controller.warmUpModel()
        hotkey.hotkey = currentHotkey
        hotkey.onPress = { [weak self] in
            guard let self else { return }
            if self.controller.state == .idle {
                self.sessionLocked = false
                self.controller.beginDictation()
            } else {
                // Stops a toggle-mode or hands-free-locked session.
                self.sessionLocked = false
                self.controller.endDictation()
            }
        }
        hotkey.onRelease = { [weak self] in
            guard let self, self.currentMode == .hold, !self.sessionLocked else { return }
            self.controller.endDictation()
        }
        hotkey.onLock = { [weak self] in
            guard let self, self.currentMode == .hold,
                  self.controller.state == .recording, !self.sessionLocked else { return }
            self.sessionLocked = true
            self.controller.showHandsFreeLock()
        }
        startHotkey()
        render(state: .idle)
    }

    private func startHotkey() {
        hotkeyActive = hotkey.start()
        if !hotkeyActive {
            Permissions.promptForAccessibility()
            startPermissionPolling()
        } else {
            stopPermissionPolling()
        }
        rebuildMenu()
    }

    // The tap can only be created after Accessibility is granted, and macOS
    // doesn't notify us of the grant — poll and activate as soon as it lands.
    private func startPermissionPolling() {
        guard permissionPollTimer == nil else { return }
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, !self.hotkeyActive, Permissions.accessibilityGranted else { return }
            if self.hotkey.start() {
                self.hotkeyActive = true
                self.stopPermissionPolling()
                self.rebuildMenu()
            }
        }
    }

    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    @objc private func retryHotkey() { startHotkey() }
    @objc private func openAccessibilitySettings() { Permissions.openAccessibilityPane() }
    @objc private func openInputMonitoringSettings() { Permissions.openInputMonitoringPane() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func selectHotkey(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let selected = Hotkey(rawValue: raw)
        else { return }
        currentHotkey = selected
        selected.save()
        hotkey.hotkey = selected
        rebuildMenu()
    }

    @objc private func openSettings() {
        presentWindow(
            &settingsWindow,
            title: "Dictator Settings",
            view: SettingsView(store: .shared)
        )
    }

    @objc private func openHistory() {
        presentWindow(
            &historyWindow,
            title: "Dictation History",
            view: HistoryView(store: .shared)
        )
    }

    private func presentWindow(_ window: inout NSWindow?, title: String, view: some View) {
        if window == nil {
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 440),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            created.title = title
            created.isReleasedWhenClosed = false
            created.contentView = NSHostingView(rootView: view)
            created.center()
            window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let selected = ActivationMode(rawValue: raw)
        else { return }
        currentMode = selected
        selected.save()
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let verb = currentMode == .hold ? "hold" : "tap"
        menu.addItem(disabledItem("Dictator — \(verb) \(currentHotkey.title) to dictate"))
        stateMenuItem = disabledItem("State: idle")
        menu.addItem(stateMenuItem)
        axMenuItem = disabledItem("Accessibility: …")
        menu.addItem(axMenuItem)
        modelMenuItem = disabledItem(modelStatus)
        menu.addItem(modelMenuItem)
        polishMenuItem = disabledItem(controller.polishStatus)
        menu.addItem(polishMenuItem)
        menu.addItem(.separator())
        let hotkeyItem = NSMenuItem(title: "Hotkey", action: nil, keyEquivalent: "")
        let hotkeyMenu = NSMenu()
        for option in Hotkey.allCases {
            let item = actionItem(option.title, #selector(selectHotkey(_:)))
            item.representedObject = option.rawValue
            item.state = option == currentHotkey ? .on : .off
            hotkeyMenu.addItem(item)
        }
        hotkeyItem.submenu = hotkeyMenu
        menu.addItem(hotkeyItem)
        let modeItem = NSMenuItem(title: "Activation", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for option in ActivationMode.allCases {
            let item = actionItem(option.title, #selector(selectMode(_:)))
            item.representedObject = option.rawValue
            item.state = option == currentMode ? .on : .off
            modeMenu.addItem(item)
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)
        menu.addItem(.separator())
        let recentItem = NSMenuItem(title: "Recent Dictations", action: nil, keyEquivalent: "")
        recentMenu = NSMenu()
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)
        menu.addItem(actionItem("Settings…", #selector(openSettings), key: ","))
        menu.addItem(actionItem("History…", #selector(openHistory)))
        menu.addItem(.separator())
        if !hotkeyActive {
            menu.addItem(disabledItem("⚠️ Hotkey inactive — activates itself once permission is granted"))
            menu.addItem(actionItem("Open Accessibility Settings", #selector(openAccessibilitySettings)))
            menu.addItem(actionItem("Open Input Monitoring Settings", #selector(openInputMonitoringSettings)))
            menu.addItem(actionItem("Retry Hotkey Listener", #selector(retryHotkey), key: "r"))
            menu.addItem(.separator())
        }
        menu.addItem(actionItem("Quit Dictator", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        axMenuItem?.title = Permissions.accessibilityGranted
            ? "Accessibility: granted ✓"
            : "Accessibility: not granted ✗"
        modelMenuItem?.title = modelStatus
        polishMenuItem?.title = controller.polishStatus
        refreshRecentMenu()
    }

    /// Clipboard-manager-style quick access: clicking an entry pastes it into
    /// the frontmost app (status menus never steal that app's focus).
    private func refreshRecentMenu() {
        guard let recentMenu else { return }
        recentMenu.removeAllItems()
        let recents = HistoryStore.shared.entries.suffix(5).reversed()
        guard !recents.isEmpty else {
            recentMenu.addItem(disabledItem("No dictations yet"))
            return
        }
        for entry in recents {
            let flattened = entry.text.replacingOccurrences(of: "\n", with: " ")
            let title = flattened.count > 44
                ? String(flattened.prefix(44)) + "…"
                : flattened
            let item = actionItem(title, #selector(pasteRecent(_:)))
            item.representedObject = entry.text
            recentMenu.addItem(item)
        }
    }

    @objc private func pasteRecent(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        // Give the menu a beat to dismiss so focus is back on the target app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.controller.pasteFromHistory(text)
        }
    }

    private func render(state: DictationController.State) {
        let symbol: String
        let desc: String
        switch state {
        case .idle: (symbol, desc) = ("mic", "idle")
        case .recording: (symbol, desc) = ("mic.fill", "recording")
        case .processing: (symbol, desc) = ("waveform", "processing")
        }
        statusItem.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "Dictator: \(desc)"
        )
        stateMenuItem?.title = "State: \(desc)"
    }
}
