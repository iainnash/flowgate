import Foundation
import SwiftUI

enum Decision: String, Codable {
    case allow
    case deny
    case ask
}

enum ToolCategory: String, Codable, CaseIterable, Identifiable {
    case read
    case write
    case execute
    case task
    case web
    case interactive
    case mcp
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .read: return "Read"
        case .write: return "Write"
        case .execute: return "Execute"
        case .task: return "Task"
        case .web: return "Web"
        case .interactive: return "Interactive"
        case .mcp: return "MCP"
        case .other: return "Other"
        }
    }

    var color: Color {
        switch self {
        case .read: return Color(red: 0.133, green: 0.773, blue: 0.369) // #22c55e
        case .write: return Color(red: 0.937, green: 0.267, blue: 0.267) // #ef4444
        case .execute: return Color(red: 0.961, green: 0.620, blue: 0.043) // #f59e0b
        case .task: return Color(red: 0.659, green: 0.333, blue: 0.969) // #a855f7
        case .web: return Color(red: 0.231, green: 0.510, blue: 0.965) // #3b82f6
        case .interactive: return Color(red: 0.545, green: 0.361, blue: 0.965) // #8b5cf6
        case .mcp: return Color(red: 0.024, green: 0.714, blue: 0.831) // #06b6d4
        case .other: return Color(red: 0.420, green: 0.451, blue: 0.498) // #6b7280
        }
    }

    static let knownTools: [String] = [
        // Read tools
        "Read", "Glob", "Grep",
        "ListMcpResourcesTool", "ReadMcpResourceTool", "ToolSearch",
        // Write tools
        "Edit", "Write", "MultiEdit", "NotebookEdit",
        // Execute tools
        "Bash", "KillShell", "Skill",
        // Task tools
        "Task", "TaskList", "TaskGet", "TaskOutput",
        "TaskCreate", "TaskUpdate", "TaskStop",
        // Web tools
        "WebFetch", "WebSearch",
        // Interactive tools
        "AskUserQuestion", "ExitPlanMode", "EnterPlanMode",
    ].sorted()

    static func fromToolName(_ toolName: String) -> ToolCategory {
        if toolName.hasPrefix("mcp__") { return .mcp }

        let readTools: Set<String> = ["Read", "Glob", "Grep", "ListMcpResourcesTool", "ReadMcpResourceTool", "ToolSearch"]
        let writeTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]
        let executeTools: Set<String> = ["Bash", "KillShell", "Skill"]
        let taskTools: Set<String> = ["Task", "TaskList", "TaskGet", "TaskOutput", "TaskCreate", "TaskUpdate", "TaskStop"]
        let webTools: Set<String> = ["WebFetch", "WebSearch"]
        let interactiveTools: Set<String> = ["AskUserQuestion", "ExitPlanMode", "EnterPlanMode"]

        if readTools.contains(toolName) { return .read }
        if writeTools.contains(toolName) { return .write }
        if executeTools.contains(toolName) { return .execute }
        if taskTools.contains(toolName) { return .task }
        if webTools.contains(toolName) { return .web }
        if interactiveTools.contains(toolName) { return .interactive }

        return .other
    }
}

// Prompt acceptance types
enum PromptAcceptType: String, Codable {
    case autoAccept = "auto-accept"
    case acceptAfter = "accept-after"
    case manual = "manual"
}

struct Prompt: Identifiable, Codable {
    let id: String
    let sessionId: String
    let toolName: String
    let toolInput: [String: AnyCodable]
    let hookEventName: String
    let cwd: String
    let createdAt: Int  // milliseconds timestamp
    let acceptType: PromptAcceptType  // How this prompt should be accepted
    let autoAcceptIn: Int?  // Seconds until auto-accept (only for accept-after type)
    let autoAcceptAt: Int?  // Unix timestamp (ms) when prompt will auto-accept (server-managed)

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
