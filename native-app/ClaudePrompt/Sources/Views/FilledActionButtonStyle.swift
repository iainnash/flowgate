import SwiftUI

struct FilledActionButtonStyle: ButtonStyle {
    let color: Color
    var windowFocused: Bool = true

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundColor(.white.opacity(isEnabled ? 1 : 0.55))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(fillColor(configuration: configuration))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    private func fillColor(configuration: Configuration) -> Color {
        let baseOpacity = windowFocused ? 1.0 : 0.55
        let enabledOpacity = isEnabled ? baseOpacity : 0.25
        let pressedOpacity = configuration.isPressed ? enabledOpacity * 0.8 : enabledOpacity
        return color.opacity(pressedOpacity)
    }
}
