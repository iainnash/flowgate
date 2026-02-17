import SwiftUI

struct ExitPlanModeCardView: View {
    let prompt: Prompt
    let sessionColor: Color
    var isActive: Bool = false
    var windowFocused: Bool = true
    var enableAnimations: Bool = true
    let onAccept: () -> Void
    let onDeny: () -> Void
    var onAskInTerminal: (() -> Void)? = nil

    @State private var appeared: Bool = false

    // Parse ExitPlanMode input
    private var allowedPrompts: [(tool: String, prompt: String)] {
        guard let allowedPromptsArray = prompt.toolInput["allowedPrompts"]?.value as? [[String: Any]] else {
            return []
        }
        return allowedPromptsArray.compactMap { dict in
            guard let tool = dict["tool"] as? String,
                  let prompt = dict["prompt"] as? String else { return nil }
            return (tool: tool, prompt: prompt)
        }
    }

    private var launchSwarm: Bool {
        prompt.toolInput["launchSwarm"]?.value as? Bool ?? false
    }

    private var teammateCount: Int? {
        prompt.toolInput["teammateCount"]?.value as? Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Circle()
                    .fill(sessionColor)
                    .frame(width: 8, height: 8)

                Text(prompt.sessionId.prefix(10))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Exit Plan Mode")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }

            // Main content
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundColor(.green)

                Text("Ready to implement?")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Claude has finished planning and wants to start implementing the solution.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            // Permissions section
            if !allowedPrompts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("REQUESTED PERMISSIONS")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    ForEach(Array(allowedPrompts.enumerated()), id: \.offset) { _, perm in
                        HStack(spacing: 8) {
                            Text(perm.tool)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(4)

                            Text(perm.prompt)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)

                        if perm.tool != allowedPrompts.last?.tool {
                            Divider()
                        }
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            }

            // Swarm info
            if launchSwarm {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("🐝")
                        Text("Swarm Mode")
                            .fontWeight(.semibold)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange)
                    .foregroundColor(.black)
                    .cornerRadius(6)

                    if let count = teammateCount {
                        Text("\(count) teammates")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            // Action buttons
            HStack(spacing: 12) {
                // Decide in Terminal button
                if let askInTerminal = onAskInTerminal {
                    Button(action: askInTerminal) {
                        Text("Decide in Terminal")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                // Keep Planning (deny)
                Button(action: onDeny) {
                    VStack(spacing: 2) {
                        Text("Keep Planning")
                        if isActive {
                            Text("⌘⇧N")
                                .font(.system(size: 9))
                                .foregroundColor(windowFocused ? .white.opacity(0.7) : .secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, isActive ? 2 : 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                // Start Implementing (accept)
                Button(action: onAccept) {
                    VStack(spacing: 2) {
                        Text("Start Implementing")
                        if isActive {
                            Text("⌘⇧Y")
                                .font(.system(size: 9))
                                .foregroundColor(windowFocused ? .white.opacity(0.7) : .secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, isActive ? 2 : 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -20)
        .scaleEffect(appeared ? 1 : 0.95)
        .onAppear {
            if !appeared {
                if enableAnimations {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            appeared = true
                        }
                    }
                } else {
                    appeared = true
                }
            }
        }
        .onDisappear {
            appeared = false
        }
    }
}

#Preview {
    let now = Int(Date().timeIntervalSince1970 * 1000)

    let exitPlanPrompt = Prompt(
        id: "1",
        sessionId: "session-abc123",
        toolName: "ExitPlanMode",
        toolInput: [
            "allowedPrompts": AnyCodable([
                ["tool": "Bash", "prompt": "run tests"],
                ["tool": "Bash", "prompt": "install dependencies"]
            ])
        ],
        hookEventName: "PreToolUse",
        cwd: "/Users/test/project",
        createdAt: now,
        acceptType: .manual,
        autoAcceptIn: nil,
        autoAcceptAt: nil
    )

    ExitPlanModeCardView(
        prompt: exitPlanPrompt,
        sessionColor: .blue,
        isActive: true,
        onAccept: {},
        onDeny: {},
        onAskInTerminal: {}
    )
    .frame(width: 450)
    .padding()
}
