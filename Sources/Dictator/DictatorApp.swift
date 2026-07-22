import AppKit
import OSLog
import SwiftUI
import ServiceManagement

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static var shared: AppDelegate?
    private let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.davidmadden.dictator",
        category: "app"
    )

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
    private var hotkeyListenerActive = false
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
    private var recoveryLeadingSeparatorItem: NSMenuItem!
    private var recoveryWarningItem: NSMenuItem!
    private var accessibilitySettingsItem: NSMenuItem!
    private var inputMonitoringSettingsItem: NSMenuItem!
    private var retryHotkeyItem: NSMenuItem!
    private var recoveryTrailingSeparatorItem: NSMenuItem!

    private func hotkeySetupState(accessibilityGranted: Bool) -> HotkeySetupState {
        HotkeySetupState(
            listenerActive: hotkeyListenerActive,
            accessibilityGranted: accessibilityGranted
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOtherInstances()
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

    /// The same bundle id can run from two paths (a dev build in build/ and
    /// the installed copy in /Applications), each adding its own menu bar
    /// icon and fighting over the hotkey. Newest launch wins.
    private func terminateOtherInstances() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.davidmadden.dictator"
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID }
        for other in others {
            NSLog("Dictator: replacing running instance at %@",
                  other.bundleURL?.path ?? "unknown path")
            other.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if !other.isTerminated { other.forceTerminate() }
            }
        }
    }

    private func startHotkey() {
        hotkeyListenerActive = hotkey.start()
        let accessibilityGranted = Permissions.accessibilityGranted
        let setup = hotkeySetupState(accessibilityGranted: accessibilityGranted)
        if setup.shouldPromptForAccessibility {
            log.notice("Dictator hotkey: Accessibility missing; prompting for permission")
            Permissions.promptForAccessibility()
            startPermissionPolling()
        } else if !hotkeyListenerActive {
            log.error("Dictator hotkey: listener inactive even though Accessibility is granted")
            stopPermissionPolling()
        } else {
            log.notice("Dictator hotkey: listener active")
            stopPermissionPolling()
        }
        rebuildMenu()
    }

    // The tap can only be created after Accessibility is granted, and macOS
    // doesn't notify us of the grant — poll and activate as soon as it lands.
    private func startPermissionPolling() {
        guard permissionPollTimer == nil else { return }
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let startSucceeded = self.hotkey.start()
            guard let outcome = HotkeyPermissionPollOutcome.evaluate(
                accessibilityGranted: Permissions.accessibilityGranted,
                startSucceeded: startSucceeded
            ) else { return }
            self.hotkeyListenerActive = outcome.listenerActive
            if outcome.stopPolling {
                self.stopPermissionPolling()
                self.log.notice("Dictator hotkey: listener activated after permission grant")
            } else {
                self.log.error("Dictator hotkey: Accessibility granted but listener still inactive")
            }
            self.rebuildMenu()
        }
    }

    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    @objc private func retryHotkey() { startHotkey() }
    @objc private func openAccessibilitySettings() { Permissions.openAccessibilityPane() }
    @objc private func openInputMonitoringSettings() { Permissions.openInputMonitoringPane() }
    @objc private func copyDiagnostics() {
        let accessibilityGranted = Permissions.accessibilityGranted
        let report = diagnosticsReport(accessibilityGranted: accessibilityGranted)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(report.formatted, forType: .string) {
            log.notice("Dictator diagnostics copied to pasteboard")
        } else {
            log.error("Dictator diagnostics failed to copy to pasteboard")
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleLoginItem() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if service.status == .enabled {
                    try service.unregister()
                } else {
                    try service.register()
                }
                rebuildMenu()
            } catch {
                NSLog("Dictator: failed to toggle login item: %@", error.localizedDescription)
            }
        }
    }

    private var loginItemEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

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
            view: HistoryView(store: .shared) { [weak self] text in
                self?.pasteDismissingHistory(text)
            }
        )
    }

    /// Enter/double-click in the History window: dismiss, give focus back to
    /// the app the user came from, then inject.
    private func pasteDismissingHistory(_ text: String) {
        historyWindow?.orderOut(nil)
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.controller.pasteFromHistory(text)
        }
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
        let recentItem = NSMenuItem(title: "Recent Dictations", action: nil, keyEquivalent: "")
        recentMenu = NSMenu()
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)
        menu.addItem(actionItem("History…", #selector(openHistory)))
        menu.addItem(actionItem("Copy Diagnostics", #selector(copyDiagnostics)))
        menu.addItem(.separator())
        menu.addItem(actionItem("Settings…", #selector(openSettings), key: ","))
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
        let loginItem = actionItem("Start at Login", #selector(toggleLoginItem))
        loginItem.state = loginItemEnabled ? .on : .off
        menu.addItem(loginItem)
        recoveryLeadingSeparatorItem = .separator()
        menu.addItem(recoveryLeadingSeparatorItem)
        recoveryWarningItem = disabledItem("")
        menu.addItem(recoveryWarningItem)
        accessibilitySettingsItem = actionItem("Open Accessibility Settings", #selector(openAccessibilitySettings))
        menu.addItem(accessibilitySettingsItem)
        inputMonitoringSettingsItem = actionItem("Open Input Monitoring Settings", #selector(openInputMonitoringSettings))
        menu.addItem(inputMonitoringSettingsItem)
        retryHotkeyItem = actionItem("Retry Hotkey Listener", #selector(retryHotkey), key: "r")
        menu.addItem(retryHotkeyItem)
        recoveryTrailingSeparatorItem = .separator()
        menu.addItem(recoveryTrailingSeparatorItem)
        refreshRecoveryItems(accessibilityGranted: Permissions.accessibilityGranted)
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
        let accessibilityGranted = Permissions.accessibilityGranted
        axMenuItem?.title = accessibilityGranted
            ? "Accessibility: granted ✓"
            : "Accessibility: not granted ✗"
        modelMenuItem?.title = modelStatus
        polishMenuItem?.title = controller.polishStatus
        refreshRecoveryItems(accessibilityGranted: accessibilityGranted)
        refreshRecentMenu()
    }

    private func refreshRecoveryItems(accessibilityGranted: Bool) {
        guard
            let recoveryLeadingSeparatorItem,
            let recoveryWarningItem,
            let accessibilitySettingsItem,
            let inputMonitoringSettingsItem,
            let retryHotkeyItem,
            let recoveryTrailingSeparatorItem
        else { return }

        let setup = hotkeySetupState(accessibilityGranted: accessibilityGranted)
        let showRecovery = setup.showRecoveryActions
        recoveryLeadingSeparatorItem.isHidden = !showRecovery
        recoveryTrailingSeparatorItem.isHidden = false
        accessibilitySettingsItem.isHidden = !showRecovery
        inputMonitoringSettingsItem.isHidden = !showRecovery
        retryHotkeyItem.isHidden = !showRecovery

        if let warning = setup.warningText {
            recoveryWarningItem.title = warning
            recoveryWarningItem.isHidden = !showRecovery
        } else {
            recoveryWarningItem.isHidden = true
        }
    }

    private func diagnosticsReport(accessibilityGranted: Bool) -> DiagnosticsReport {
        let history = HistoryStore.shared.entries.last
        let info = Bundle.main.infoDictionary ?? [:]
        return DiagnosticsReport(
            timestamp: Date(),
            appVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
            buildVersion: info["CFBundleVersion"] as? String ?? "unknown",
            bundlePath: Bundle.main.bundleURL.path,
            processID: ProcessInfo.processInfo.processIdentifier,
            hotkeyTitle: currentHotkey.title,
            activationTitle: currentMode.title,
            dictationState: stateDescription(for: controller.state),
            sessionLocked: sessionLocked,
            hotkeyListenerActive: hotkeyListenerActive,
            accessibilityGranted: accessibilityGranted,
            inputMonitoringGranted: Permissions.inputMonitoringGranted,
            microphonePermission: Permissions.microphonePermissionSummary,
            launchAtLoginEnabled: loginItemEnabled,
            modelStatus: modelStatus,
            polishStatus: controller.polishStatus,
            historyCount: HistoryStore.shared.entries.count,
            lastHistoryApp: history?.app,
            lastHistoryDate: history?.date,
            setupWarning: hotkeySetupState(accessibilityGranted: accessibilityGranted).warningText
        )
    }

    private func stateDescription(for state: DictationController.State) -> String {
        switch state {
        case .idle:
            return "idle"
        case .recording:
            return "recording"
        case .processing:
            return "processing"
        }
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
