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
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var floatingWindow: NSWindow?

    let promptManager = PromptManager()
    let settingsManager = SettingsManager()
    let hotkeyManager = HotkeyManager()

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            await setupApp()
        }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            promptManager.disconnect()
        }
    }

    private func setupApp() async {
        // Hide from Dock (menu bar app only)
        NSApp.setActivationPolicy(.accessory)

        // Set up menu bar
        setupMenuBar()

        // Set up floating window
        setupFloatingWindow()

        // Set up hotkeys
        setupHotkeys()

        // Request notification permission
        promptManager.requestNotificationPermission()

        // Connect to server
        promptManager.connect()

        // Sync settings
        await settingsManager.syncWithServer()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "message.circle", accessibilityDescription: "Claude Prompt")
            button.action = #selector(togglePopover)
            button.target = self

            // Set up badge observation
            observePrompts()
        }

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 220, height: 280)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                promptManager: promptManager,
                settingsManager: settingsManager,
                onShowWindow: { [weak self] in
                    self?.showFloatingWindow()
                    self?.popover.close()
                },
                onQuit: {
                    NSApp.terminate(nil)
                }
            )
        )
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
        window.title = "Claude Prompt"
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

        // Set initial size if no saved frame
        if window.frame.size == .zero {
            window.setContentSize(NSSize(width: 400, height: 500))
            window.center()
        }

        floatingWindow = window

        // Show window on launch if there are prompts
        if promptManager.promptCount > 0 {
            showFloatingWindow()
        }

        // Watch for new prompts to show window
        observeNewPrompts()
    }

    private func observeNewPrompts() {
        var previousCount = promptManager.promptCount
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let currentCount = self.promptManager.promptCount

                // Show window and float when new prompts arrive
                if currentCount > previousCount && currentCount > 0 {
                    self.showFloatingWindow()
                }

                // Update window level based on prompt count
                self.updateWindowLevel()

                previousCount = currentCount
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
                self?.showFloatingWindow()
            }
        }

        hotkeyManager.onToggle = { [weak self] in
            Task { @MainActor in
                self?.toggleFloatingWindow()
            }
        }

        hotkeyManager.setup(config: settingsManager.settings.native.globalHotkeys)
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

        // Start transparent
        window.alphaValue = 0

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 1
        }
    }

    private func hideFloatingWindow() {
        guard let window = floatingWindow else { return }

        // Fade out
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            window.alphaValue = 1  // Reset for next show
        })
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

        let count = promptManager.promptCount

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
            button.image = NSImage(systemSymbolName: "message.circle", accessibilityDescription: "Claude Prompt")
        }
    }
}
