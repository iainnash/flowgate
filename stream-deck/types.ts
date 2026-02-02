// Types matching Go server schema

export interface Prompt {
  id: string;
  sessionId: string;
  toolName: string;
  toolInput: Record<string, unknown>;
  hookEventName: string;
  cwd: string;
  createdAt: number; // milliseconds
  acceptType: 'auto-accept' | 'accept-after' | 'manual';
  autoAcceptIn?: number; // seconds
  autoAcceptAt?: number; // milliseconds
}

export interface Decision {
  decision: 'allow' | 'deny' | 'ask';
  reason?: string;
  updatedInput?: Record<string, unknown>;
}

export type WsMessage =
  | { type: 'prompt:new'; prompt: Prompt }
  | { type: 'prompt:resolved'; id: string; autoAccepted?: boolean }
  | { type: 'prompt:updated'; prompt: Prompt }
  | { type: 'prompts:list'; prompts: Prompt[] }
  | { type: 'pause:changed'; isPaused: boolean };

export interface ClientMessage {
  type: 'resolve' | 'resolve-all' | 'toggle-pause' | 'list';
  id?: string;
  decision?: Decision;
  resolveDecision?: 'allow' | 'deny';
}
