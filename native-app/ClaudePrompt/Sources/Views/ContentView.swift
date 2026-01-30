import SwiftUI

struct ContentView: View {
    @ObservedObject var promptManager: PromptManager
    @ObservedObject var settingsManager: SettingsManager
    @State private var showingOtherDialog = false
    @State private var showingSettings = false
    @State private var selectedPromptForOther: Prompt?
    @State private var otherReason = ""
    @State private var selectedIndex: Int = 0
    @State private var pausedPromptIds: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Prompt list or empty state
            if promptManager.prompts.isEmpty {
                emptyStateView
            } else {
                promptListView
            }
        }
        .frame(minWidth: 420, idealWidth: 480, maxWidth: 700, minHeight: 150, idealHeight: 400, maxHeight: 800)
        .sheet(isPresented: $showingOtherDialog) {
            otherDialogView
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(settingsManager: settingsManager)
        }
        .onAppear {
            setupKeyboardHandling()
        }
        .onChange(of: promptManager.prompts.count) { newCount in
            // Reset selection if out of bounds
            if selectedIndex >= newCount {
                selectedIndex = max(0, newCount - 1)
            }
        }
    }

    private func setupKeyboardHandling() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            return handleKeyEvent(event)
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard !promptManager.prompts.isEmpty else { return event }
        guard !showingOtherDialog && !showingSettings else { return event }

        let key = event.charactersIgnoringModifiers ?? ""

        switch key {
        case "j":  // Vim down
            selectNext()
            return nil
        case "k":  // Vim up
            selectPrevious()
            return nil
        default:
            break
        }

        switch event.keyCode {
        case 125:  // Down arrow
            selectNext()
            return nil
        case 126:  // Up arrow
            selectPrevious()
            return nil
        case 36:   // Enter - accept
            acceptSelected()
            return nil
        case 53:   // Escape - deny
            denySelected()
            return nil
        default:
            break
        }

        return event
    }

    private func selectNext() {
        if selectedIndex < promptManager.prompts.count - 1 {
            selectedIndex += 1
            pauseSelectedPrompt()
        }
    }

    private func selectPrevious() {
        if selectedIndex > 0 {
            selectedIndex -= 1
            pauseSelectedPrompt()
        }
    }

    private func pauseSelectedPrompt() {
        guard selectedIndex < promptManager.prompts.count else { return }
        let prompt = promptManager.prompts[selectedIndex]
        pausedPromptIds.insert(prompt.id)
    }

    private func acceptSelected() {
        guard selectedIndex < promptManager.prompts.count else { return }
        let prompt = promptManager.prompts[selectedIndex]
        promptManager.resolvePrompt(prompt, decision: .allow)
    }

    private func denySelected() {
        guard selectedIndex < promptManager.prompts.count else { return }
        let prompt = promptManager.prompts[selectedIndex]
        promptManager.resolvePrompt(prompt, decision: .deny)
    }

    var selectedPrompt: Prompt? {
        guard selectedIndex < promptManager.prompts.count else { return nil }
        return promptManager.prompts[selectedIndex]
    }

    private var headerView: some View {
        HStack {
            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(promptManager.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(promptManager.connectionStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Prompt count badge
            if promptManager.promptCount > 0 {
                Text("\(promptManager.promptCount)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }

            // Quick actions menu
            if promptManager.promptCount > 1 {
                Menu {
                    Button("Accept All") {
                        promptManager.acceptAll()
                    }
                    Button("Deny All") {
                        promptManager.denyAll()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }

            // Settings button
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gear")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.green.opacity(0.6))

            Text("No pending prompts")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Prompts from Claude Code will appear here")
                .font(.caption)
                .foregroundColor(.secondary)

            // Hotkey hints
            VStack(spacing: 4) {
                Text("⌘⇧P to toggle window")
                Text("↑↓ or j/k to navigate")
            }
            .font(.caption2)
            .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var promptListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(promptManager.prompts.enumerated()), id: \.element.id) { index, prompt in
                        PromptCardView(
                            prompt: prompt,
                            sessionColor: promptManager.colorForSession(prompt.sessionId),
                            isActive: index == selectedIndex,
                            autoAcceptSeconds: prompt.autoAcceptIn,
                            timerPaused: pausedPromptIds.contains(prompt.id),
                            onAccept: {
                                promptManager.resolvePrompt(prompt, decision: .allow)
                            },
                            onDeny: {
                                promptManager.resolvePrompt(prompt, decision: .deny)
                            },
                            onOther: {
                                selectedPromptForOther = prompt
                                showingOtherDialog = true
                            }
                        )
                        .id(prompt.id)
                        .onTapGesture {
                            selectedIndex = index
                            pausedPromptIds.insert(prompt.id)
                        }
                    }
                }
                .padding()
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .onChange(of: selectedIndex) { newIndex in
                if newIndex < promptManager.prompts.count {
                    withAnimation {
                        proxy.scrollTo(promptManager.prompts[newIndex].id, anchor: .center)
                    }
                }
            }
        }
    }

    private var otherDialogView: some View {
        VStack(spacing: 16) {
            Text("Additional Response")
                .font(.headline)

            if let prompt = selectedPromptForOther {
                Text("For: \(prompt.toolName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            TextField("Reason or instructions...", text: $otherReason, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

            HStack {
                Button("Cancel") {
                    showingOtherDialog = false
                    otherReason = ""
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Allow with Reason") {
                    if let prompt = selectedPromptForOther {
                        promptManager.resolvePrompt(prompt, decision: .allow, reason: otherReason)
                    }
                    showingOtherDialog = false
                    otherReason = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button("Deny with Reason") {
                    if let prompt = selectedPromptForOther {
                        promptManager.resolvePrompt(prompt, decision: .deny, reason: otherReason)
                    }
                    showingOtherDialog = false
                    otherReason = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(
            promptManager: PromptManager(),
            settingsManager: SettingsManager()
        )
    }
}
