<script lang="ts">
  import { isCodeChange } from './types';

  export let toolName: string;
  export let toolInput: Record<string, unknown>;

  interface DiffLine {
    type: 'context' | 'add' | 'remove' | 'header';
    content: string;
    oldLineNum?: number;
    newLineNum?: number;
  }

  function computeLineDiff(oldText: string, newText: string): DiffLine[] {
    const oldLines = oldText.split('\n');
    const newLines = newText.split('\n');
    const result: DiffLine[] = [];

    // Simple LCS-based diff
    const lcs = computeLCS(oldLines, newLines);
    let oldIdx = 0;
    let newIdx = 0;
    let oldLineNum = 1;
    let newLineNum = 1;

    for (const match of lcs) {
      // Add removed lines
      while (oldIdx < match.oldIdx) {
        result.push({ type: 'remove', content: oldLines[oldIdx], oldLineNum: oldLineNum++ });
        oldIdx++;
      }
      // Add inserted lines
      while (newIdx < match.newIdx) {
        result.push({ type: 'add', content: newLines[newIdx], newLineNum: newLineNum++ });
        newIdx++;
      }
      // Add context line
      result.push({ type: 'context', content: oldLines[oldIdx], oldLineNum: oldLineNum++, newLineNum: newLineNum++ });
      oldIdx++;
      newIdx++;
    }

    // Remaining removed lines
    while (oldIdx < oldLines.length) {
      result.push({ type: 'remove', content: oldLines[oldIdx], oldLineNum: oldLineNum++ });
      oldIdx++;
    }
    // Remaining added lines
    while (newIdx < newLines.length) {
      result.push({ type: 'add', content: newLines[newIdx], newLineNum: newLineNum++ });
      newIdx++;
    }

    return result;
  }

  interface LCSMatch {
    oldIdx: number;
    newIdx: number;
  }

  function computeLCS(oldLines: string[], newLines: string[]): LCSMatch[] {
    const m = oldLines.length;
    const n = newLines.length;

    // Build DP table
    const dp: number[][] = Array(m + 1).fill(null).map(() => Array(n + 1).fill(0));

    for (let i = 1; i <= m; i++) {
      for (let j = 1; j <= n; j++) {
        if (oldLines[i - 1] === newLines[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = Math.max(dp[i - 1][j], dp[i][j - 1]);
        }
      }
    }

    // Backtrack to find LCS
    const result: LCSMatch[] = [];
    let i = m, j = n;
    while (i > 0 && j > 0) {
      if (oldLines[i - 1] === newLines[j - 1]) {
        result.unshift({ oldIdx: i - 1, newIdx: j - 1 });
        i--;
        j--;
      } else if (dp[i - 1][j] > dp[i][j - 1]) {
        i--;
      } else {
        j--;
      }
    }

    return result;
  }

  $: isEdit = toolName === 'Edit';
  $: isWrite = toolName === 'Write';
  $: isNotebookEdit = toolName === 'NotebookEdit';

  $: filePath = (toolInput.file_path as string) ?? '';
  $: oldString = (toolInput.old_string as string) ?? '';
  $: newString = (toolInput.new_string as string) ?? '';
  $: writeContent = (toolInput.content as string) ?? '';
  $: notebookSource = (toolInput.new_source as string) ?? '';
  $: editMode = (toolInput.edit_mode as string) ?? 'replace';
  $: replaceAll = (toolInput.replace_all as boolean) ?? false;

  $: diffLines = isEdit ? computeLineDiff(oldString, newString) : [];
  $: addedCount = diffLines.filter(l => l.type === 'add').length;
  $: removedCount = diffLines.filter(l => l.type === 'remove').length;
</script>

<div class="code-diff">
  {#if isEdit}
    <div class="diff-header">
      <span class="file-path">{filePath}</span>
      <span class="stats">
        <span class="added">+{addedCount}</span>
        <span class="removed">-{removedCount}</span>
        {#if replaceAll}
          <span class="replace-all">replace all</span>
        {/if}
      </span>
    </div>
    <div class="diff-content">
      {#each diffLines as line}
        <div class="diff-line {line.type}">
          <span class="line-num old">{line.type === 'add' ? '' : line.oldLineNum ?? ''}</span>
          <span class="line-num new">{line.type === 'remove' ? '' : line.newLineNum ?? ''}</span>
          <span class="line-marker">
            {#if line.type === 'add'}+{:else if line.type === 'remove'}-{:else}&nbsp;{/if}
          </span>
          <span class="line-content">{line.content}</span>
        </div>
      {/each}
    </div>
  {:else if isWrite}
    <div class="diff-header">
      <span class="file-path">{filePath}</span>
      <span class="stats">
        <span class="added">+{writeContent.split('\n').length} lines</span>
        <span class="write-label">write</span>
      </span>
    </div>
    <div class="diff-content write-content">
      {#each writeContent.split('\n') as line, i}
        <div class="diff-line add">
          <span class="line-num new">{i + 1}</span>
          <span class="line-marker">+</span>
          <span class="line-content">{line}</span>
        </div>
      {/each}
    </div>
  {:else if isNotebookEdit}
    <div class="diff-header">
      <span class="file-path">{filePath}</span>
      <span class="stats">
        <span class="edit-mode">{editMode}</span>
      </span>
    </div>
    <div class="diff-content">
      {#each notebookSource.split('\n') as line, i}
        <div class="diff-line {editMode === 'delete' ? 'remove' : 'add'}">
          <span class="line-num new">{i + 1}</span>
          <span class="line-marker">{editMode === 'delete' ? '-' : '+'}</span>
          <span class="line-content">{line}</span>
        </div>
      {/each}
    </div>
  {:else}
    <pre class="fallback">{JSON.stringify(toolInput, null, 2)}</pre>
  {/if}
</div>

<style>
  .code-diff {
    background: var(--input-bg, #1a1a2e);
    border: 1px solid var(--input-border, #333);
    border-radius: 6px;
    overflow: hidden;
    font-family: 'SF Mono', Monaco, Consolas, monospace;
    font-size: 12px;
  }

  .diff-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 8px 12px;
    background: var(--card-bg, #2a2a3e);
    border-bottom: 1px solid var(--input-border, #333);
  }

  .file-path {
    color: var(--text-primary, #fff);
    font-weight: 500;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .stats {
    display: flex;
    gap: 8px;
    flex-shrink: 0;
  }

  .added {
    color: #22c55e;
  }

  .removed {
    color: #ef4444;
  }

  .replace-all, .write-label, .edit-mode {
    color: var(--text-muted, #888);
    font-size: 11px;
    padding: 2px 6px;
    background: var(--input-bg, #1a1a2e);
    border-radius: 4px;
  }

  .diff-content {
    max-height: 300px;
    overflow-y: auto;
  }

  .diff-line {
    display: flex;
    min-height: 20px;
    line-height: 20px;
  }

  .diff-line.add {
    background: rgba(34, 197, 94, 0.15);
  }

  .diff-line.remove {
    background: rgba(239, 68, 68, 0.15);
  }

  .diff-line.context {
    background: transparent;
  }

  .line-num {
    min-width: 32px;
    padding: 0 4px;
    text-align: right;
    color: var(--text-muted, #666);
    user-select: none;
    flex-shrink: 0;
  }

  .line-marker {
    width: 20px;
    text-align: center;
    flex-shrink: 0;
    user-select: none;
  }

  .diff-line.add .line-marker {
    color: #22c55e;
  }

  .diff-line.remove .line-marker {
    color: #ef4444;
  }

  .line-content {
    flex: 1;
    padding-right: 12px;
    white-space: pre;
    overflow-x: auto;
  }

  .fallback {
    margin: 0;
    padding: 12px;
    white-space: pre-wrap;
    word-break: break-word;
    color: var(--text-secondary, #ccc);
  }

  /* Scrollbar styling */
  .diff-content::-webkit-scrollbar {
    width: 8px;
    height: 8px;
  }

  .diff-content::-webkit-scrollbar-track {
    background: var(--input-bg, #1a1a2e);
  }

  .diff-content::-webkit-scrollbar-thumb {
    background: var(--border-color, #444);
    border-radius: 4px;
  }

  .diff-content::-webkit-scrollbar-thumb:hover {
    background: var(--text-muted, #666);
  }
</style>
