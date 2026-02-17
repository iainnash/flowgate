import SwiftUI
import Foundation

// Question option structure
struct QuestionOption: Identifiable {
    let id = UUID()
    let label: String
    let description: String
}

// Question structure
struct UserQuestion: Identifiable {
    let id = UUID()
    let question: String
    let header: String
    let options: [QuestionOption]
    let multiSelect: Bool
}

struct UserQuestionCardView: View {
    let prompt: Prompt
    let sessionColor: Color
    var isActive: Bool = false
    var windowFocused: Bool = true
    var enableAnimations: Bool = true
    let onSubmit: ([String: Any]) -> Void
    let onAskInTerminal: () -> Void

    @State private var appeared: Bool = false
    @State private var selectedAnswers: [Int: Set<String>] = [:]
    @State private var otherInputs: [Int: String] = [:]
    @State private var showOther: [Int: Bool] = [:]

    // Parse questions from tool input
    private var questions: [UserQuestion] {
        guard let questionsArray = prompt.toolInput["questions"]?.value as? [[String: Any]] else {
            return []
        }
        return questionsArray.compactMap { dict -> UserQuestion? in
            guard let question = dict["question"] as? String,
                  let header = dict["header"] as? String,
                  let optionsArray = dict["options"] as? [[String: Any]] else { return nil }

            let options = optionsArray.compactMap { optDict -> QuestionOption? in
                guard let label = optDict["label"] as? String else { return nil }
                let description = optDict["description"] as? String ?? ""
                return QuestionOption(label: label, description: description)
            }

            let multiSelect = dict["multiSelect"] as? Bool ?? false
            return UserQuestion(question: question, header: header, options: options, multiSelect: multiSelect)
        }
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

                Text("User Prompt")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }

            // Questions
            ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                questionView(question, index: index)
            }

            Divider()

            // Action buttons
            HStack(spacing: 12) {
                Button(action: onAskInTerminal) {
                    Text("Answer in Terminal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: submitAnswers) {
                    VStack(spacing: 2) {
                        Text("Submit")
                        if isActive {
                            Text("\u{2318}\u{21E7}Y")
                                .font(.system(size: 9))
                                .foregroundColor(windowFocused ? .white.opacity(0.7) : .secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, isActive ? 2 : 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple, lineWidth: 2)
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

    @ViewBuilder
    private func questionView(_ question: UserQuestion, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Question header
            Text(question.header.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.purple)
                .tracking(0.5)

            // Question text
            Text(question.question)
                .font(.body)
                .foregroundColor(.primary)

            // Options
            VStack(spacing: 6) {
                ForEach(question.options) { option in
                    optionButton(option, questionIndex: index, multiSelect: question.multiSelect)
                }

                // Other option
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        let newShowOther = !(showOther[index] ?? false)
                        showOther[index] = newShowOther
                        if !newShowOther {
                            otherInputs[index] = nil
                        }
                        // Clear regular selections when choosing "Other"
                        if newShowOther {
                            selectedAnswers[index] = nil
                        }
                    }
                } label: {
                    HStack {
                        Text("Other...")
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(showOther[index] == true ? Color.purple : Color.secondary.opacity(0.3), lineWidth: 1)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(showOther[index] == true ? Color.purple.opacity(0.1) : Color.clear)
                            )
                    )
                }
                .buttonStyle(.plain)

                // Other text input
                if showOther[index] == true {
                    TextField("Enter custom response...", text: Binding(
                        get: { otherInputs[index] ?? "" },
                        set: { otherInputs[index] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    private func optionButton(_ option: QuestionOption, questionIndex: Int, multiSelect: Bool) -> some View {
        let isSelected = selectedAnswers[questionIndex]?.contains(option.label) ?? false

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                // Clear "Other" when selecting a regular option
                showOther[questionIndex] = false
                otherInputs[questionIndex] = nil

                if multiSelect {
                    var current = selectedAnswers[questionIndex] ?? []
                    if current.contains(option.label) {
                        current.remove(option.label)
                    } else {
                        current.insert(option.label)
                    }
                    selectedAnswers[questionIndex] = current
                } else {
                    selectedAnswers[questionIndex] = [option.label]
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if !option.description.isEmpty {
                        Text(option.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: multiSelect ? "checkmark.square.fill" : "checkmark.circle.fill")
                        .foregroundColor(.purple)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.purple : Color.secondary.opacity(0.3), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.purple.opacity(0.1) : Color.clear)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func submitAnswers() {
        var responseAnswers: [String: String] = [:]

        for (index, question) in questions.enumerated() {
            if showOther[index] == true, let otherText = otherInputs[index], !otherText.isEmpty {
                responseAnswers[question.question] = otherText
            } else if let selected = selectedAnswers[index], !selected.isEmpty {
                responseAnswers[question.question] = selected.sorted().joined(separator: ", ")
            }
        }

        onSubmit(["answers": responseAnswers])
    }
}

#Preview {
    let now = Int(Date().timeIntervalSince1970 * 1000)

    let questionPrompt = Prompt(
        id: "1",
        sessionId: "session-abc123",
        toolName: "AskUserQuestion",
        toolInput: [
            "questions": AnyCodable([
                [
                    "question": "Which database would you like to use?",
                    "header": "Database",
                    "options": [
                        ["label": "PostgreSQL", "description": "Recommended for most use cases"],
                        ["label": "SQLite", "description": "Simple, file-based database"],
                        ["label": "MongoDB", "description": "NoSQL document store"]
                    ],
                    "multiSelect": false
                ] as [String: Any]
            ])
        ],
        hookEventName: "PreToolUse",
        cwd: "/Users/test/project",
        createdAt: now,
        acceptType: .manual,
        autoAcceptIn: nil,
        autoAcceptAt: nil
    )

    UserQuestionCardView(
        prompt: questionPrompt,
        sessionColor: .blue,
        isActive: true,
        onSubmit: { _ in },
        onAskInTerminal: {}
    )
    .frame(width: 450)
    .padding()
}
