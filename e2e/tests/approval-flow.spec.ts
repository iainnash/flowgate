import { test, expect } from '@playwright/test';

test.describe('Approval Flow', () => {
  test('should show empty state initially', async ({ page }) => {
    await page.goto('/');
    await expect(page.getByText('No pending prompts')).toBeVisible();
  });

  test('should approve prompt via Yes button', async ({ page, request }) => {
    await page.goto('/');

    // Simulate hook sending a prompt
    const promptRes = request.post('/api/prompt', {
      data: {
        session_id: 'e2e-test',
        tool_name: 'Bash',
        tool_input: { command: 'echo hello' },
        hook_event_name: 'PreToolUse',
        cwd: '/tmp',
      },
    });

    // Wait for prompt card to appear
    await expect(page.getByText('Bash')).toBeVisible();
    await expect(page.getByText('echo hello')).toBeVisible();

    // Click Yes
    await page.getByRole('button', { name: 'Yes' }).click();

    // Verify prompt resolved
    const result = await promptRes;
    expect(result.ok()).toBe(true);
    const body = await result.json();
    expect(body.decision).toBe('allow');

    // Verify prompt removed from UI
    await expect(page.getByText('echo hello')).not.toBeVisible();
  });

  test('should deny prompt via No button', async ({ page, request }) => {
    await page.goto('/');

    const promptRes = request.post('/api/prompt', {
      data: {
        session_id: 'e2e-deny',
        tool_name: 'Bash',
        tool_input: { command: 'rm file.txt' },
        hook_event_name: 'PreToolUse',
        cwd: '/tmp',
      },
    });

    await expect(page.getByText('rm file.txt')).toBeVisible();
    await page.getByRole('button', { name: 'No' }).click();

    const result = await promptRes;
    const body = await result.json();
    expect(body.decision).toBe('deny');
  });

  test('should deny with custom reason via Other modal', async ({
    page,
    request,
  }) => {
    await page.goto('/');

    const promptRes = request.post('/api/prompt', {
      data: {
        session_id: 'e2e-other',
        tool_name: 'Bash',
        tool_input: { command: 'dangerous command' },
        hook_event_name: 'PreToolUse',
        cwd: '/tmp',
      },
    });

    await expect(page.getByText('dangerous command')).toBeVisible();
    await page.getByRole('button', { name: 'Other' }).click();

    // Modal should appear
    await expect(page.getByText('Custom Response')).toBeVisible();

    // Fill in denial reason
    await page.getByLabel('Denial reason').fill('Too risky');
    await page.getByRole('button', { name: 'Deny' }).click();

    const result = await promptRes;
    const body = await result.json();
    expect(body.decision).toBe('deny');
    expect(body.reason).toBe('Too risky');
  });

  test('should modify and approve via Other modal', async ({
    page,
    request,
  }) => {
    await page.goto('/');

    const promptRes = request.post('/api/prompt', {
      data: {
        session_id: 'e2e-modify',
        tool_name: 'Bash',
        tool_input: { command: 'npm install foo' },
        hook_event_name: 'PreToolUse',
        cwd: '/tmp',
      },
    });

    await expect(page.getByText('npm install foo')).toBeVisible();
    await page.getByRole('button', { name: 'Other' }).click();

    // Switch to modify tab
    await page.getByRole('button', { name: 'Modify & approve' }).click();

    // Modify the JSON
    const textarea = page.getByLabel('Modified input');
    await textarea.fill('{"command": "npm install bar"}');
    await page.getByRole('button', { name: 'Approve with changes' }).click();

    const result = await promptRes;
    const body = await result.json();
    expect(body.decision).toBe('allow');
    expect(body.updatedInput.command).toBe('npm install bar');
  });
});
