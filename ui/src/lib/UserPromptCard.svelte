<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import { getSessionColor, resolvePrompt } from './stores';
  import type { Prompt, UserQuestion } from './types';

  export let prompt: Prompt;

  const dispatch = createEventDispatcher<{ resolved: void }>();

  // Parse the questions from tool input
  $: questions = (prompt.toolInput.questions as UserQuestion[]) || [];
  $: sessionColor = getSessionColor(prompt.sessionId);

  // Track selected answers for each question
  let answers: Record<number, string | string[]> = {};

  function toggleOption(questionIdx: number, optionLabel: string, multiSelect: boolean) {
    if (multiSelect) {
      const current = (answers[questionIdx] as string[]) || [];
      if (current.includes(optionLabel)) {
        answers = { ...answers, [questionIdx]: current.filter((l) => l !== optionLabel) };
      } else {
        answers = { ...answers, [questionIdx]: [...current, optionLabel] };
      }
    } else {
      answers = { ...answers, [questionIdx]: optionLabel };
    }
  }

  function isSelected(questionIdx: number, optionLabel: string, multiSelect: boolean): boolean {
    if (multiSelect) {
      return ((answers[questionIdx] as string[]) || []).includes(optionLabel);
    }
    return answers[questionIdx] === optionLabel;
  }

  // Custom "Other" input for each question
  let otherInputs: Record<number, string> = {};
  let showOther: Record<number, boolean> = {};

  async function handleSubmit() {
    // Build the answers object for the response
    const responseAnswers: Record<string, string> = {};

    questions.forEach((q, idx) => {
      const answer = answers[idx];
      if (showOther[idx] && otherInputs[idx]) {
        responseAnswers[q.question] = otherInputs[idx];
      } else if (Array.isArray(answer)) {
        responseAnswers[q.question] = answer.join(', ');
      } else if (answer) {
        responseAnswers[q.question] = answer;
      }
    });

    // For user prompts, we allow with the answers as updatedInput
    await resolvePrompt(prompt.id, {
      decision: 'allow',
      updatedInput: { answers: responseAnswers },
    });
    dispatch('resolved');
  }

  async function handleSkip() {
    await resolvePrompt(prompt.id, {
      decision: 'ask',
      reason: 'User skipped to terminal',
    });
    dispatch('resolved');
  }
</script>

<div class="user-prompt-card">
  <div class="header">
    <span class="session-badge" style="background-color: {sessionColor}">
      {prompt.sessionId.slice(0, 10)}
    </span>
    <span class="tool-badge">User Prompt</span>
  </div>

  <div class="questions">
    {#each questions as question, qIdx}
      <div class="question-block">
        <div class="question-header">{question.header}</div>
        <div class="question-text">{question.question}</div>

        <div class="options" class:multi={question.multiSelect}>
          {#each question.options as option}
            <button
              class="option"
              class:selected={isSelected(qIdx, option.label, question.multiSelect)}
              on:click={() => {
                showOther = { ...showOther, [qIdx]: false };
                toggleOption(qIdx, option.label, question.multiSelect);
              }}
            >
              <span class="option-label">{option.label}</span>
              {#if option.description}
                <span class="option-desc">{option.description}</span>
              {/if}
            </button>
          {/each}

          <button
            class="option other-option"
            class:selected={showOther[qIdx]}
            on:click={() => {
              const newShowOther = !showOther[qIdx];
              showOther = { ...showOther, [qIdx]: newShowOther };
              if (!newShowOther) {
                otherInputs = { ...otherInputs, [qIdx]: '' };
              }
            }}
          >
            <span class="option-label">Other...</span>
          </button>
        </div>

        {#if showOther[qIdx]}
          <input
            type="text"
            class="other-input"
            placeholder="Enter custom response..."
            value={otherInputs[qIdx] || ''}
            on:input={(e) => {
              otherInputs = { ...otherInputs, [qIdx]: e.currentTarget.value };
            }}
          />
        {/if}
      </div>
    {/each}
  </div>

  <div class="actions">
    <button class="btn skip" on:click={handleSkip}>
      Answer in Terminal
    </button>
    <button class="btn submit" on:click={handleSubmit}>
      Submit
    </button>
  </div>
</div>

<style>
  .user-prompt-card {
    background: #1e1e2e;
    border: 2px solid #8b5cf6;
    border-radius: 12px;
    padding: 16px;
    margin-bottom: 12px;
  }

  .header {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 16px;
  }

  .session-badge {
    font-size: 11px;
    padding: 2px 8px;
    border-radius: 10px;
    color: white;
    font-weight: 500;
  }

  .tool-badge {
    font-size: 12px;
    padding: 2px 8px;
    border-radius: 6px;
    background: #8b5cf6;
    color: white;
    font-weight: 600;
  }

  .questions {
    display: flex;
    flex-direction: column;
    gap: 20px;
  }

  .question-block {
    background: #252538;
    border-radius: 8px;
    padding: 14px;
  }

  .question-header {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    color: #8b5cf6;
    margin-bottom: 6px;
    font-weight: 600;
  }

  .question-text {
    font-size: 15px;
    color: #eee;
    margin-bottom: 12px;
    line-height: 1.4;
  }

  .options {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .option {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 2px;
    padding: 10px 14px;
    border: 1px solid #444;
    border-radius: 8px;
    background: #1a1a2e;
    color: #ccc;
    text-align: left;
    cursor: pointer;
    transition: all 0.15s ease;
  }

  .option:hover {
    border-color: #666;
    background: #222238;
  }

  .option.selected {
    border-color: #8b5cf6;
    background: rgba(139, 92, 246, 0.15);
    color: #fff;
  }

  .option-label {
    font-size: 14px;
    font-weight: 500;
  }

  .option-desc {
    font-size: 12px;
    color: #888;
  }

  .option.selected .option-desc {
    color: #aaa;
  }

  .other-option {
    border-style: dashed;
  }

  .other-input {
    width: 100%;
    margin-top: 8px;
    padding: 10px;
    border: 1px solid #8b5cf6;
    border-radius: 6px;
    background: #1a1a2e;
    color: #eee;
    font-size: 14px;
  }

  .other-input:focus {
    outline: none;
    border-color: #a78bfa;
  }

  .actions {
    display: flex;
    gap: 8px;
    justify-content: flex-end;
    margin-top: 16px;
    padding-top: 16px;
    border-top: 1px solid #333;
  }

  .btn {
    padding: 8px 16px;
    border: none;
    border-radius: 6px;
    font-size: 14px;
    cursor: pointer;
    font-weight: 500;
  }

  .btn.skip {
    background: #444;
    color: #ccc;
  }

  .btn.skip:hover {
    background: #555;
  }

  .btn.submit {
    background: #8b5cf6;
    color: white;
  }

  .btn.submit:hover {
    background: #7c3aed;
  }
</style>
