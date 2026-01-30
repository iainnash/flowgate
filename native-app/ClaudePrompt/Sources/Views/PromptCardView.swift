import SwiftUI

struct PromptCardView: View {
    let prompt: Prompt
    let sessionColor: Color
    var isActive: Bool = false
    var windowFocused: Bool = true  // Whether the parent window is focused
    var enableAnimations: Bool = true  // Enable entrance animations
    let onAccept: () -> Void
    let onDeny: () -> Void
    var onAcceptWithReason: ((String) -> Void)? = nil
    var onDenyWithReason: ((String) -> Void)? = nil

    @State private var showOtherField: Bool = false
    @State private var otherReason: String = ""
    @FocusState private var isOtherFieldFocused: Bool

    // Animation state for entrance
    @State private var appeared: Bool = false

    // Computed properties for prompt type (based on server-provided acceptType)
    private var isImmediateAutoAccept: Bool { prompt.acceptType == .autoAccept }
    private var isAcceptAfter: Bool { prompt.acceptType == .acceptAfter }
    private var isManual: Bool { prompt.acceptType == .manual }
    private var isPaused: Bool { isAcceptAfter && prompt.autoAcceptAt == nil }

    // Calculate countdown from server-provided autoAcceptAt
    private func countdownRemaining(at date: Date) -> Int {
        if let autoAcceptAt = prompt.autoAcceptAt {
            let now = Int(date.timeIntervalSince1970 * 1000)
            return max(0, (autoAcceptAt - now) / 1000)
        } else if let autoAcceptIn = prompt.autoAcceptIn, autoAcceptIn > 0 {
            // Paused - show the original duration
            return autoAcceptIn
        }
        return 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            headerView

            // Diff view for Edit/Write tools
            if prompt.toolName == "Edit" {
                EditDiffView(prompt: prompt)
            } else if prompt.toolName == "Write" {
                WriteDiffView(prompt: prompt)
            } else if prompt.category == .mcp {
                // MCP tool arguments view
                McpArgsView(prompt: prompt)
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
            // - Manual prompts: show Yes/No buttons
            // - Accept-after prompts: show buttons with countdown
            // - Immediate auto-accept: no buttons, just indicator
            if isImmediateAutoAccept {
                // Immediate auto-accept - just show indicator
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.green)
                    Text("Auto-accepting...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                actionButtons

                // Expandable "Other" section with text field
                if showOtherField {
                    otherFieldView
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        // Entrance animation
        .opacity(enableAnimations ? (appeared ? 1 : 0) : 1)
        .offset(y: enableAnimations ? (appeared ? 0 : -20) : 0)
        .scaleEffect(enableAnimations ? (appeared ? 1 : 0.95) : 1)
        .onAppear {
            if enableAnimations {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0)) {
                    appeared = true
                }
            } else {
                appeared = true
            }
        }
    }


    private var otherFieldView: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Reason or instructions...", text: $otherReason, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .focused($isOtherFieldFocused)

            HStack(spacing: 8) {
                Button("Cancel") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showOtherField = false
                        otherReason = ""
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Allow") {
                    onAcceptWithReason?(otherReason)
                    showOtherField = false
                    otherReason = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button("Deny") {
                    onDenyWithReason?(otherReason)
                    showOtherField = false
                    otherReason = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
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
            // Accept button with countdown - use TimelineView for live updates
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let remaining = countdownRemaining(at: context.date)
                Button(action: onAccept) {
                    VStack(spacing: 2) {
                        HStack {
                            Image(systemName: "checkmark")
                            if isAcceptAfter && remaining > 0 {
                                Text("Yes (\(remaining)s)")
                            } else if isPaused {
                                Text("Yes (paused)")
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
                .buttonStyle(.borderedProminent)
                .tint(windowFocused ? .green : .green.opacity(0.7))
            }

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
            .tint(windowFocused ? .red : .red.opacity(0.7))

            // Other button - toggles inline text field
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showOtherField.toggle()
                    if showOtherField {
                        isOtherFieldFocused = true
                    } else {
                        otherReason = ""
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    HStack {
                        Image(systemName: showOtherField ? "chevron.up" : "ellipsis")
                        Text(showOtherField ? "Hide" : "Other")
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

}

struct PromptCardView_Previews: PreviewProvider {
    static var previews: some View {
        let now = Int(Date().timeIntervalSince1970 * 1000)

        let bashPrompt = Prompt(
            id: "1",
            sessionId: "session-1",
            toolName: "Bash",
            toolInput: ["command": AnyCodable("npm install && npm run build")],
            hookEventName: "PreToolUse",
            cwd: "/Users/test/project",
            createdAt: now,
            acceptType: .acceptAfter,
            autoAcceptIn: 5,
            autoAcceptAt: now + 5000  // 5 seconds from now
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
            createdAt: now,
            acceptType: .manual,
            autoAcceptIn: nil,
            autoAcceptAt: nil
        )

        VStack(spacing: 20) {
            PromptCardView(
                prompt: bashPrompt,
                sessionColor: .blue,
                isActive: true,
                enableAnimations: true,
                onAccept: {},
                onDeny: {}
            )

            PromptCardView(
                prompt: editPrompt,
                sessionColor: .green,
                isActive: false,
                enableAnimations: true,
                onAccept: {},
                onDeny: {}
            )
        }
        .frame(width: 450)
        .padding()
    }
}
