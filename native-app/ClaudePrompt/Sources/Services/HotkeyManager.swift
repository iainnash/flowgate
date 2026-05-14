import Foundation
import HotKey
import Carbon
import AppKit

class HotkeyManager: ObservableObject {
    private var acceptHotKey: HotKey?
    private var denyHotKey: HotKey?
    private var otherHotKey: HotKey?
    private var toggleHotKey: HotKey?
    private var pauseAllHotKey: HotKey?
    private var currentConfig: HotkeyConfig?
    private(set) var isSuspended = false

    var onAccept: (@Sendable () -> Void)?
    var onDeny: (@Sendable () -> Void)?
    var onOther: (@Sendable () -> Void)?
    var onToggle: (@Sendable () -> Void)?
    var onPauseAll: (@Sendable () -> Void)?

    init(config: HotkeyConfig? = nil) {
        if let config {
            setup(config: config)
        }
    }

    func setup(config: HotkeyConfig) {
        currentConfig = config
        guard !isSuspended else {
            unregisterHotkeys()
            return
        }

        registerHotkeys(config: config)
    }

    func setSuspended(_ suspended: Bool) {
        guard isSuspended != suspended else { return }
        isSuspended = suspended

        if suspended {
            unregisterHotkeys()
        } else if let currentConfig {
            registerHotkeys(config: currentConfig)
        }
    }

    private func unregisterHotkeys() {
        // Clear existing hotkeys
        acceptHotKey = nil
        denyHotKey = nil
        otherHotKey = nil
        toggleHotKey = nil
        pauseAllHotKey = nil
    }

    private func registerHotkeys(config: HotkeyConfig) {
        unregisterHotkeys()
        // Set up new hotkeys
        if let (key, modifiers) = parseHotkey(config.accept) {
            acceptHotKey = HotKey(key: key, modifiers: modifiers)
            acceptHotKey?.keyDownHandler = { [weak self] in
                self?.onAccept?()
            }
        }

        if let (key, modifiers) = parseHotkey(config.deny) {
            denyHotKey = HotKey(key: key, modifiers: modifiers)
            denyHotKey?.keyDownHandler = { [weak self] in
                self?.onDeny?()
            }
        }

        if let (key, modifiers) = parseHotkey(config.other) {
            otherHotKey = HotKey(key: key, modifiers: modifiers)
            otherHotKey?.keyDownHandler = { [weak self] in
                self?.onOther?()
            }
        }

        if let (key, modifiers) = parseHotkey(config.toggle) {
            toggleHotKey = HotKey(key: key, modifiers: modifiers)
            toggleHotKey?.keyDownHandler = { [weak self] in
                self?.onToggle?()
            }
        }

        if let (key, modifiers) = parseHotkey(config.pauseAll) {
            pauseAllHotKey = HotKey(key: key, modifiers: modifiers)
            pauseAllHotKey?.keyDownHandler = { [weak self] in
                self?.onPauseAll?()
            }
        }
    }

    private func parseHotkey(_ string: String) -> (Key, NSEvent.ModifierFlags)? {
        let parts = string.lowercased().split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }

        var modifiers: NSEvent.ModifierFlags = []
        var keyString: String?

        for part in parts {
            switch part {
            case "cmd", "command":
                modifiers.insert(.command)
            case "shift":
                modifiers.insert(.shift)
            case "alt", "option":
                modifiers.insert(.option)
            case "ctrl", "control":
                modifiers.insert(.control)
            default:
                keyString = part
            }
        }

        guard let keyStr = keyString,
              let key = Key(string: keyStr) else {
            return nil
        }

        return (key, modifiers)
    }
}
