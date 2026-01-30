import { test, expect } from '@playwright/test';

test.describe('Auto-Accept', () => {
  test('should auto-accept after timeout', async ({ page, request }) => {
    await page.goto('/');

    // Configure rule for execute category with 2 second timeout
    await page.getByRole('button', { name: 'Settings' }).click();

    // Find the execute rule and edit it
    const executeRule = page.locator('.rule-item').filter({ hasText: 'Command execution' });
    await executeRule.click();

    // Change action to accept-after with 2 seconds
    await page.locator('select').filter({ hasText: 'Action' }).selectOption('accept-after');
    await page.getByLabel('Delay (seconds)').fill('2');
    await page.getByRole('button', { name: 'Apply' }).click();
    await page.getByRole('button', { name: 'Save All' }).click();

    const promptRes = request.post('/api/prompt', {
      data: {
        session_id: 'auto-test',
        tool_name: 'Bash',
        tool_input: { command: 'ls' },
        hook_event_name: 'PreToolUse',
        cwd: '/tmp',
      },
    });

    // Wait for auto-accept (2 seconds + buffer)
    const result = await promptRes;
    const body = await result.json();
    expect(body.decision).toBe('allow');
  });

  test('should NOT auto-accept when rule requires verification', async ({
    page,
    request,
  }) => {
    await page.goto('/');

    // Configure write category rule to require verification
    await page.getByRole('button', { name: 'Settings' }).click();

    // Find the write rule and edit it
    const writeRule = page.locator('.rule-item').filter({ hasText: 'File writes' });
    await writeRule.click();

    // Change action to require-verify
    await page.locator('select').filter({ hasText: 'Action' }).selectOption('require-verify');
    await page.getByRole('button', { name: 'Apply' }).click();
    await page.getByRole('button', { name: 'Save All' }).click();

    const promptPromise = request.post('/api/prompt', {
      data: {
        session_id: 'code-test',
        tool_name: 'Edit',
        tool_input: {
          file_path: '/test.txt',
          old_string: 'a',
          new_string: 'b',
        },
        hook_event_name: 'PreToolUse',
        cwd: '/tmp',
      },
    });

    // Wait for prompt to appear
    await expect(page.getByText('Edit')).toBeVisible();

    // Should show manual approval message
    await expect(page.getByText(/Manual approval/i)).toBeVisible();

    // Wait past timeout - prompt should still be there
    await page.waitForTimeout(1500);
    await expect(page.getByText('Edit')).toBeVisible();

    // Manually approve
    await page.getByRole('button', { name: 'Yes' }).click();

    const result = await promptPromise;
    expect(result.ok()).toBe(true);
  });

  test('should show countdown timer', async ({ page, request }) => {
    await page.goto('/');

    // Configure read rule with 5 second timeout
    await page.getByRole('button', { name: 'Settings' }).click();

    // Find the read rule and edit it
    const readRule = page.locator('.rule-item').filter({ hasText: 'Read operations' });
    await readRule.click();

    // Set action to accept-after with 5 seconds
    await page.locator('select').filter({ hasText: 'Action' }).selectOption('accept-after');
    await page.getByLabel('Delay (seconds)').fill('5');
    await page.getByRole('button', { name: 'Apply' }).click();
    await page.getByRole('button', { name: 'Save All' }).click();

    request.post('/api/prompt', {
      data: {
        session_id: 'countdown-test',
        tool_name: 'Read',
        tool_input: { file_path: '/test.txt' },
        hook_event_name: 'PreToolUse',
        cwd: '/tmp',
      },
    });

    // Wait for prompt to appear
    await expect(page.getByText('Read')).toBeVisible();

    // Should show countdown
    const countdown = page.getByTestId('countdown');
    await expect(countdown).toBeVisible();

    // Approve before timeout
    await page.getByRole('button', { name: 'Yes' }).click();
  });

  test('should support project-specific rules', async ({ page, request }) => {
    await page.goto('/');

    // Add a project with custom rules
    await page.getByRole('button', { name: 'Settings' }).click();
    await page.getByRole('button', { name: '+ Project' }).click();
    await page.getByPlaceholder('/path/to/project').fill('/my/project');
    await page.getByRole('button', { name: 'Add' }).click();

    // Add a rule to auto-accept all tools in this project
    await page.getByRole('button', { name: '+ Add Rule' }).click();
    await page.getByLabel('Name').fill('Auto-accept all');
    await page.locator('select').filter({ hasText: 'Match Type' }).selectOption('all');
    await page.locator('select').filter({ hasText: 'Action' }).selectOption('auto-accept');
    await page.getByRole('button', { name: 'Apply' }).click();
    await page.getByRole('button', { name: 'Save All' }).click();

    // Test that project rule applies
    const promptRes = request.post('/api/prompt', {
      data: {
        session_id: 'project-test',
        tool_name: 'Bash',
        tool_input: { command: 'dangerous' },
        hook_event_name: 'PreToolUse',
        cwd: '/my/project/src',
      },
    });

    const result = await promptRes;
    const body = await result.json();
    expect(body.decision).toBe('allow');
  });
});
