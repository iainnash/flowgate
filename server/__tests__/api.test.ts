import { describe, it, expect, beforeAll, afterAll, vi } from 'vitest';
import request from 'supertest';
import { app, server, queue } from '../index.js';

// Mock the open module
vi.mock('open', () => ({ default: vi.fn() }));

describe('API Endpoints', () => {
  afterAll(() => {
    server.close();
  });

  describe('POST /api/prompt', () => {
    it('should reject malformed prompt', async () => {
      const res = await request(app)
        .post('/api/prompt')
        .send({ invalid: 'data' });
      expect(res.status).toBe(400);
      expect(res.body.error).toBe('Invalid hook input');
    });

    it('should accept valid prompt and wait for resolution', async () => {
      // Track when prompt is added using a promise
      let resolvePromptAdded: (id: string) => void;
      const promptAddedPromise = new Promise<string>((resolve) => {
        resolvePromptAdded = resolve;
      });

      queue.setCallbacks({
        onPromptAdded: (prompt) => {
          resolvePromptAdded(prompt.id);
        },
        onPromptResolved: () => {},
      });

      // Start the prompt request in background
      const promptPromise = new Promise<request.Response>((resolve, reject) => {
        request(app)
          .post('/api/prompt')
          .send({
            session_id: 'test',
            tool_name: 'Bash',
            tool_input: { command: 'echo hello' },
            hook_event_name: 'PreToolUse',
            cwd: '/tmp',
          })
          .then(resolve)
          .catch(reject);
      });

      // Wait for prompt to be added
      const addedPromptId = await promptAddedPromise;
      expect(addedPromptId).toBeDefined();

      // Resolve the prompt
      await request(app)
        .post(`/api/prompts/${addedPromptId}/resolve`)
        .send({ decision: 'allow' });

      const res = await promptPromise;
      expect(res.status).toBe(200);
      expect(res.body.decision).toBe('allow');
    });
  });

  describe('GET /api/prompts', () => {
    it('should return empty array when no prompts', async () => {
      const res = await request(app).get('/api/prompts');
      expect(res.status).toBe(200);
      expect(res.body).toEqual([]);
    });
  });

  describe('POST /api/prompts/:id/resolve', () => {
    it('should return 404 for unknown prompt', async () => {
      const res = await request(app)
        .post('/api/prompts/unknown/resolve')
        .send({ decision: 'allow' });
      expect(res.status).toBe(404);
    });

    it('should reject invalid decision', async () => {
      const res = await request(app)
        .post('/api/prompts/test/resolve')
        .send({ decision: 'invalid' });
      expect(res.status).toBe(400);
      expect(res.body.error).toBe('Invalid decision');
    });
  });

  describe('GET /api/settings', () => {
    it('should return settings with rules', async () => {
      const res = await request(app).get('/api/settings');
      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('rules');
      expect(res.body).toHaveProperty('projects');
      expect(Array.isArray(res.body.rules)).toBe(true);
    });
  });

  describe('PUT /api/settings', () => {
    it('should update settings with new rules', async () => {
      const newRules = [{
        id: 'test-rule',
        name: 'Test Rule',
        matchType: 'all',
        matchValue: '*',
        action: { type: 'require-verify' },
        enabled: true,
      }];
      const res = await request(app)
        .put('/api/settings')
        .send({ rules: newRules });
      expect(res.status).toBe(200);
      expect(res.body.rules).toHaveLength(1);
      expect(res.body.rules[0].name).toBe('Test Rule');
    });
  });
});
