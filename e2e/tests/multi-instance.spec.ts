import { test, expect } from '@playwright/test';

test.describe('Multi-Instance Support', () => {
  test('should display prompts from multiple sessions', async ({
    page,
    request,
  }) => {
    await page.goto('/');

    // Send prompts from two different sessions
    request.post('/api/prompt', {
      data: {
        session_id: 'session-alpha',
        tool_name: 'Bash',
        tool_input: { command: 'echo alpha' },
        hook_event_name: 'PreToolUse',
        cwd: '/project-a',
      },
    });

    request.post('/api/prompt', {
      data: {
        session_id: 'session-beta',
        tool_name: 'Edit',
        tool_input: { file_path: '/test.txt' },
        hook_event_name: 'PreToolUse',
        cwd: '/project-b',
      },
    });

    // Verify both prompts appear
    await expect(page.getByText('session-a')).toBeVisible();
    await expect(page.getByText('session-b')).toBeVisible();

    // Verify both tools are shown
    await expect(page.getByText('Bash')).toBeVisible();
    await expect(page.getByText('Edit')).toBeVisible();
  });

  test('should have different colors for different sessions', async ({
    page,
    request,
  }) => {
    await page.goto('/');

    // Send prompts from two different sessions
    request.post('/api/prompt', {
      data: {
        session_id: 'session-one',
        tool_name: 'Bash',
        tool_input: { command: 'cmd1' },
        hook_event_name: 'PreToolUse',
        cwd: '/tmp',
      },
    });

    request.post('/api/prompt', {
      data: {
        session_id: 'session-two',
        tool_name: 'Bash',
        tool_input: { command: 'cmd2' },
        hook_event_name: 'PreToolUse',
        cwd: '/tmp',
      },
    });

    // Wait for both badges to appear
    await expect(page.getByText('session-o')).toBeVisible();
    await expect(page.getByText('session-t')).toBeVisible();

    // Get the background colors of both badges
    const badges = await page.locator('.session-badge').all();
    expect(badges.length).toBe(2);

    const color1 = await badges[0].evaluate(
      (el) => window.getComputedStyle(el).backgroundColor
    );
    const color2 = await badges[1].evaluate(
      (el) => window.getComputedStyle(el).backgroundColor
    );

    // Colors should be different
    expect(color1).not.toBe(color2);
  });

  test('should resolve prompts independently', async ({ page, request }) => {
    await page.goto('/');

    // Send two prompts
    const prompt1 = request.post('/api/prompt', {
      data: {
        session_id: 'session-resolve-1',
        tool_name: 'Bash',
        tool_input: { command: 'first' },
        hook_event_name: 'PreToolUse',
        cwd: '/tmp',
      },
    });

    const prompt2 = request.post('/api/prompt', {
      data: {
        session_id: 'session-resolve-2',
        tool_name: 'Bash',
        tool_input: { command: 'second' },
        hook_event_name: 'PreToolUse',
        cwd: '/tmp',
      },
    });

    // Wait for both to appear
    await expect(page.getByText('first')).toBeVisible();
    await expect(page.getByText('second')).toBeVisible();

    // Approve the first one
    const yesButtons = await page.getByRole('button', { name: 'Yes' }).all();
    await yesButtons[0].click();

    // First prompt should be resolved
    const result1 = await prompt1;
    expect((await result1.json()).decision).toBe('allow');

    // Second should still be visible
    await expect(page.getByText('second')).toBeVisible();

    // Deny the second one
    await page.getByRole('button', { name: 'No' }).click();
    const result2 = await prompt2;
    expect((await result2.json()).decision).toBe('deny');
  });
});
