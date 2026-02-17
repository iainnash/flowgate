import SwiftUI
import AppKit

@main
struct ClaudePromptApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty WindowGroup - we manage windows manually via AppDelegate
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
                .hidden()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 0, height: 0)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var floatingWindow: NSWindow?
    var logWindow: NSWindow?

    let promptManager: PromptManager
    let settingsManager: SettingsManager
    let hotkeyManager = HotkeyManager()

    override init() {
        // Create shared WebSocket client
        let webSocketClient = WebSocketClient()

        // Initialize managers with shared client
        self.promptManager = PromptManager(webSocket: webSocketClient)
        self.settingsManager = SettingsManager(webSocket: webSocketClient)

        super.init()

        // Link managers so PromptManager can forward settings updates
        promptManager.settingsManager = settingsManager
    }

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            // Start embedded server first
            ServerManager.shared.startServer()

            // Wait briefly for server to start
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            await setupApp()
        }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            promptManager.disconnect()
            ServerManager.shared.stopServer()
        }
    }

    private func setupApp() async {
        // Start as accessory (no dock icon)
        NSApp.setActivationPolicy(.accessory)

        // Set up application menu
        setupApplicationMenu()

        // Set up menu bar
        setupMenuBar()

        // Set up floating window
        setupFloatingWindow()

        // Set up hotkeys
        setupHotkeys()

        // Request notification permission
        promptManager.requestNotificationPermission()

        // Connect to server (will receive settings via WebSocket)
        promptManager.connect()

        // Show setup instructions on first launch
        checkFirstLaunch()
    }

    private func checkFirstLaunch() {
        let hasLaunchedKey = "hasLaunchedBefore"
        let defaults = UserDefaults.standard

        if !defaults.bool(forKey: hasLaunchedKey) {
            defaults.set(true, forKey: hasLaunchedKey)
            showSetupInstructions()
        }
    }

    private func showSetupInstructions() {
        // Get hook path from app bundle
        let hookPath: String
        if let resourcePath = Bundle.main.resourcePath {
            hookPath = (resourcePath as NSString).appendingPathComponent("prompt-hook")
        } else {
            hookPath = "/Applications/Flowgate.app/Contents/Resources/prompt-hook"
        }

        let alert = NSAlert()
        alert.messageText = "Welcome to Flowgate!"
        alert.informativeText = """
            To integrate with Claude Code, add this to your ~/.claude/settings.json:

            {
              "hooks": {
                "PreToolUse": ["\(hookPath)"]
              }
            }

            The hook path has been copied to your clipboard.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings File")
        alert.addButton(withTitle: "OK")

        // Copy hook path to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hookPath, forType: .string)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open or create settings file
            let settingsPath = NSString(string: "~/.claude/settings.json").expandingTildeInPath
            let settingsURL = URL(fileURLWithPath: settingsPath)

            // Create directory if needed
            let settingsDir = settingsURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: settingsDir, withIntermediateDirectories: true)

            // Create file if it doesn't exist
            if !FileManager.default.fileExists(atPath: settingsPath) {
                let defaultSettings = """
                    {
                      "hooks": {
                        "PreToolUse": ["\(hookPath)"]
                      }
                    }
                    """
                try? defaultSettings.write(to: settingsURL, atomically: true, encoding: .utf8)
            }

            NSWorkspace.shared.open(settingsURL)
        }
    }

    private func setupApplicationMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu

        appMenu.addItem(NSMenuItem(title: "About Flowgate", action: #selector(showAbout), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Flowgate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        mainMenu.addItem(appMenuItem)

        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu

        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenu = NSMenu(title: "View")
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu

        viewMenu.addItem(NSMenuItem(title: "Show Prompts Window", action: #selector(showPromptsWindow), keyEquivalent: "1"))
        viewMenu.addItem(NSMenuItem(title: "Show Server Log", action: #selector(showLogWindowAction), keyEquivalent: "2"))
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(NSMenuItem(title: "Open Web UI", action: #selector(openWebUIAction), keyEquivalent: "o"))

        mainMenu.addItem(viewMenuItem)

        // Server menu
        let serverMenu = NSMenu(title: "Server")
        let serverMenuItem = NSMenuItem()
        serverMenuItem.submenu = serverMenu

        serverMenu.addItem(NSMenuItem(title: "Start Server", action: #selector(startServerAction), keyEquivalent: ""))
        serverMenu.addItem(NSMenuItem(title: "Stop Server", action: #selector(stopServerAction), keyEquivalent: ""))
        serverMenu.addItem(NSMenuItem(title: "Restart Server", action: #selector(restartServerAction), keyEquivalent: "r"))
        serverMenu.addItem(NSMenuItem.separator())
        serverMenu.addItem(NSMenuItem(title: "Clear Log", action: #selector(clearLogAction), keyEquivalent: "k"))

        mainMenu.addItem(serverMenuItem)

        // Window menu
        let windowMenu = NSMenu(title: "Window")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu

        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.close), keyEquivalent: "w"))

        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func showSettings() {
        let settingsView = SettingsView(settingsManager: settingsManager)
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showPromptsWindow() {
        showFloatingWindow()
    }

    @objc private func showLogWindowAction() {
        showLogWindow()
    }

    @objc private func openWebUIAction() {
        Task {
            guard let token = TokenManager.shared.readToken() else {
                print("Cannot read auth token")
                return
            }
            let urlString = "http://localhost:8888?token=\(token)"
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func startServerAction() {
        ServerManager.shared.startServer()
    }

    @objc private func stopServerAction() {
        ServerManager.shared.stopServer()
    }

    @objc private func restartServerAction() {
        ServerManager.shared.restartServer()
    }

    @objc private func clearLogAction() {
        ServerManager.shared.clearLog()
    }

    private func showOtherDialog() {
        // First show and focus the window
        showFloatingWindow()

        // Check if there's a current prompt
        guard let prompt = promptManager.currentPrompt else {
            let alert = NSAlert()
            alert.messageText = "No Pending Prompts"
            alert.informativeText = "There are no prompts waiting for a response."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // Show input dialog
        let alert = NSAlert()
        alert.messageText = "Custom Response"
        alert.informativeText = "Enter a message to send back to Claude for: \(prompt.toolName)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Cancel")

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        inputField.placeholderString = "Enter your response..."
        inputField.usesSingleLineMode = false
        inputField.cell?.wraps = true
        inputField.cell?.isScrollable = true
        alert.accessoryView = inputField

        // Make input field first responder
        alert.window.initialFirstResponder = inputField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let reason = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !reason.isEmpty {
                promptManager.resolvePrompt(prompt, decision: .ask, reason: reason)
            }
        }
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            // Check if all windows are closed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let hasVisibleWindows = (self.floatingWindow?.isVisible ?? false) ||
                                        (self.logWindow?.isVisible ?? false)

                if !hasVisibleWindows {
                    // Hide from dock when no windows are open
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "message.circle", accessibilityDescription: "Flowgate")
            button.action = #selector(togglePopover)
            button.target = self

            // Set up badge observation
            observePrompts()
        }

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 240, height: 380)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                promptManager: promptManager,
                settingsManager: settingsManager,
                onShowWindow: { [weak self] in
                    self?.showFloatingWindow()
                    self?.popover.close()
                },
                onShowLog: { [weak self] in
                    self?.showLogWindow()
                    self?.popover.close()
                },
                onShowSettings: { [weak self] in
                    self?.showSettings()
                    self?.popover.close()
                },
                onQuit: {
                    NSApp.terminate(nil)
                }
            )
        )
    }

    private func showLogWindow() {
        // Show in dock when window is open (enables menu bar)
        NSApp.setActivationPolicy(.regular)

        if logWindow == nil {
            let logView = LogView()
            let hostingController = NSHostingController(rootView: logView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = "Server Log"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 700, height: 400))
            window.center()
            window.setFrameAutosaveName("ClaudePromptLogWindow")
            window.delegate = self

            logWindow = window
        }

        logWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func observePrompts() {
        // Use a simple timer to check for prompt count changes
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMenuBarBadge()
            }
        }
    }

    private func setupFloatingWindow() {
        let contentView = ContentView(
            promptManager: promptManager,
            settingsManager: settingsManager
        )

        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Flowgate"
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor

        // Floating window behavior
        if settingsManager.floatingWindow {
            window.level = .floating
        }

        // Remember position
        window.setFrameAutosaveName("ClaudePromptFloatingWindow")
        window.delegate = self

        // Set initial size if no saved frame
        if window.frame.size == .zero {
            window.setContentSize(NSSize(width: 400, height: 500))
            window.center()
        }

        floatingWindow = window

        // Always show window on launch
        showFloatingWindow()

        // Watch for new prompts to show window
        observeNewPrompts()
    }

    private func observeNewPrompts() {
        var previousPromptIds = Set(promptManager.prompts.map { $0.id })
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let currentPrompts = self.promptManager.prompts
                let currentIds = Set(currentPrompts.map { $0.id })

                // Find new prompts
                let newIds = currentIds.subtracting(previousPromptIds)
                if !newIds.isEmpty {
                    let newPrompts = currentPrompts.filter { newIds.contains($0.id) }
                    self.handleNewPrompts(newPrompts)
                }

                // Update window level based on prompt count
                self.updateWindowLevel()

                previousPromptIds = currentIds
            }
        }
    }

    private func handleNewPrompts(_ newPrompts: [Prompt]) {
        let focusMode = settingsManager.settings.nativeOnly.focusStealMode

        switch focusMode {
        case .never:
            // Don't show window at all
            return

        case .always:
            // Show window for any new prompt
            showFloatingWindow()

        case .confirmationNeeded:
            // Only show window if any new prompt requires manual approval (no autoAcceptIn)
            let hasManualPrompt = newPrompts.contains { $0.autoAcceptIn == nil }
            if hasManualPrompt {
                showFloatingWindow()
            }
        }
    }

    private func updateWindowLevel() {
        guard let window = floatingWindow else { return }
        guard settingsManager.floatingWindow else {
            // User disabled floating, always normal
            window.level = .normal
            return
        }

        if promptManager.promptCount > 0 {
            // Float when there are pending prompts
            window.level = .floating
        } else {
            // Normal window when no prompts
            window.level = .normal
        }
    }

    private func setupHotkeys() {
        hotkeyManager.onAccept = { [weak self] in
            Task { @MainActor in
                self?.promptManager.acceptCurrent()
            }
        }

        hotkeyManager.onDeny = { [weak self] in
            Task { @MainActor in
                self?.promptManager.denyCurrent()
            }
        }

        hotkeyManager.onOther = { [weak self] in
            Task { @MainActor in
                self?.showOtherDialog()
            }
        }

        hotkeyManager.onToggle = { [weak self] in
            Task { @MainActor in
                self?.toggleFloatingWindow()
            }
        }

        hotkeyManager.onPauseAll = { [weak self] in
            Task { @MainActor in
                self?.promptManager.togglePauseAll()
            }
        }

        hotkeyManager.setup(config: settingsManager.settings.nativeOnly.globalHotkeys)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.close()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showFloatingWindow() {
        guard let window = floatingWindow else { return }

        // Show in dock when window is open (enables menu bar)
        NSApp.setActivationPolicy(.regular)

        let animationsEnabled = settingsManager.settings.server.native.enableAnimations

        if animationsEnabled {
            // Disable implicit animations during setup
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            window.alphaValue = 0
            NSAnimationContext.endGrouping()

            // Show and activate
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            // Animate fade in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }
        } else {
            window.alphaValue = 1
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func hideFloatingWindow() {
        guard let window = floatingWindow else { return }

        let animationsEnabled = settingsManager.settings.server.native.enableAnimations

        if animationsEnabled {
            // Fade out
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                window.animator().alphaValue = 0
            }, completionHandler: {
                window.orderOut(nil)
                window.alphaValue = 1  // Reset for next show
            })
        } else {
            // No animation
            window.orderOut(nil)
        }
    }

    private func toggleFloatingWindow() {
        if floatingWindow?.isVisible == true {
            hideFloatingWindow()
        } else {
            showFloatingWindow()
        }
    }

    private func updateMenuBarBadge() {
        guard let button = statusItem.button else { return }

        // Only count manual prompts (non-auto-accept) for badge
        let count = promptManager.manualPromptCount

        if count > 0 {
            // Create composite image with badge
            let imageSize = NSSize(width: 24, height: 22)
            let image = NSImage(size: imageSize, flipped: false) { rect in
                // Draw base icon
                if let symbolImage = NSImage(systemSymbolName: "message.circle.fill", accessibilityDescription: nil) {
                    symbolImage.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
                }

                // Draw badge
                let badgeText = "\(count)"
                let badgeWidth = max(12.0, CGFloat(badgeText.count) * 6.0 + 4.0)
                let badgeRect = NSRect(x: 24 - badgeWidth, y: 10, width: badgeWidth, height: 12)
                NSColor.systemRed.setFill()
                NSBezierPath(roundedRect: badgeRect, xRadius: 6, yRadius: 6).fill()

                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center

                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                    .foregroundColor: NSColor.white,
                    .paragraphStyle: paragraphStyle
                ]

                let textSize = badgeText.size(withAttributes: attributes)
                let textRect = NSRect(
                    x: badgeRect.midX - textSize.width / 2,
                    y: badgeRect.midY - textSize.height / 2,
                    width: textSize.width,
                    height: textSize.height
                )
                badgeText.draw(in: textRect, withAttributes: attributes)

                return true
            }

            button.image = image
        } else {
            button.image = NSImage(systemSymbolName: "message.circle", accessibilityDescription: "Flowgate")
        }
    }
}
