import SwiftUI

private enum RuleEditTarget: Identifiable {
    case new
    case existing(Rule)

    var id: String {
        switch self {
        case .new: return "__new__"
        case .existing(let rule): return rule.name
        }
    }

    var rule: Rule? {
        if case .existing(let r) = self { return r }
        return nil
    }
}

struct RulesListView: View {
    @ObservedObject var settingsManager: SettingsManager
    @Environment(\.dismiss) var dismiss

    @State private var editTarget: RuleEditTarget?

    private var rules: [Rule] {
        settingsManager.settings.server.rules
    }

    var body: some View {
        NavigationStack {
            List {
                if rules.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("No Rules")
                                .font(.headline)
                            Text("Add a rule to auto-accept prompts or customize handling")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                } else {
                    Section {
                        ForEach(Array(rules.enumerated()), id: \.element.name) { index, rule in
                            RuleRow(rule: rule, onToggle: {
                                toggleRule(at: index)
                            }, onDelete: {
                                deleteRule(at: index)
                            })
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editTarget = .existing(rule)
                            }
                        }
                        .onDelete(perform: deleteRules)
                        .onMove(perform: moveRules)
                    } header: {
                        Text("Most permissive rule wins. Auto-accept > Timed accept > Manual")
                    }
                }

                Section {
                    Text("Rules determine how prompts are handled. You can auto-accept, add a delay, or require manual approval based on tool, category, or pattern.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Rules")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editTarget = .new
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editTarget) { target in
                RuleEditorView(
                    rule: target.rule,
                    existingNames: Set(rules.map { $0.name })
                ) { newRule in
                    saveRule(newRule, replacing: target.rule)
                }
            }
        }
    }

    private func toggleRule(at index: Int) {
        var updatedRules = rules
        let rule = updatedRules[index]
        updatedRules[index] = Rule(
            name: rule.name,
            toolName: rule.toolName,
            category: rule.category,
            pattern: rule.pattern,
            action: rule.action,
            enabled: !rule.enabled,
            matchCount: rule.matchCount
        )
        settingsManager.settings.server.rules = updatedRules
        settingsManager.saveToFile()
        settingsManager.pushToServer()
    }

    private func deleteRule(at index: Int) {
        var updatedRules = rules
        updatedRules.remove(at: index)
        settingsManager.settings.server.rules = updatedRules
        settingsManager.saveToFile()
        settingsManager.pushToServer()
    }

    private func deleteRules(at offsets: IndexSet) {
        var updatedRules = rules
        updatedRules.remove(atOffsets: offsets)
        settingsManager.settings.server.rules = updatedRules
        settingsManager.saveToFile()
        settingsManager.pushToServer()
    }

    private func moveRules(from source: IndexSet, to destination: Int) {
        var updatedRules = rules
        updatedRules.move(fromOffsets: source, toOffset: destination)
        settingsManager.settings.server.rules = updatedRules
        settingsManager.saveToFile()
        settingsManager.pushToServer()
    }

    private func saveRule(_ rule: Rule, replacing oldRule: Rule?) {
        var updatedRules = rules

        if let oldRule = oldRule, let index = updatedRules.firstIndex(where: { $0.name == oldRule.name }) {
            updatedRules[index] = rule
        } else {
            updatedRules.append(rule)
        }

        settingsManager.settings.server.rules = updatedRules
        settingsManager.saveToFile()
        settingsManager.pushToServer()
    }
}

struct RuleRow: View {
    let rule: Rule
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Enable/disable toggle
            Button {
                onToggle()
            } label: {
                Image(systemName: rule.enabled ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(rule.enabled ? .accentColor : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(rule.name)
                        .font(.headline)
                        .foregroundColor(rule.enabled ? .primary : .secondary)

                    ActionBadge(action: rule.action)
                }

                HStack(spacing: 8) {
                    if !rule.toolName.isEmpty {
                        Label(rule.toolName, systemImage: "wrench")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let category = rule.category, let cat = ToolCategory(rawValue: category) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(cat.color)
                                .frame(width: 8, height: 8)
                            Text(cat.displayName)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    if let pattern = rule.pattern, !pattern.isEmpty {
                        Label(pattern, systemImage: "textformat.abc")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                if rule.matchCount > 0 {
                    Text("Matched \(rule.matchCount) times")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }

            Spacer()

            // Delete button
            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.body)
            }
            .buttonStyle(.plain)
            .help("Delete rule")

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(.vertical, 4)
        .opacity(rule.enabled ? 1.0 : 0.6)
    }
}

struct ActionBadge: View {
    let action: RuleAction

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }

    private var label: String {
        switch action.type {
        case "auto-accept":
            return "Auto"
        case "accept-after":
            return "\(action.seconds ?? 5)s"
        default:
            return "Manual"
        }
    }

    private var color: Color {
        switch action.type {
        case "auto-accept":
            return .green
        case "accept-after":
            return .orange
        default:
            return .blue
        }
    }
}

#Preview {
    RulesListView(settingsManager: SettingsManager(webSocket: WebSocketClient()))
}
