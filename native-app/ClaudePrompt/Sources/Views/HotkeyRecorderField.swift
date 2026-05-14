import AppKit
import HotKey
import SwiftUI

struct HotkeyRecorderField: View {
    @Binding var value: String
    var onRecordingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 6) {
            HotkeyRecorderTextField(value: $value, onRecordingChanged: onRecordingChanged)

            Button {
                value = ""
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear shortcut")
            .opacity(value.isEmpty ? 0.35 : 1)
            .disabled(value.isEmpty)
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

private struct HotkeyRecorderTextField: NSViewRepresentable {
    @Binding var value: String
    let onRecordingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> RecordingTextField {
        let textField = RecordingTextField()
        textField.isEditable = false
        textField.isSelectable = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.alignment = .center
        textField.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textField.onCapture = { value in
            self.value = value
        }
        textField.onRecordingChanged = onRecordingChanged
        textField.stringValue = RecordingTextField.displayText(for: value)
        return textField
    }

    func updateNSView(_ nsView: RecordingTextField, context: Context) {
        if !nsView.isRecording {
            nsView.stringValue = RecordingTextField.displayText(for: value)
        }
        nsView.onCapture = { value in
            self.value = value
        }
        nsView.onRecordingChanged = onRecordingChanged
    }
}

final class RecordingTextField: NSTextField {
    var onCapture: ((String) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    var isRecording = false
    private var previousValue = ""

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        previousValue = stringValue
        setRecording(true)
        stringValue = "Press keys"
        currentEditor()?.selectedRange = NSRange(location: 0, length: 0)
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            cancelRecording()
            return
        }

        guard let key = Key(carbonKeyCode: UInt32(event.keyCode)),
              let keyName = Self.storageName(for: key) else {
            NSSound.beep()
            return
        }

        let modifiers = Self.modifierNames(for: event.modifierFlags)
        guard !modifiers.isEmpty || Self.isFunctionKey(keyName) else {
            NSSound.beep()
            stringValue = "Add modifier"
            return
        }

        let capturedValue = (modifiers + [keyName]).joined(separator: "+")
        stringValue = Self.displayText(for: capturedValue)
        setRecording(false)
        window?.makeFirstResponder(nil)
        onCapture?(capturedValue)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            cancelRecording()
        }
        return super.resignFirstResponder()
    }

    private func cancelRecording() {
        setRecording(false)
        stringValue = previousValue
        window?.makeFirstResponder(nil)
    }

    private func setRecording(_ recording: Bool) {
        guard isRecording != recording else { return }
        isRecording = recording
        onRecordingChanged?(recording)
    }

    private static func modifierNames(for flags: NSEvent.ModifierFlags) -> [String] {
        var names: [String] = []
        let deviceIndependentFlags = flags.intersection(.deviceIndependentFlagsMask)

        if deviceIndependentFlags.contains(.command) {
            names.append("cmd")
        }
        if deviceIndependentFlags.contains(.control) {
            names.append("ctrl")
        }
        if deviceIndependentFlags.contains(.option) {
            names.append("option")
        }
        if deviceIndependentFlags.contains(.shift) {
            names.append("shift")
        }
        if deviceIndependentFlags.contains(.function) {
            names.append("fn")
        }

        return names
    }

    static func displayText(for value: String) -> String {
        guard !value.isEmpty else { return "None" }

        return value
            .split(separator: "+")
            .map { part -> String in
                switch part.lowercased() {
                case "cmd", "command": return "⌘"
                case "ctrl", "control": return "^"
                case "option", "alt": return "⌥"
                case "shift": return "⇧"
                case "fn", "function": return "fn"
                case "left": return "←"
                case "right": return "→"
                case "up": return "↑"
                case "down": return "↓"
                case "return", "enter": return "↩"
                case "tab": return "⇥"
                case "space": return "Space"
                case "delete", "backspace": return "⌫"
                case "escape", "esc": return "Esc"
                default: return part.uppercased()
                }
            }
            .joined()
    }

    private static func isFunctionKey(_ key: String) -> Bool {
        key.range(of: #"^f([1-9]|1[0-9]|20)$"#, options: .regularExpression) != nil
    }

    private static func storageName(for key: Key) -> String? {
        switch key {
        case .`return`: return "return"
        case .tab: return "tab"
        case .space: return "space"
        case .delete: return "delete"
        case .escape: return "escape"
        case .leftArrow: return "left"
        case .rightArrow: return "right"
        case .downArrow: return "down"
        case .upArrow: return "up"
        case .f1: return "f1"
        case .f2: return "f2"
        case .f3: return "f3"
        case .f4: return "f4"
        case .f5: return "f5"
        case .f6: return "f6"
        case .f7: return "f7"
        case .f8: return "f8"
        case .f9: return "f9"
        case .f10: return "f10"
        case .f11: return "f11"
        case .f12: return "f12"
        case .f13: return "f13"
        case .f14: return "f14"
        case .f15: return "f15"
        case .f16: return "f16"
        case .f17: return "f17"
        case .f18: return "f18"
        case .f19: return "f19"
        case .f20: return "f20"
        case .command, .rightCommand, .option, .rightOption, .control, .rightControl,
             .shift, .rightShift, .function, .capsLock:
            return nil
        default:
            return String(describing: key).lowercased()
        }
    }
}
