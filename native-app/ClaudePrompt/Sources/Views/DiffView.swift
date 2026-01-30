import SwiftUI

// MARK: - Diff Algorithm

struct DiffLine: Identifiable {
    let id = UUID()
    let type: DiffLineType
    let content: String
    let oldLineNum: Int?
    let newLineNum: Int?
}

enum DiffLineType {
    case context
    case add
    case remove

    var backgroundColor: Color {
        switch self {
        case .add: return Color.green.opacity(0.15)
        case .remove: return Color.red.opacity(0.15)
        case .context: return Color.clear
        }
    }

    var prefix: String {
        switch self {
        case .add: return "+"
        case .remove: return "-"
        case .context: return " "
        }
    }

    var prefixColor: Color {
        switch self {
        case .add: return .green
        case .remove: return .red
        case .context: return .secondary
        }
    }
}

struct LCSMatch {
    let oldIdx: Int
    let newIdx: Int
}

/// Compute LCS (Longest Common Subsequence) of two line arrays
func computeLCS(_ oldLines: [String], _ newLines: [String]) -> [LCSMatch] {
    let m = oldLines.count
    let n = newLines.count

    // Build DP table
    var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

    for i in 1...m {
        for j in 1...n {
            if oldLines[i - 1] == newLines[j - 1] {
                dp[i][j] = dp[i - 1][j - 1] + 1
            } else {
                dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
            }
        }
    }

    // Backtrack to find LCS
    var result: [LCSMatch] = []
    var i = m, j = n
    while i > 0 && j > 0 {
        if oldLines[i - 1] == newLines[j - 1] {
            result.insert(LCSMatch(oldIdx: i - 1, newIdx: j - 1), at: 0)
            i -= 1
            j -= 1
        } else if dp[i - 1][j] > dp[i][j - 1] {
            i -= 1
        } else {
            j -= 1
        }
    }

    return result
}

/// Compute line-by-line diff using LCS algorithm
func computeLineDiff(oldText: String, newText: String) -> [DiffLine] {
    let oldLines = oldText.components(separatedBy: "\n")
    let newLines = newText.components(separatedBy: "\n")
    var result: [DiffLine] = []

    let lcs = computeLCS(oldLines, newLines)
    var oldIdx = 0
    var newIdx = 0
    var oldLineNum = 1
    var newLineNum = 1

    for match in lcs {
        // Add removed lines
        while oldIdx < match.oldIdx {
            result.append(DiffLine(type: .remove, content: oldLines[oldIdx], oldLineNum: oldLineNum, newLineNum: nil))
            oldLineNum += 1
            oldIdx += 1
        }
        // Add inserted lines
        while newIdx < match.newIdx {
            result.append(DiffLine(type: .add, content: newLines[newIdx], oldLineNum: nil, newLineNum: newLineNum))
            newLineNum += 1
            newIdx += 1
        }
        // Add context line
        result.append(DiffLine(type: .context, content: oldLines[oldIdx], oldLineNum: oldLineNum, newLineNum: newLineNum))
        oldLineNum += 1
        newLineNum += 1
        oldIdx += 1
        newIdx += 1
    }

    // Remaining removed lines
    while oldIdx < oldLines.count {
        result.append(DiffLine(type: .remove, content: oldLines[oldIdx], oldLineNum: oldLineNum, newLineNum: nil))
        oldLineNum += 1
        oldIdx += 1
    }
    // Remaining added lines
    while newIdx < newLines.count {
        result.append(DiffLine(type: .add, content: newLines[newIdx], oldLineNum: nil, newLineNum: newLineNum))
        newLineNum += 1
        newIdx += 1
    }

    return result
}

// MARK: - Views

struct DiffView: View {
    let oldString: String?
    let newString: String?
    let filePath: String?
    let replaceAll: Bool

    init(oldString: String?, newString: String?, filePath: String?, replaceAll: Bool = false) {
        self.oldString = oldString
        self.newString = newString
        self.filePath = filePath
        self.replaceAll = replaceAll
    }

    var diffLines: [DiffLine] {
        guard let old = oldString, let new = newString else { return [] }
        return computeLineDiff(oldText: old, newText: new)
    }

    var addedCount: Int {
        diffLines.filter { $0.type == .add }.count
    }

    var removedCount: Int {
        diffLines.filter { $0.type == .remove }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                if let path = filePath {
                    Text(path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                HStack(spacing: 8) {
                    Text("+\(addedCount)")
                        .foregroundColor(.green)
                        .font(.system(.caption, design: .monospaced))

                    Text("-\(removedCount)")
                        .foregroundColor(.red)
                        .font(.system(.caption, design: .monospaced))

                    if replaceAll {
                        Text("replace all")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Diff content
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(diffLines) { line in
                        DiffLineRowView(line: line)
                    }
                }
                .frame(minWidth: 300, alignment: .leading)
            }
            .frame(maxHeight: 250)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
}

struct DiffLineRowView: View {
    let line: DiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Old line number
            Text(line.oldLineNum.map { String($0) } ?? "")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 32, alignment: .trailing)
                .padding(.trailing, 4)

            // New line number
            Text(line.newLineNum.map { String($0) } ?? "")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 32, alignment: .trailing)
                .padding(.trailing, 4)

            // Prefix (+/-)
            Text(line.type.prefix)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(line.type.prefixColor)
                .frame(width: 16)

            // Content
            Text(line.content.isEmpty ? " " : line.content)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(line.type.backgroundColor)
    }
}

// MARK: - Helper Views for Prompts

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

    var replaceAll: Bool {
        prompt.toolInput["replace_all"]?.value as? Bool ?? false
    }

    var body: some View {
        if oldString != nil || newString != nil {
            DiffView(oldString: oldString, newString: newString, filePath: filePath, replaceAll: replaceAll)
        }
    }
}

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
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    if let path = filePath {
                        Image(systemName: "doc.badge.plus")
                            .foregroundColor(.green)
                        Text(path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.primary)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Text("+\(content.components(separatedBy: "\n").count) lines")
                        .foregroundColor(.green)
                        .font(.system(.caption, design: .monospaced))

                    Text("write")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Content
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(content.components(separatedBy: "\n").enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .top, spacing: 0) {
                                Text(String(index + 1))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 32, alignment: .trailing)
                                    .padding(.trailing, 4)

                                Text("+")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.green)
                                    .frame(width: 16)

                                Text(line.isEmpty ? " " : line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.15))
                        }
                    }
                    .frame(minWidth: 300, alignment: .leading)
                }
                .frame(maxHeight: 200)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

// MARK: - MCP Args View

struct McpArgsView: View {
    let prompt: Prompt

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with tool name
            HStack {
                Image(systemName: "server.rack")
                    .foregroundColor(.cyan)
                Text(cleanToolName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)
                    .fontWeight(.medium)

                Spacer()

                Text("MCP")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.cyan.opacity(0.2))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Arguments
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sortedArgs, id: \.key) { key, value in
                        HStack(alignment: .top, spacing: 8) {
                            Text(key)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.cyan)
                                .frame(minWidth: 80, alignment: .trailing)

                            Text(formatValue(value))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                                .lineLimit(5)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 150)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }

    // Remove "mcp__" prefix and format tool name
    var cleanToolName: String {
        var name = prompt.toolName
        if name.hasPrefix("mcp__") {
            name = String(name.dropFirst(5))
        }
        // Replace underscores with spaces and capitalize
        return name.replacingOccurrences(of: "_", with: " ")
    }

    // Sort args alphabetically for consistent display
    var sortedArgs: [(key: String, value: Any)] {
        prompt.toolInput.map { ($0.key, $0.value.value) }
            .sorted { $0.key < $1.key }
    }

    func formatValue(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let int as Int:
            return String(int)
        case let double as Double:
            return String(double)
        case let bool as Bool:
            return bool ? "true" : "false"
        case let array as [Any]:
            return "[\(array.map { formatValue($0) }.joined(separator: ", "))]"
        case let dict as [String: Any]:
            let items = dict.map { "\($0.key): \(formatValue($0.value))" }
            return "{\(items.joined(separator: ", "))}"
        case is NSNull:
            return "null"
        default:
            return String(describing: value)
        }
    }
}

// MARK: - Previews

struct DiffView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            DiffView(
                oldString: "const foo = 'bar';\nconst baz = 123;\nlet x = true;",
                newString: "const foo = 'baz';\nconst baz = 123;\nlet x = false;\nlet y = 42;",
                filePath: "/src/index.ts"
            )

            DiffView(
                oldString: "function hello() {\n  console.log('hi');\n}",
                newString: "function hello(name) {\n  console.log('hi', name);\n}",
                filePath: "/src/utils.ts",
                replaceAll: true
            )
        }
        .padding()
        .frame(width: 500)
    }
}
