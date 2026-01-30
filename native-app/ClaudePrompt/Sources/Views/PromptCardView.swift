import SwiftUI

struct PromptCardView: View {
    let prompt: Prompt
    let sessionColor: Color
    var isActive: Bool = false
    var autoAcceptSeconds: Int? = nil  // Countdown seconds if auto-accept is enabled
    var timerPaused: Bool = false  // Pause timer when user interacts
    let onAccept: () -> Void
    let onDeny: () -> Void
    let onOther: () -> Void

    @State private var countdownProgress: CGFloat = 0
    @State private var countdownRemaining: Int = 0
    @State private var countdownTimer: Timer?
    @State private var countdownStartTime: Date?
    @State private var isPaused: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            headerView

            // Diff view for Edit/Write tools
            if prompt.toolName == "Edit" {
                EditDiffView(prompt: prompt)
            } else if prompt.toolName == "Write" {
                WriteDiffView(prompt: prompt)
            } else {
                // Description for other tools
                Text(prompt.description)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .truncationMode(.tail)
            }

            // Working directory
            HStack {
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(prompt.cwd)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // Action buttons
            actionButtons
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .onAppear {
            startCountdownIfNeeded()
        }
        .onDisappear {
            countdownTimer?.invalidate()
        }
    }

    private var headerView: some View {
        HStack {
            Circle()
                .fill(sessionColor)
                .frame(width: 8, height: 8)

            Text(prompt.toolName)
                .font(.headline)
                .fontWeight(.semibold)

            Spacer()

            if isActive {
                Text("ACTIVE")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(3)
            }

            Text(prompt.category.displayName)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(categoryColor.opacity(0.2))
                .foregroundColor(categoryColor)
                .cornerRadius(4)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Accept button with countdown
            Button(action: onAccept) {
                ZStack(alignment: .leading) {
                    // Countdown fill animation
                    if countdownProgress > 0 {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(width: geo.size.width * countdownProgress)
                                .animation(.linear(duration: 0.1), value: countdownProgress)
                        }
                    }

                    VStack(spacing: 2) {
                        HStack {
                            Image(systemName: "checkmark")
                            if countdownRemaining > 0 {
                                Text("Yes (\(countdownRemaining)s)")
                            } else {
                                Text("Yes")
                            }
                        }
                        if isActive {
                            Text("⌘⇧Y")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, isActive ? 6 : 8)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            // Deny button
            Button(action: onDeny) {
                VStack(spacing: 2) {
                    HStack {
                        Image(systemName: "xmark")
                        Text("No")
                    }
                    if isActive {
                        Text("⌘⇧N")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, isActive ? 6 : 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            // Other button
            Button(action: onOther) {
                VStack(spacing: 2) {
                    HStack {
                        Image(systemName: "ellipsis")
                        Text("Other")
                    }
                    if isActive {
                        Text("⌘⇧O")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, isActive ? 6 : 8)
            }
            .buttonStyle(.bordered)
        }
    }

    private var categoryColor: Color {
        switch prompt.category {
        case .read: return .blue
        case .write: return .orange
        case .execute: return .red
        case .web: return .purple
        case .interactive: return .green
        case .mcp: return .cyan
        case .other: return .gray
        }
    }

    private func startCountdownIfNeeded() {
        guard let seconds = autoAcceptSeconds, seconds > 0 else { return }

        countdownRemaining = seconds
        countdownStartTime = Date()
        let totalSeconds = Double(seconds)

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [self] timer in
            // Check if paused
            if timerPaused || isPaused {
                return  // Keep timer running but don't progress
            }

            guard let startTime = countdownStartTime else {
                timer.invalidate()
                return
            }

            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(1.0, elapsed / totalSeconds)

            Task { @MainActor in
                countdownProgress = CGFloat(progress)
                countdownRemaining = max(0, Int(ceil(totalSeconds - elapsed)))

                if progress >= 1.0 {
                    timer.invalidate()
                    // Auto-accept when countdown completes
                    onAccept()
                }
            }
        }
    }

    func pauseCountdown() {
        isPaused = true
    }
}

struct PromptCardView_Previews: PreviewProvider {
    static var previews: some View {
        let bashPrompt = Prompt(
            id: "1",
            sessionId: "session-1",
            toolName: "Bash",
            toolInput: ["command": AnyCodable("npm install && npm run build")],
            hookEventName: "PreToolUse",
            cwd: "/Users/test/project",
            createdAt: Int(Date().timeIntervalSince1970 * 1000),
            autoAcceptIn: 5
        )

        let editPrompt = Prompt(
            id: "2",
            sessionId: "session-1",
            toolName: "Edit",
            toolInput: [
                "file_path": AnyCodable("/src/index.ts"),
                "old_string": AnyCodable("const foo = 'bar';"),
                "new_string": AnyCodable("const foo = 'baz';")
            ],
            hookEventName: "PreToolUse",
            cwd: "/Users/test/project",
            createdAt: Int(Date().timeIntervalSince1970 * 1000),
            autoAcceptIn: nil
        )

        VStack(spacing: 20) {
            PromptCardView(
                prompt: bashPrompt,
                sessionColor: .blue,
                isActive: true,
                autoAcceptSeconds: 5,
                onAccept: {},
                onDeny: {},
                onOther: {}
            )

            PromptCardView(
                prompt: editPrompt,
                sessionColor: .green,
                isActive: false,
                onAccept: {},
                onDeny: {},
                onOther: {}
            )
        }
        .frame(width: 450)
        .padding()
    }
}
