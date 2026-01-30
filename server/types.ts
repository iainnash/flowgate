// Hook input from Claude Code
export interface HookInput {
  session_id: string;
  tool_name: string;
  tool_input: Record<string, unknown>;
  hook_event_name: string;
  cwd: string;
  transcript_path?: string;
  permission_mode?: string;
  tool_use_id?: string;
}

// Decision sent back to hook
export interface Decision {
  decision: 'allow' | 'deny' | 'ask';
  reason?: string;
  updatedInput?: Record<string, unknown>;
}

// Prompt acceptance types
export type PromptAcceptType = 'auto-accept' | 'accept-after' | 'manual';

// Internal prompt representation
export interface Prompt {
  id: string;
  sessionId: string;
  toolName: string;
  toolInput: Record<string, unknown>;
  hookEventName: string;
  cwd: string;
  createdAt: number;
  acceptType: PromptAcceptType;  // How this prompt should be accepted
  autoAcceptIn?: number;  // Seconds until auto-accept (only for accept-after type)
  autoAcceptAt?: number;  // Unix timestamp (ms) when prompt will auto-accept (server-managed, synced to clients)
}

// Prompt with resolver for pending requests
export interface PendingPrompt extends Prompt {
  resolve: (decision: Decision) => void;
  timeoutId?: ReturnType<typeof setTimeout>;
}

// Rule matching types
export type RuleMatchType = 'category' | 'tool' | 'pattern' | 'all';

// Rule actions
export type RuleAction =
  | { type: 'auto-accept' }
  | { type: 'accept-after'; seconds: number }
  | { type: 'require-verify' };

// A single permission rule
export interface PermissionRule {
  id: string;
  name: string;
  matchType: RuleMatchType;
  matchValue: string;
  action: RuleAction;
  enabled: boolean;
}

// Project-specific settings
export interface ProjectConfig {
  projectPath: string;
  rules: PermissionRule[];
}

// Settings configuration
export interface Settings {
  rules: PermissionRule[];
  projects: ProjectConfig[];
}

// Legacy types for migration
export type AutoAcceptSettings = {
  [K in ToolCategory]?: boolean;
};

export interface LegacySettings {
  autoAcceptTimeout?: number;
  autoAccept?: AutoAcceptSettings;
  autoAcceptCodeChanges?: boolean;
  autoAcceptToolCalls?: boolean;
}

// Tool categories
export const TOOL_CATEGORIES = {
  read: new Set([
    'Read', 'Glob', 'Grep',
    'TaskList', 'TaskGet', 'TaskOutput',
    'ListMcpResourcesTool', 'ReadMcpResourceTool',
    'ToolSearch',
  ]),
  write: new Set([
    'Edit', 'Write', 'NotebookEdit',
    'TaskCreate', 'TaskUpdate',
  ]),
  execute: new Set([
    'Bash', 'KillShell',
    'Task', 'Skill',
  ]),
  web: new Set([
    'WebFetch', 'WebSearch',
  ]),
  interactive: new Set([
    'AskUserQuestion',
    'ExitPlanMode',
    'EnterPlanMode',
  ]),
} as const;

export type ToolCategory = 'read' | 'write' | 'execute' | 'web' | 'interactive' | 'mcp' | 'other';

export function getToolCategory(toolName: string): ToolCategory {
  if (toolName.startsWith('mcp__')) return 'mcp';
  if (TOOL_CATEGORIES.read.has(toolName)) return 'read';
  if (TOOL_CATEGORIES.write.has(toolName)) return 'write';
  if (TOOL_CATEGORIES.execute.has(toolName)) return 'execute';
  if (TOOL_CATEGORIES.web.has(toolName)) return 'web';
  if (TOOL_CATEGORIES.interactive.has(toolName)) return 'interactive';
  return 'other';
}

// WebSocket message types
export type WsMessage =
  | { type: 'prompt:new'; prompt: Prompt }
  | { type: 'prompt:resolved'; id: string; autoAccepted?: boolean }
  | { type: 'prompt:updated'; prompt: Prompt }  // For timer updates (e.g., after resume from pause)
  | { type: 'settings:updated'; settings: Settings }
  | { type: 'prompts:list'; prompts: Prompt[] }
  | { type: 'pause:changed'; isPaused: boolean };

// Code change tools that require explicit approval
export const CODE_CHANGE_TOOLS = new Set(['Edit', 'Write', 'NotebookEdit']);

export function isCodeChange(toolName: string): boolean {
  return CODE_CHANGE_TOOLS.has(toolName);
}

// Evaluate if a rule matches a tool
export function ruleMatchesTool(rule: PermissionRule, toolName: string): boolean {
  if (!rule.enabled) return false;

  switch (rule.matchType) {
    case 'all':
      return true;
    case 'category':
      return getToolCategory(toolName) === rule.matchValue;
    case 'tool':
      return toolName === rule.matchValue;
    case 'pattern':
      try {
        return new RegExp(rule.matchValue).test(toolName);
      } catch {
        return false;
      }
    default:
      return false;
  }
}

// Find the first matching rule for a tool in a given cwd
export function findMatchingRule(
  settings: Settings,
  toolName: string,
  cwd: string
): PermissionRule | undefined {
  // Check project-specific rules first
  for (const project of settings.projects) {
    if (cwd.startsWith(project.projectPath)) {
      for (const rule of project.rules) {
        if (ruleMatchesTool(rule, toolName)) {
          return rule;
        }
      }
    }
  }

  // Then check global rules
  for (const rule of settings.rules) {
    if (ruleMatchesTool(rule, toolName)) {
      return rule;
    }
  }

  return undefined;
}

// Default rules
export function createDefaultRules(): PermissionRule[] {
  return [
    {
      id: crypto.randomUUID(),
      name: 'Interactive prompts',
      matchType: 'category',
      matchValue: 'interactive',
      action: { type: 'require-verify' },
      enabled: true,
    },
    {
      id: crypto.randomUUID(),
      name: 'Read operations',
      matchType: 'category',
      matchValue: 'read',
      action: { type: 'accept-after', seconds: 3 },
      enabled: true,
    },
    {
      id: crypto.randomUUID(),
      name: 'Web requests',
      matchType: 'category',
      matchValue: 'web',
      action: { type: 'accept-after', seconds: 5 },
      enabled: true,
    },
    {
      id: crypto.randomUUID(),
      name: 'File writes',
      matchType: 'category',
      matchValue: 'write',
      action: { type: 'accept-after', seconds: 10 },
      enabled: true,
    },
    {
      id: crypto.randomUUID(),
      name: 'Command execution',
      matchType: 'category',
      matchValue: 'execute',
      action: { type: 'require-verify' },
      enabled: true,
    },
    {
      id: crypto.randomUUID(),
      name: 'MCP tools',
      matchType: 'category',
      matchValue: 'mcp',
      action: { type: 'require-verify' },
      enabled: true,
    },
    {
      id: crypto.randomUUID(),
      name: 'Everything else',
      matchType: 'all',
      matchValue: '*',
      action: { type: 'require-verify' },
      enabled: true,
    },
  ];
}
