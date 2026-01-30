export interface Prompt {
  id: string;
  sessionId: string;
  toolName: string;
  toolInput: Record<string, unknown>;
  hookEventName: string;
  cwd: string;
  createdAt: number;
}

// AskUserQuestion tool input structure
export interface UserQuestionOption {
  label: string;
  description: string;
}

export interface UserQuestion {
  question: string;
  header: string;
  options: UserQuestionOption[];
  multiSelect: boolean;
}

export interface AskUserQuestionInput {
  questions: UserQuestion[];
}

export function isUserPrompt(prompt: Prompt): prompt is Prompt & { toolInput: AskUserQuestionInput } {
  return prompt.toolName === 'AskUserQuestion' &&
         'questions' in prompt.toolInput &&
         Array.isArray(prompt.toolInput.questions);
}

// ExitPlanMode tool input structure
export interface ExitPlanModeInput {
  allowedPrompts?: Array<{
    tool: string;
    prompt: string;
  }>;
  launchSwarm?: boolean;
  teammateCount?: number;
}

export function isExitPlanMode(prompt: Prompt): prompt is Prompt & { toolInput: ExitPlanModeInput } {
  return prompt.toolName === 'ExitPlanMode';
}

export type ToolCategory = 'read' | 'write' | 'execute' | 'web' | 'interactive' | 'mcp' | 'other';

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
  matchValue: string; // category name, tool name, or regex pattern
  action: RuleAction;
  enabled: boolean;
}

// Project-specific settings
export interface ProjectConfig {
  projectPath: string;
  rules: PermissionRule[];
}

// UI preferences
export interface UIPreferences {
  theme: 'dark' | 'light';
  volume: number; // 0-100, 0 = muted
}

export const DEFAULT_UI_PREFS: UIPreferences = {
  theme: 'dark',
  volume: 50,
};

// Main settings structure
export interface Settings {
  rules: PermissionRule[];
  projects: ProjectConfig[];
  ui: UIPreferences;
}

// Legacy types for migration
export type AutoAcceptSettings = {
  [K in ToolCategory]?: boolean;
};

export interface LegacySettings {
  autoAcceptTimeout: number;
  autoAccept?: AutoAcceptSettings;
  autoAcceptCodeChanges?: boolean;
  autoAcceptToolCalls?: boolean;
}

export interface Decision {
  decision: 'allow' | 'deny' | 'ask';
  reason?: string;
  updatedInput?: Record<string, unknown>;
}

export type WsMessage =
  | { type: 'prompt:new'; prompt: Prompt }
  | { type: 'prompt:resolved'; id: string; autoAccepted?: boolean }
  | { type: 'settings:updated'; settings: Settings }
  | { type: 'prompts:list'; prompts: Prompt[] };

export const CODE_CHANGE_TOOLS = new Set(['Edit', 'Write', 'NotebookEdit']);

export function isCodeChange(toolName: string): boolean {
  return CODE_CHANGE_TOOLS.has(toolName);
}

// Helper to create a default rule
export function createDefaultRule(
  matchType: RuleMatchType,
  matchValue: string,
  action: RuleAction,
  name?: string
): PermissionRule {
  return {
    id: crypto.randomUUID(),
    name: name ?? `${matchType}: ${matchValue}`,
    matchType,
    matchValue,
    action,
    enabled: true,
  };
}

// Default rules that provide safe defaults
export const DEFAULT_RULES: PermissionRule[] = [
  createDefaultRule('category', 'interactive', { type: 'require-verify' }, 'Interactive prompts'),
  createDefaultRule('category', 'read', { type: 'accept-after', seconds: 3 }, 'Read operations'),
  createDefaultRule('category', 'web', { type: 'accept-after', seconds: 5 }, 'Web requests'),
  createDefaultRule('category', 'write', { type: 'accept-after', seconds: 10 }, 'File writes'),
  createDefaultRule('category', 'execute', { type: 'require-verify' }, 'Command execution'),
  createDefaultRule('category', 'mcp', { type: 'require-verify' }, 'MCP tools'),
  createDefaultRule('all', '*', { type: 'require-verify' }, 'Everything else'),
];

// Device status types
export interface DeviceStatus {
  name: string;
  connected: boolean;
  deviceModel?: string;
}

export interface DevicesResponse {
  devices: DeviceStatus[];
  hasConnectedDevice: boolean;
}
