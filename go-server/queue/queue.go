package queue

import (
	"fmt"
	"sync"
	"time"

	"github.com/iain/claude-prompt-ui/models"
)

// Callbacks for queue events
type Callbacks struct {
	OnPromptAdded    func(*models.Prompt)
	OnPromptResolved func(id string, autoAccepted bool)
	OnPromptUpdated  func(*models.Prompt)
}

// PendingPrompt tracks a prompt with its resolution mechanism
type PendingPrompt struct {
	*models.Prompt
	ResolveChan chan *models.Decision
	Timer       *time.Timer
}

// Queue manages pending prompts and auto-accept timers
type Queue struct {
	mu              sync.RWMutex
	prompts         map[string]*PendingPrompt
	settings        *models.Settings
	callbacks       *Callbacks
	isPaused        bool
	pausedRemaining map[string]time.Duration // remaining time when paused
	verbose         bool
}

// New creates a new prompt queue
func New(verbose bool) *Queue {
	return &Queue{
		prompts:         make(map[string]*PendingPrompt),
		settings:        models.DefaultSettings(),
		pausedRemaining: make(map[string]time.Duration),
		verbose:         verbose,
	}
}

// SetCallbacks sets the event callbacks
func (q *Queue) SetCallbacks(cb *Callbacks) {
	q.callbacks = cb
}

// log prints debug output if verbose mode is enabled
func (q *Queue) log(format string, args ...interface{}) {
	if q.verbose {
		fmt.Printf("[%s] [Queue] %s\n", time.Now().Format(time.RFC3339), fmt.Sprintf(format, args...))
	}
}

// Add adds a new prompt and waits for resolution
func (q *Queue) Add(input *models.HookInput) (*models.Decision, error) {
	q.mu.Lock()

	// Generate unique ID
	id := fmt.Sprintf("prompt-%d", time.Now().UnixNano())

	// Determine action based on rules
	action := q.matchRules(input.ToolName, input.ToolInput)

	// Create prompt
	now := models.GetCurrentTimeMillis()
	var acceptType models.PromptAcceptType
	var autoAcceptIn *int
	var autoAcceptAt *int64

	switch action.Type {
	case "auto-accept":
		acceptType = models.AcceptTypeAutoAccept
		nowPtr := now
		autoAcceptAt = &nowPtr
	case "accept-after":
		acceptType = models.AcceptTypeAcceptAfter
		if action.Seconds > 0 {
			autoAcceptIn = &action.Seconds
			if !q.isPaused {
				acceptAt := now + int64(action.Seconds*1000)
				autoAcceptAt = &acceptAt
			}
		}
	default:
		acceptType = models.AcceptTypeManual
	}

	prompt := &models.Prompt{
		ID:            id,
		SessionID:     input.SessionID,
		ToolName:      input.ToolName,
		ToolInput:     input.ToolInput,
		HookEventName: input.HookEventName,
		CWD:           input.CWD,
		CreatedAt:     now,
		AcceptType:    acceptType,
		AutoAcceptIn:  autoAcceptIn,
		AutoAcceptAt:  autoAcceptAt,
	}

	resolveChan := make(chan *models.Decision, 1)
	pending := &PendingPrompt{
		Prompt:      prompt,
		ResolveChan: resolveChan,
	}

	q.prompts[id] = pending
	q.log("Added prompt: %s (%s) - type: %s", id, input.ToolName, acceptType)

	// Set up timer if needed
	q.setupTimer(id, pending, &action)

	q.mu.Unlock()

	// Notify observers
	if q.callbacks != nil && q.callbacks.OnPromptAdded != nil {
		q.callbacks.OnPromptAdded(prompt)
	}

	// Wait for resolution
	decision := <-resolveChan
	return decision, nil
}

// setupTimer sets up auto-accept timer
func (q *Queue) setupTimer(id string, pending *PendingPrompt, action *models.RuleAction) {
	// Clear existing timer
	if pending.Timer != nil {
		pending.Timer.Stop()
		pending.Timer = nil
	}

	// Handle immediate auto-accept
	if action.Type == "auto-accept" {
		pending.Timer = time.AfterFunc(0, func() {
			q.Resolve(id, &models.Decision{
				Decision: "allow",
				Reason:   strPtr("Auto-accepted immediately"),
			}, true)
		})
		return
	}

	// Only set up timer for accept-after rules
	if action.Type != "accept-after" || action.Seconds <= 0 {
		return
	}

	// Don't start timer if globally paused
	if q.isPaused {
		q.pausedRemaining[id] = time.Duration(action.Seconds) * time.Second
		return
	}

	duration := time.Duration(action.Seconds) * time.Second
	pending.Timer = time.AfterFunc(duration, func() {
		q.Resolve(id, &models.Decision{
			Decision: "allow",
			Reason:   strPtr("Auto-accepted by timer"),
		}, true)
	})
}

// Resolve resolves a prompt with a decision
func (q *Queue) Resolve(id string, decision *models.Decision, autoAccepted bool) bool {
	q.mu.Lock()
	defer q.mu.Unlock()

	pending, exists := q.prompts[id]
	if !exists {
		return false
	}

	q.log("Resolving prompt: %s - decision: %s (auto: %v)", id, decision.Decision, autoAccepted)

	// Stop timer if exists
	if pending.Timer != nil {
		pending.Timer.Stop()
		pending.Timer = nil
	}

	// Remove from queue
	delete(q.prompts, id)
	delete(q.pausedRemaining, id)

	// Send decision to waiting goroutine
	select {
	case pending.ResolveChan <- decision:
	default:
	}
	close(pending.ResolveChan)

	// Notify observers
	if q.callbacks != nil && q.callbacks.OnPromptResolved != nil {
		q.callbacks.OnPromptResolved(id, autoAccepted)
	}

	return true
}

// List returns all pending prompts
func (q *Queue) List() []*models.Prompt {
	q.mu.RLock()
	defer q.mu.RUnlock()

	prompts := make([]*models.Prompt, 0, len(q.prompts))
	for _, p := range q.prompts {
		prompts = append(prompts, p.Prompt)
	}
	return prompts
}

// SetPaused pauses or resumes all auto-accept timers
func (q *Queue) SetPaused(paused bool) {
	q.mu.Lock()
	defer q.mu.Unlock()

	if q.isPaused == paused {
		return
	}

	q.isPaused = paused
	q.log("Global pause: %v", paused)

	if paused {
		// Pausing: save remaining time and clear timers
		now := time.Now()
		for id, pending := range q.prompts {
			if pending.Timer != nil {
				// Calculate remaining time
				if pending.AutoAcceptAt != nil {
					remaining := time.Until(time.UnixMilli(*pending.AutoAcceptAt))
					if remaining > 0 {
						q.pausedRemaining[id] = remaining
						remainingSecs := int(remaining.Seconds() + 0.5)
						pending.AutoAcceptIn = &remainingSecs
					}
				}
				pending.Timer.Stop()
				pending.Timer = nil
			}
			// Clear autoAcceptAt (signals paused state to clients)
			pending.AutoAcceptAt = nil

			// Notify observers of update
			if q.callbacks != nil && q.callbacks.OnPromptUpdated != nil {
				q.callbacks.OnPromptUpdated(pending.Prompt)
			}
		}
		q.log("Paused %d timers at %s", len(q.pausedRemaining), now.Format(time.RFC3339))
	} else {
		// Resuming: restart timers with remaining time
		now := models.GetCurrentTimeMillis()
		for id, pending := range q.prompts {
			remaining, exists := q.pausedRemaining[id]
			if exists && remaining > 0 {
				// Update autoAcceptAt to new time
				acceptAt := now + remaining.Milliseconds()
				pending.AutoAcceptAt = &acceptAt

				// Restart timer
				pending.Timer = time.AfterFunc(remaining, func() {
					q.Resolve(id, &models.Decision{
						Decision: "allow",
						Reason:   strPtr("Auto-accepted by timer"),
					}, true)
				})

				// Notify observers of update
				if q.callbacks != nil && q.callbacks.OnPromptUpdated != nil {
					q.callbacks.OnPromptUpdated(pending.Prompt)
				}
			}
			delete(q.pausedRemaining, id)
		}
		q.log("Resumed %d timers", len(q.prompts))
	}
}

// IsPaused returns whether the queue is paused
func (q *Queue) IsPaused() bool {
	q.mu.RLock()
	defer q.mu.RUnlock()
	return q.isPaused
}

// GetSettings returns current settings
func (q *Queue) GetSettings() *models.Settings {
	q.mu.RLock()
	defer q.mu.RUnlock()
	return q.settings
}

// UpdateSettings updates settings
func (q *Queue) UpdateSettings(updates *models.Settings) *models.Settings {
	q.mu.Lock()
	defer q.mu.Unlock()

	if updates.Rules != nil {
		q.settings.Rules = updates.Rules
	}
	// Merge native settings
	q.settings.Native = updates.Native

	return q.settings
}

// matchRules finds the first matching rule for a tool
func (q *Queue) matchRules(toolName string, toolInput map[string]interface{}) models.RuleAction {
	category := getToolCategory(toolName)

	for i := range q.settings.Rules {
		rule := &q.settings.Rules[i]
		if !rule.Enabled {
			continue
		}

		// Check tool name match
		if rule.ToolName != "" && rule.ToolName == toolName {
			rule.MatchCount++
			return rule.Action
		}

		// Check category match
		if rule.Category != "" && rule.Category == category {
			rule.MatchCount++
			return rule.Action
		}

		// Pattern matching not implemented yet
		// TODO: Add JavaScript expression evaluation for patterns
	}

	// Default: manual approval
	return models.RuleAction{Type: "manual"}
}

// getToolCategory returns the category for a tool
func getToolCategory(toolName string) string {
	// MCP tools
	if len(toolName) >= 5 && toolName[:5] == "mcp__" {
		return "mcp"
	}

	// Read tools
	readTools := map[string]bool{
		"Read": true, "Glob": true, "Grep": true,
		"TaskList": true, "TaskGet": true, "TaskOutput": true,
		"ListMcpResourcesTool": true, "ReadMcpResourceTool": true,
		"ToolSearch": true,
	}
	if readTools[toolName] {
		return "read"
	}

	// Write tools
	writeTools := map[string]bool{
		"Edit": true, "Write": true, "NotebookEdit": true,
		"TaskCreate": true, "TaskUpdate": true,
	}
	if writeTools[toolName] {
		return "write"
	}

	// Execute tools
	executeTools := map[string]bool{
		"Bash": true, "KillShell": true,
		"Task": true, "Skill": true,
	}
	if executeTools[toolName] {
		return "execute"
	}

	// Web tools
	webTools := map[string]bool{
		"WebFetch": true, "WebSearch": true,
	}
	if webTools[toolName] {
		return "web"
	}

	// Interactive tools
	interactiveTools := map[string]bool{
		"AskUserQuestion": true,
		"ExitPlanMode":    true,
		"EnterPlanMode":   true,
	}
	if interactiveTools[toolName] {
		return "interactive"
	}

	return "other"
}

// Helper function
func strPtr(s string) *string {
	return &s
}
