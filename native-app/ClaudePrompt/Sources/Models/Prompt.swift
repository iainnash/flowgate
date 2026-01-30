import Foundation

enum Decision: String, Codable {
    case allow
    case deny
    case ask
}

enum ToolCategory: String, Codable, CaseIterable {
    case read
    case write
    case execute
    case web
    case interactive
    case mcp
    case other

    var displayName: String {
        switch self {
        case .read: return "Read"
        case .write: return "Write"
        case .execute: return "Execute"
        case .web: return "Web"
        case .interactive: return "Interactive"
        case .mcp: return "MCP"
        case .other: return "Other"
        }
    }

    static func fromToolName(_ toolName: String) -> ToolCategory {
        let readTools = ["Read", "Glob", "Grep", "TaskList", "TaskGet", "TaskOutput", "LS", "ListMcpResourcesTool", "ReadMcpResourceTool", "ToolSearch"]
        let writeTools = ["Edit", "Write", "MultiEdit", "NotebookEdit", "TaskCreate", "TaskUpdate"]
        let executeTools = ["Bash", "KillShell", "Task", "Skill"]
        let webTools = ["WebFetch", "WebSearch"]
        let interactiveTools = ["AskUserQuestion", "ExitPlanMode", "EnterPlanMode"]

        if readTools.contains(toolName) { return .read }
        if writeTools.contains(toolName) { return .write }
        if executeTools.contains(toolName) { return .execute }
        if webTools.contains(toolName) { return .web }
        if interactiveTools.contains(toolName) { return .interactive }
        if toolName.hasPrefix("mcp__") { return .mcp }
        return .other
    }
}

struct Prompt: Identifiable, Codable {
    let id: String
    let sessionId: String
    let toolName: String
    let toolInput: [String: AnyCodable]
    let hookEventName: String
    let cwd: String
    let createdAt: Int  // milliseconds timestamp
    let autoAcceptIn: Int?  // seconds until auto-accept (if applicable)

    var category: ToolCategory {
        ToolCategory.fromToolName(toolName)
    }

    var description: String {
        if let command = toolInput["command"]?.value as? String {
            let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(trimmed.prefix(100)) + (trimmed.count > 100 ? "..." : "")
        }
        if let filePath = toolInput["file_path"]?.value as? String {
            return filePath
        }
        if let pattern = toolInput["pattern"]?.value as? String {
            return pattern
        }
        if let query = toolInput["query"]?.value as? String {
            return query
        }
        return toolName
    }
}

struct PromptResolution: Codable {
    let decision: Decision
    let reason: String?
}

// Helper for encoding/decoding arbitrary JSON
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unable to encode value"))
        }
    }
}
