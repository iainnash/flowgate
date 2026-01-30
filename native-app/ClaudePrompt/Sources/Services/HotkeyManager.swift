import Foundation
import HotKey
import Carbon
import AppKit

class HotkeyManager: ObservableObject {
    private var acceptHotKey: HotKey?
    private var denyHotKey: HotKey?
    private var otherHotKey: HotKey?
    private var toggleHotKey: HotKey?

    var onAccept: (@Sendable () -> Void)?
    var onDeny: (@Sendable () -> Void)?
    var onOther: (@Sendable () -> Void)?
    var onToggle: (@Sendable () -> Void)?

    func setup(config: HotkeyConfig) {
        // Clear existing hotkeys
        acceptHotKey = nil
        denyHotKey = nil
        otherHotKey = nil
        toggleHotKey = nil

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

        guard let keyStr = keyString, let key = keyFromString(keyStr) else {
            return nil
        }

        return (key, modifiers)
    }

    private func keyFromString(_ string: String) -> Key? {
        switch string.lowercased() {
        case "a": return .a
        case "b": return .b
        case "c": return .c
        case "d": return .d
        case "e": return .e
        case "f": return .f
        case "g": return .g
        case "h": return .h
        case "i": return .i
        case "j": return .j
        case "k": return .k
        case "l": return .l
        case "m": return .m
        case "n": return .n
        case "o": return .o
        case "p": return .p
        case "q": return .q
        case "r": return .r
        case "s": return .s
        case "t": return .t
        case "u": return .u
        case "v": return .v
        case "w": return .w
        case "x": return .x
        case "y": return .y
        case "z": return .z
        case "1": return .one
        case "2": return .two
        case "3": return .three
        case "4": return .four
        case "5": return .five
        case "6": return .six
        case "7": return .seven
        case "8": return .eight
        case "9": return .nine
        case "0": return .zero
        case "space": return .space
        case "return", "enter": return .return
        case "escape", "esc": return .escape
        case "tab": return .tab
        case "delete", "backspace": return .delete
        case "up": return .upArrow
        case "down": return .downArrow
        case "left": return .leftArrow
        case "right": return .rightArrow
        default: return nil
        }
    }
}
