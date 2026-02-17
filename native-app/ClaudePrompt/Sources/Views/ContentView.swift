import SwiftUI

struct ContentView: View {
    @ObservedObject var promptManager: PromptManager
    @ObservedObject var settingsManager: SettingsManager
    @State private var showingOtherDialog = false
    @State private var showingSettings = false
    @State private var selectedPromptForOther: Prompt?
    @State private var otherReason = ""
    @State private var selectedIndex: Int = 0
    @State private var previousPromptCount: Int = 0
    @Environment(\.controlActiveState) private var controlActiveState

    // Filter prompts based on showAutoAccept setting
    // Always show manual and accept-after (countdown) prompts
    // Only hide immediate auto-accept prompts when showAutoAccept is false
    var filteredPrompts: [Prompt] {
        let sorted = promptManager.sortedPrompts
        if settingsManager.settings.server.native.showAutoAccept {
            return sorted
        } else {
            // Show manual AND accept-after prompts (countdown prompts still need attention)
            return sorted.filter { $0.acceptType != .autoAccept }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Prompt list or empty state
            if filteredPrompts.isEmpty {
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
        .onChange(of: filteredPrompts.count) { newCount in
            // Reset selection if out of bounds
            if selectedIndex >= newCount {
                selectedIndex = max(0, newCount - 1)
            }

            // Return focus to previous app if enabled and prompts just became empty
            if settingsManager.settings.nativeOnly.returnFocusWhenEmpty &&
               previousPromptCount > 0 && newCount == 0 {
                // Deactivate app to return focus to previous application
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.hide(nil)
                }
            }

            previousPromptCount = newCount
        }
    }

    private func setupKeyboardHandling() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            return handleKeyEvent(event)
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard !filteredPrompts.isEmpty else { return event }
        guard !showingOtherDialog && !showingSettings else { return event }

        // Don't intercept keys when typing in a text field
        if let firstResponder = NSApp.keyWindow?.firstResponder,
           firstResponder is NSTextView || firstResponder is NSTextField {
            return event
        }

        let key = event.charactersIgnoringModifiers ?? ""
        let hasCmd = event.modifierFlags.contains(.command)
        let hasShift = event.modifierFlags.contains(.shift)
        let hasCmdShift = hasCmd && hasShift

        // ⌘⇧Y - Accept selected
        if hasCmdShift && key.lowercased() == "y" {
            acceptSelected()
            return nil
        }

        // ⌘⇧N - Deny selected
        if hasCmdShift && key.lowercased() == "n" {
            denySelected()
            return nil
        }

        // ⌘⇧O - Show other dialog
        if hasCmdShift && key.lowercased() == "o" {
            showOtherForSelected()
            return nil
        }

        // Navigation without modifiers
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
        case 36:   // Enter - also accept (convenience)
            acceptSelected()
            return nil
        case 53:   // Escape - also deny (convenience)
            denySelected()
            return nil
        default:
            break
        }

        return event
    }

    private func selectNext() {
        if selectedIndex < filteredPrompts.count - 1 {
            selectedIndex += 1
        }
    }

    private func selectPrevious() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    private func acceptSelected() {
        guard selectedIndex < filteredPrompts.count else { return }
        let prompt = filteredPrompts[selectedIndex]
        promptManager.resolvePrompt(prompt, decision: .allow)
    }

    private func denySelected() {
        guard selectedIndex < filteredPrompts.count else { return }
        let prompt = filteredPrompts[selectedIndex]
        promptManager.resolvePrompt(prompt, decision: .deny)
    }

    private func showOtherForSelected() {
        guard selectedIndex < filteredPrompts.count else { return }
        selectedPromptForOther = filteredPrompts[selectedIndex]
        showingOtherDialog = true
    }

    var selectedPrompt: Prompt? {
        guard selectedIndex < filteredPrompts.count else { return nil }
        return filteredPrompts[selectedIndex]
    }

    private var headerView: some View {
        HStack {
            // Hidden focus target - captures initial focus to avoid highlighting visible buttons
            Color.clear
                .frame(width: 0, height: 0)
                .focusable(true)

            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(promptManager.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text("Flowgate")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("·")
                    .font(.caption)
                    .foregroundColor(.secondary)
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

            // Accept All button - always visible, disabled when no prompts
            Button {
                promptManager.acceptAll()
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.title3)
                    .foregroundColor(promptManager.promptCount > 0 ? .green : .secondary.opacity(0.4))
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .disabled(promptManager.promptCount == 0)
            .help("Accept all prompts")

            // Deny All button - always visible, disabled when no prompts
            Button {
                promptManager.denyAll()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.title3)
                    .foregroundColor(promptManager.promptCount > 0 ? .red : .secondary.opacity(0.4))
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .disabled(promptManager.promptCount == 0)
            .help("Deny all prompts")

            // Pause/Play toggle button
            Button {
                promptManager.togglePauseAll()
            } label: {
                Image(systemName: promptManager.isPaused ? "play.fill" : "pause.fill")
                    .font(.title3)
                    .foregroundColor(promptManager.isPaused ? .orange : .green)
                    .padding(4)
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .help(promptManager.isPaused ? "Resume auto-accept" : "Pause auto-accept")

            // Settings button
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gear")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .focusable(false)
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
                    ForEach(Array(filteredPrompts.enumerated()), id: \.element.id) { index, prompt in
                        promptCard(for: prompt, at: index)
                    }
                }
                .padding()
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .onChange(of: selectedIndex) { newIndex in
                if newIndex < filteredPrompts.count {
                    withAnimation {
                        proxy.scrollTo(filteredPrompts[newIndex].id, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func promptCard(for prompt: Prompt, at index: Int) -> some View {
        if prompt.toolName == "ExitPlanMode" {
            ExitPlanModeCardView(
                prompt: prompt,
                sessionColor: promptManager.colorForSession(prompt.sessionId),
                isActive: index == selectedIndex,
                windowFocused: controlActiveState == .key,
                enableAnimations: settingsManager.settings.server.native.enableAnimations,
                onAccept: {
                    promptManager.resolvePrompt(prompt, decision: .allow)
                },
                onDeny: {
                    promptManager.resolvePrompt(prompt, decision: .deny)
                },
                onAskInTerminal: {
                    promptManager.resolvePrompt(prompt, decision: .ask, reason: "User wants to decide in terminal")
                }
            )
            .id(prompt.id)
            .onTapGesture {
                selectedIndex = index
            }
        } else {
            PromptCardView(
                prompt: prompt,
                sessionColor: promptManager.colorForSession(prompt.sessionId),
                isActive: index == selectedIndex,
                windowFocused: controlActiveState == .key,
                enableAnimations: settingsManager.settings.server.native.enableAnimations,
                onAccept: {
                    promptManager.resolvePrompt(prompt, decision: .allow)
                },
                onDeny: {
                    promptManager.resolvePrompt(prompt, decision: .deny)
                },
                onAcceptWithReason: { reason in
                    promptManager.resolvePrompt(prompt, decision: .allow, reason: reason)
                },
                onDenyWithReason: { reason in
                    promptManager.resolvePrompt(prompt, decision: .deny, reason: reason)
                }
            )
            .id(prompt.id)
            .onTapGesture {
                selectedIndex = index
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
        let ws = WebSocketClient()
        ContentView(
            promptManager: PromptManager(webSocket: ws),
            settingsManager: SettingsManager(webSocket: ws)
        )
    }
}
