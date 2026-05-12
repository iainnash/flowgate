package queue

import (
	"testing"
	"time"

	"github.com/iainnash/flowgate/go-server/models"
)

func newTestQueue(rules []models.Rule) *Queue {
	return &Queue{
		prompts:         make(map[string]*PendingPrompt),
		settings:        &models.Settings{Rules: rules},
		pausedRemaining: make(map[string]time.Duration),
	}
}

func TestMatchRulesRequiresAllSpecifiedCriteria(t *testing.T) {
	q := newTestQueue([]models.Rule{
		{
			Name:     "Impossible mixed criteria",
			ToolName: "Bash",
			Category: "read",
			Action:   models.RuleAction{Type: "auto-accept"},
			Enabled:  true,
		},
	})

	action := q.matchRules("Bash", map[string]interface{}{"command": "pnpm test"})

	if action.Type != "manual" {
		t.Fatalf("expected no rule match to fall back to manual, got %q", action.Type)
	}
}

func TestMatchRulesSelectsMostPermissiveMatchingAction(t *testing.T) {
	q := newTestQueue([]models.Rule{
		{
			Name:     "Execute after delay",
			Category: "execute",
			Action:   models.RuleAction{Type: "accept-after", Seconds: 10},
			Enabled:  true,
		},
		{
			Name:     "Specific bash auto accept",
			ToolName: "Bash",
			Pattern:  "^pnpm test$",
			Action:   models.RuleAction{Type: "auto-accept"},
			Enabled:  true,
		},
		{
			Name:     "Disabled deny-by-manual",
			ToolName: "Bash",
			Action:   models.RuleAction{Type: "manual"},
			Enabled:  false,
		},
	})

	action := q.matchRules("Bash", map[string]interface{}{"command": "pnpm test"})

	if action.Type != "auto-accept" {
		t.Fatalf("expected most permissive matching rule to win, got %q", action.Type)
	}

	if q.settings.Rules[0].MatchCount != 1 {
		t.Fatalf("expected category rule match count to increment, got %d", q.settings.Rules[0].MatchCount)
	}
	if q.settings.Rules[1].MatchCount != 1 {
		t.Fatalf("expected specific rule match count to increment, got %d", q.settings.Rules[1].MatchCount)
	}
	if q.settings.Rules[2].MatchCount != 0 {
		t.Fatalf("expected disabled rule not to match, got %d", q.settings.Rules[2].MatchCount)
	}
}

func TestResolveRemovesPromptAndNotifies(t *testing.T) {
	q := newTestQueue(nil)
	resolveChan := make(chan *models.Decision, 1)
	timer := time.AfterFunc(time.Hour, func() {})
	defer timer.Stop()

	q.prompts["prompt-1"] = &PendingPrompt{
		Prompt: &models.Prompt{
			ID:       "prompt-1",
			ToolName: "Bash",
		},
		ResolveChan: resolveChan,
		Timer:       timer,
	}
	q.pausedRemaining["prompt-1"] = time.Second

	var callbackID string
	var callbackAutoAccepted bool
	q.SetCallbacks(&Callbacks{
		OnPromptResolved: func(id string, autoAccepted bool) {
			callbackID = id
			callbackAutoAccepted = autoAccepted
		},
	})

	decision := &models.Decision{Decision: "deny"}
	if ok := q.Resolve("prompt-1", decision, true); !ok {
		t.Fatal("expected Resolve to return true for an existing prompt")
	}

	if _, exists := q.prompts["prompt-1"]; exists {
		t.Fatal("expected resolved prompt to be removed")
	}
	if _, exists := q.pausedRemaining["prompt-1"]; exists {
		t.Fatal("expected paused timer state to be removed")
	}
	if callbackID != "prompt-1" || !callbackAutoAccepted {
		t.Fatalf("unexpected callback values: id=%q autoAccepted=%v", callbackID, callbackAutoAccepted)
	}

	got, ok := <-resolveChan
	if !ok {
		t.Fatal("expected decision before resolve channel closes")
	}
	if got != decision {
		t.Fatalf("expected decision pointer %p, got %p", decision, got)
	}
	if _, ok := <-resolveChan; ok {
		t.Fatal("expected resolve channel to be closed")
	}
}

func TestSetPausedUpdatesAndRestartsTimers(t *testing.T) {
	q := newTestQueue(nil)
	acceptIn := 5
	acceptAt := models.GetCurrentTimeMillis() + int64(acceptIn*1000)
	timer := time.AfterFunc(time.Duration(acceptIn)*time.Second, func() {})
	defer timer.Stop()

	prompt := &models.Prompt{
		ID:           "prompt-1",
		AcceptType:   models.AcceptTypeAcceptAfter,
		AutoAcceptIn: &acceptIn,
		AutoAcceptAt: &acceptAt,
	}
	q.prompts[prompt.ID] = &PendingPrompt{
		Prompt:      prompt,
		ResolveChan: make(chan *models.Decision, 1),
		Timer:       timer,
	}

	updateCount := 0
	q.SetCallbacks(&Callbacks{
		OnPromptUpdated: func(*models.Prompt) {
			updateCount++
		},
	})

	q.SetPaused(true)

	if !q.isPaused {
		t.Fatal("expected queue to be paused")
	}
	if q.prompts[prompt.ID].Timer != nil {
		t.Fatal("expected timer to be cleared while paused")
	}
	if q.prompts[prompt.ID].AutoAcceptAt != nil {
		t.Fatal("expected autoAcceptAt to be cleared while paused")
	}
	if remaining := q.pausedRemaining[prompt.ID]; remaining <= 0 {
		t.Fatalf("expected remaining pause duration, got %s", remaining)
	}

	q.SetPaused(false)

	if q.isPaused {
		t.Fatal("expected queue to be resumed")
	}
	if q.prompts[prompt.ID].Timer == nil {
		t.Fatal("expected timer to be restarted on resume")
	}
	if q.prompts[prompt.ID].AutoAcceptAt == nil {
		t.Fatal("expected autoAcceptAt to be restored on resume")
	}
	if _, exists := q.pausedRemaining[prompt.ID]; exists {
		t.Fatal("expected paused remaining state to be cleared on resume")
	}
	if updateCount != 2 {
		t.Fatalf("expected one update for pause and one for resume, got %d", updateCount)
	}
}
