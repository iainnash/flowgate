// Prompt acceptance types matching Go server
export { default as protocolSchema } from '../../../shared/protocol.schema.json';

export type PromptAcceptType = 'auto-accept' | 'accept-after' | 'manual';

export interface Prompt {
  id: string;
  sessionId: string;
  toolName: string;
  toolInput: Record<string, unknown>;
  hookEventName: string;
  cwd: string;
  createdAt: number;  // milliseconds
  acceptType: PromptAcceptType;
  autoAcceptIn?: number;  // seconds (only for display)
  autoAcceptAt?: number;  // milliseconds (only for accept-after)
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

export type ToolCategory = 'read' | 'write' | 'execute' | 'task' | 'web' | 'interactive' | 'mcp' | 'other';

// Simplified settings matching Go server schema
export interface Settings {
  rules: Rule[];
  native: NativeSettings;
}

export interface Rule {
  name: string;
  toolName: string;
  category?: string;
  pattern?: string;
  action: RuleAction;
  enabled: boolean;
  matchCount: number;
}

export interface RuleAction {
  type: 'manual' | 'auto-accept' | 'accept-after';
  seconds?: number;
}

export interface NativeSettings {
  showAutoAccept: boolean;
  enableAnimations: boolean;
}

// UI preferences stored in localStorage (not sent to server)
export interface UIPreferences {
  theme: 'dark' | 'light';
  volume: number; // 0-100, 0 = muted
}

export const DEFAULT_UI_PREFS: UIPreferences = {
  theme: 'dark',
  volume: 50,
}

export interface Decision {
  decision: 'allow' | 'deny' | 'ask' | 'defer';
  reason?: string;
  updatedInput?: Record<string, unknown>;
  additionalContext?: string;
}

export type WsMessage =
  | { type: 'prompt:new'; prompt: Prompt }
  | { type: 'prompt:resolved'; id: string; autoAccepted?: boolean }
  | { type: 'prompt:updated'; prompt: Prompt }
  | { type: 'prompts:list'; prompts: Prompt[] }
  | { type: 'pause:changed'; isPaused: boolean }
  | { type: 'settings:updated'; settings: Settings };

export const CODE_CHANGE_TOOLS = new Set(['Edit', 'Write', 'NotebookEdit']);

export function isCodeChange(toolName: string): boolean {
  return CODE_CHANGE_TOOLS.has(toolName);
}

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
