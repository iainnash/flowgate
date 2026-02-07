import SwiftUI

struct RuleEditorView: View {
    @Environment(\.dismiss) var dismiss

    let rule: Rule?
    let existingNames: Set<String>
    let onSave: (Rule) -> Void

    @State private var name: String = ""
    @State private var toolName: String = ""
    @State private var category: String = ""
    @State private var pattern: String = ""
    @State private var actionType: ActionType = .manual
    @State private var actionSeconds: Int = 5
    @State private var enabled: Bool = true

    enum ActionType: String, CaseIterable {
        case manual = "manual"
        case autoAccept = "auto-accept"
        case acceptAfter = "accept-after"

        var displayName: String {
            switch self {
            case .manual: return "Manual"
            case .autoAccept: return "Auto-accept"
            case .acceptAfter: return "Accept after delay"
            }
        }
    }

    init(rule: Rule?, existingNames: Set<String>, onSave: @escaping (Rule) -> Void) {
        self.rule = rule
        self.existingNames = existingNames
        self.onSave = onSave

        if let rule = rule {
            _name = State(initialValue: rule.name)
            _toolName = State(initialValue: rule.toolName)
            _category = State(initialValue: rule.category ?? "")
            _pattern = State(initialValue: rule.pattern ?? "")
            _enabled = State(initialValue: rule.enabled)

            switch rule.action.type {
            case "auto-accept":
                _actionType = State(initialValue: .autoAccept)
            case "accept-after":
                _actionType = State(initialValue: .acceptAfter)
                _actionSeconds = State(initialValue: rule.action.seconds ?? 5)
            default:
                _actionType = State(initialValue: .manual)
            }
        }
    }

    private var isEditing: Bool { rule != nil }

    private var canSave: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return false }

        // Check for duplicate names (excluding current rule if editing)
        if isEditing {
            let otherNames = existingNames.subtracting([rule!.name])
            if otherNames.contains(trimmedName) { return false }
        } else {
            if existingNames.contains(trimmedName) { return false }
        }

        // At least one match condition required
        return !toolName.isEmpty || !category.isEmpty || !pattern.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rule") {
                    TextField("Name", text: $name)
                    Toggle("Enabled", isOn: $enabled)
                }

                Section {
                    Picker("Tool", selection: $toolName) {
                        Text("Any tool").tag("")
                        ForEach(ToolCategory.knownTools, id: \.self) { tool in
                            Text(tool).tag(tool)
                        }
                    }

                    Picker("Category", selection: $category) {
                        Text("Any category").tag("")
                        ForEach(ToolCategory.allCases) { cat in
                            HStack {
                                Circle()
                                    .fill(cat.color)
                                    .frame(width: 8, height: 8)
                                Text(cat.displayName)
                            }
                            .tag(cat.rawValue)
                        }
                    }

                    TextField("Pattern (regex)", text: $pattern)
                } header: {
                    Text("Match Conditions")
                } footer: {
                    Text("Rule matches if ANY condition is met. Pattern is matched against tool input (commands, file paths, etc.)")
                }

                Section("Action") {
                    Picker("Action", selection: $actionType) {
                        ForEach(ActionType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    if actionType == .acceptAfter {
                        Stepper("Delay: \(actionSeconds) seconds", value: $actionSeconds, in: 1...60)
                    }

                    switch actionType {
                    case .manual:
                        Text("Always require user approval")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .autoAccept:
                        Text("Accept immediately without delay")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .acceptAfter:
                        Text("Show countdown, auto-accept if not denied")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Rule" : "New Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveRule()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func saveRule() {
        let action: RuleAction
        switch actionType {
        case .manual:
            action = .manual
        case .autoAccept:
            action = .autoAccept
        case .acceptAfter:
            action = .acceptAfter(actionSeconds)
        }

        let newRule = Rule(
            name: name.trimmingCharacters(in: .whitespaces),
            toolName: toolName,
            category: category.isEmpty ? nil : category,
            pattern: pattern.isEmpty ? nil : pattern,
            action: action,
            enabled: enabled,
            matchCount: rule?.matchCount ?? 0
        )

        onSave(newRule)
        dismiss()
    }
}

#Preview {
    RuleEditorView(rule: nil, existingNames: []) { _ in }
}
