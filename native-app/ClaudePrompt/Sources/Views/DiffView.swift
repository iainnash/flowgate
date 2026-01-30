import SwiftUI

struct DiffView: View {
    let oldString: String?
    let newString: String?
    let filePath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // File path header
            if let path = filePath {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundColor(.secondary)
                    Text(path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            // Diff content - scrollable both directions
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    if let old = oldString, !old.isEmpty {
                        // Show removal
                        DiffLineView(content: old, type: .removed)
                    }

                    if let new = newString, !new.isEmpty {
                        // Show addition
                        DiffLineView(content: new, type: .added)
                    }

                    if oldString == nil && newString != nil {
                        // New file
                        if let content = newString {
                            DiffLineView(content: content, type: .added, isNewFile: true)
                        }
                    }
                }
                .frame(minWidth: 300, alignment: .leading)
            }
            .frame(maxHeight: 250)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
        }
    }
}

struct DiffLineView: View {
    let content: String
    let type: DiffType
    var isNewFile: Bool = false

    enum DiffType {
        case added
        case removed
        case context

        var backgroundColor: Color {
            switch self {
            case .added: return Color.green.opacity(0.15)
            case .removed: return Color.red.opacity(0.15)
            case .context: return Color.clear
            }
        }

        var prefix: String {
            switch self {
            case .added: return "+"
            case .removed: return "-"
            case .context: return " "
            }
        }

        var prefixColor: Color {
            switch self {
            case .added: return .green
            case .removed: return .red
            case .context: return .secondary
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(content.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 0) {
                    Text(type.prefix)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(type.prefixColor)
                        .frame(width: 16)

                    Text(line.isEmpty ? " " : line)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(type.backgroundColor)
            }
        }
    }
}

// Helper view for Edit tool prompts
struct EditDiffView: View {
    let prompt: Prompt

    var oldString: String? {
        prompt.toolInput["old_string"]?.value as? String
    }

    var newString: String? {
        prompt.toolInput["new_string"]?.value as? String
    }

    var filePath: String? {
        prompt.toolInput["file_path"]?.value as? String
    }

    var body: some View {
        if oldString != nil || newString != nil {
            DiffView(oldString: oldString, newString: newString, filePath: filePath)
        }
    }
}

// Helper view for Write tool prompts
struct WriteDiffView: View {
    let prompt: Prompt

    var content: String? {
        prompt.toolInput["content"]?.value as? String
    }

    var filePath: String? {
        prompt.toolInput["file_path"]?.value as? String
    }

    var body: some View {
        if let content = content {
            VStack(alignment: .leading, spacing: 8) {
                if let path = filePath {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                            .foregroundColor(.green)
                        Text(path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("(new file)")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                ScrollView {
                    Text(content)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 200)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
            }
        }
    }
}

struct DiffView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            DiffView(
                oldString: "const foo = 'bar';",
                newString: "const foo = 'baz';",
                filePath: "/src/index.ts"
            )

            DiffView(
                oldString: nil,
                newString: "# New File\n\nThis is new content.",
                filePath: "/README.md"
            )
        }
        .padding()
        .frame(width: 400)
    }
}
